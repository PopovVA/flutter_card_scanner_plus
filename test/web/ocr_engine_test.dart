import 'dart:async';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_card_scanner_plus/src/web/ocr_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// A worker a test scripts: whether its script arrives, how fast it says
/// WebAssembly is, and whether its engine loads.
class FakeWorker implements EngineWorker {
  FakeWorker(this.backend);

  final OcrBackend backend;

  /// Fails the script fetch while set.
  Object? startError;

  /// Fails the engine load while set.
  Object? loadError;

  /// Never finishes loading while set, so the loader has to time out or
  /// be cancelled.
  bool hangLoad = false;

  /// What each benchmark answers, in order. The last one repeats.
  List<double?> benchmarks = [8];

  int benchmarkCalls = 0;
  int loads = 0;
  bool terminated = false;

  final _hung = Completer<void>();

  @override
  Future<void> get started async {
    final failure = startError;
    if (failure != null) throw failure;
  }

  @override
  Future<double?> benchmark() async {
    final at = benchmarkCalls++;
    return benchmarks[at < benchmarks.length ? at : benchmarks.length - 1];
  }

  @override
  Future<void> load() async {
    loads++;
    if (hangLoad) return _hung.future;
    final failure = loadError;
    if (failure != null) throw failure;
  }

  @override
  void terminate() {
    terminated = true;
    if (!_hung.isCompleted) {
      _hung.future.ignore();
      _hung.completeError(StateError('terminated'));
    }
  }
}

void main() {
  late List<FakeWorker> launched;
  late List<OcrEngineReport> reports;
  late EngineMemory memory;

  /// Runs before a worker is handed to the loader, to script it.
  void Function(FakeWorker worker)? arrange;

  setUp(() {
    launched = [];
    reports = [];
    memory = EngineMemory();
    arrange = null;
  });

  EngineLoader<FakeWorker> loaderFor({
    bool webGpu = true,
    Duration loadTimeout = const Duration(seconds: 5),
  }) => EngineLoader<FakeWorker>(
    launch: (backend) {
      final worker = FakeWorker(backend);
      arrange?.call(worker);
      launched.add(worker);
      return worker;
    },
    webGpuAvailable: () => webGpu,
    loadTimeout: loadTimeout,
    memory: memory,
    onReport: reports.add,
  );

  List<OcrBackend> backends() => [for (final w in launched) w.backend];

  group('choosing a build', () {
    test('WebGPU is tried first where the browser has it', () async {
      final worker = await loaderFor().load();

      expect(worker.backend, OcrBackend.webGpu);
      expect(backends(), [OcrBackend.webGpu]);
      expect(worker.loads, 1);
      expect(worker.terminated, isFalse);
      expect(reports.single.backend, OcrBackend.webGpu);
      expect(reports.single.isLoaded, isTrue);
    });

    test('a browser without WebGPU goes straight to WebAssembly', () async {
      final worker = await loaderFor(webGpu: false).load();

      expect(worker.backend, OcrBackend.wasm);
      expect(backends(), [OcrBackend.wasm]);
      expect(reports.single.webGpuFailure, isNull);
    });

    test('a WebGPU load that fails hands over to WebAssembly', () async {
      arrange = (worker) {
        if (worker.backend == OcrBackend.webGpu) {
          worker.loadError = StateError('WebGPU has no adapter');
        }
      };

      final worker = await loaderFor().load();

      expect(worker.backend, OcrBackend.wasm);
      expect(backends(), [OcrBackend.webGpu, OcrBackend.wasm]);
      expect(launched.first.terminated, isTrue, reason: 'nothing left over');
      expect(worker.terminated, isFalse);
      expect(reports.single.backend, OcrBackend.wasm);
      expect(reports.single.webGpuFailure, 'WebGPU has no adapter');
    });

    test('a WebGPU worker that cannot be fetched does the same', () async {
      arrange = (worker) {
        if (worker.backend == OcrBackend.webGpu) {
          worker.startError = StateError('404');
        }
      };

      final worker = await loaderFor().load();

      expect(worker.backend, OcrBackend.wasm);
      expect(launched.first.loads, 0);
    });

    test('a WebGPU load that never finishes is given up on', () async {
      arrange = (worker) =>
          worker.hangLoad = worker.backend == OcrBackend.webGpu;

      final worker = await loaderFor(
        loadTimeout: const Duration(milliseconds: 30),
      ).load();

      expect(worker.backend, OcrBackend.wasm);
      expect(launched.first.terminated, isTrue);
      expect(reports.single.webGpuFailure, 'the load timed out');
    });

    test('the page remembers that WebGPU failed', () async {
      arrange = (worker) {
        if (worker.backend == OcrBackend.webGpu) {
          worker.loadError = StateError('no');
        }
      };
      await loaderFor().load();
      launched.clear();
      reports.clear();

      // A second scan on the same page, with WebGPU working this time: it
      // is not asked.
      arrange = null;
      final worker = await loaderFor().load();

      expect(worker.backend, OcrBackend.wasm);
      expect(backends(), [OcrBackend.wasm]);
      expect(reports.single.webGpuFailure, isNull);
    });

    test('nothing is remembered about a WebGPU load that worked', () async {
      await loaderFor().load();
      launched.clear();

      final worker = await loaderFor().load();

      expect(worker.backend, OcrBackend.webGpu);
    });

    test('a WebAssembly load that fails leaves no worker behind', () async {
      arrange = (worker) => worker.loadError = StateError('missing model');

      await expectLater(loaderFor().load(), throwsStateError);

      expect(backends(), [OcrBackend.webGpu, OcrBackend.wasm]);
      expect(launched.every((worker) => worker.terminated), isTrue);
      expect(reports.single.isLoaded, isFalse);
      expect(reports.single.tooSlow, isFalse);
    });
  });

  group('a browser too slow to scan in', () {
    Matcher throwsTooSlow = throwsA(
      isA<CardScannerException>().having(
        (e) => e.code,
        'code',
        CardScannerException.tooSlow,
      ),
    );

    test('is found out before anything is loaded', () async {
      arrange = (worker) => worker.benchmarks = [72];

      await expectLater(loaderFor(webGpu: false).load(), throwsTooSlow);

      final worker = launched.single;
      expect(worker.loads, 0, reason: 'no engine fetched to be thrown away');
      expect(worker.terminated, isTrue);
      expect(reports.single.tooSlow, isTrue);
      expect(reports.single.isLoaded, isFalse);
      expect(reports.single.benchmark, const Duration(milliseconds: 72));
    });

    test('is found out after the load when it only shows then', () async {
      arrange = (worker) => worker.benchmarks = [9, 61];

      await expectLater(loaderFor(webGpu: false).load(), throwsTooSlow);

      final worker = launched.single;
      expect(worker.loads, 1);
      expect(worker.terminated, isTrue, reason: 'the engine is freed');
      expect(reports.single.tooSlow, isTrue);
      expect(reports.single.benchmark, const Duration(milliseconds: 61));
    });

    test('the threshold itself still scans', () async {
      arrange = (worker) => worker.benchmarks = [40];

      final worker = await loaderFor(webGpu: false).load();

      expect(worker.terminated, isFalse);
      expect(reports.single.tooSlow, isFalse);
      expect(reports.single.benchmark, const Duration(milliseconds: 40));
    });

    test('just past the threshold does not', () async {
      arrange = (worker) => worker.benchmarks = [40.5];

      await expectLater(loaderFor(webGpu: false).load(), throwsTooSlow);
    });

    test(
      'WebGPU is not benchmarked: the same phones read cards there',
      () async {
        arrange = (worker) => worker.benchmarks = [80];

        final worker = await loaderFor().load();

        expect(worker.backend, OcrBackend.webGpu);
        expect(worker.benchmarkCalls, 0);
        expect(reports.single.benchmark, isNull);
      },
    );

    test('falling back from WebGPU into the slow state says both', () async {
      arrange = (worker) {
        if (worker.backend == OcrBackend.webGpu) {
          worker.loadError = StateError('no adapter');
        } else {
          worker.benchmarks = [66];
        }
      };

      await expectLater(loaderFor().load(), throwsTooSlow);

      expect(reports.single.tooSlow, isTrue);
      expect(reports.single.webGpuFailure, 'no adapter');
      expect(launched.every((worker) => worker.terminated), isTrue);
    });

    test('a benchmark that could not be run does not stop a scan', () async {
      arrange = (worker) => worker.benchmarks = [null];

      final worker = await loaderFor(webGpu: false).load();

      expect(worker.loads, 1);
      expect(reports.single.benchmark, isNull);
    });

    test('the message carries the measurement, for a log', () async {
      arrange = (worker) => worker.benchmarks = [72];

      Object? caught;
      try {
        await loaderFor(webGpu: false).load();
      } catch (error) {
        caught = error;
      }

      expect((caught! as CardScannerException).message, contains('72 ms'));
    });
  });

  group('a load that is cancelled', () {
    test('stops its worker and starts no other', () async {
      arrange = (worker) => worker.hangLoad = true;
      final loader = loaderFor();

      final loading = loader.load();
      await Future<void>.delayed(Duration.zero);
      loader.cancel();

      await expectLater(loading, throwsStateError);
      expect(backends(), [OcrBackend.webGpu], reason: 'no fallback started');
      expect(launched.single.terminated, isTrue);
    });

    test('says nothing about WebGPU, and reports nothing', () async {
      arrange = (worker) => worker.hangLoad = true;
      final loader = loaderFor();

      final loading = loader.load();
      await Future<void>.delayed(Duration.zero);
      loader.cancel();
      await expectLater(loading, throwsStateError);

      expect(memory.webGpuFailed, isFalse);
      expect(reports, isEmpty);
    });
  });

  group('reports', () {
    test('reach a listener and stay available afterwards', () async {
      const report = OcrEngineReport(
        backend: OcrBackend.wasm,
        benchmark: Duration(milliseconds: 9),
        loadTime: Duration(seconds: 2),
      );
      final heard = <OcrEngineReport>[];
      final listening = CardScanner.engineReports.listen(heard.add);
      addTearDown(listening.cancel);

      OcrEngineReports.add(report);
      await Future<void>.delayed(Duration.zero);

      expect(heard, [report]);
      expect(CardScanner.lastEngineReport, report);
    });

    test('describe themselves without any card data', () {
      const report = OcrEngineReport(
        backend: OcrBackend.wasm,
        benchmark: Duration(milliseconds: 72),
        tooSlow: true,
        webGpuFailure: 'no adapter',
      );

      expect(
        '$report',
        'OcrEngineReport(wasm, benchmark 72 ms, too slow, '
            'WebGPU failed: no adapter)',
      );
    });
  });
}
