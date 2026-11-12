import 'dart:async';

import 'package:meta/meta.dart';

import '../channel/card_scanner_platform.dart';

/// Which build of the browser engine runs the models.
///
/// Both are the same PaddleOCR pipeline bundled from the same sources.
/// They differ in where the two model graphs execute, and that is all.
enum OcrBackend {
  /// On the GPU, through WebGPU. Tried first where the browser has it.
  webGpu,

  /// In WebAssembly, on one thread. Runs in every browser the scanner
  /// supports, and is what a failed WebGPU load falls back to.
  wasm,
}

/// What the browser engine said about itself when a scan loaded it.
///
/// Diagnostics for a host app that wants to know which path its users are
/// on. It carries no card data: a backend, two durations and a reason.
@immutable
class OcrEngineReport {
  /// A report that [backend] was the build in play, that WebAssembly took
  /// [benchmark] for the timing loop, that the engine was usable after
  /// [loadTime], that it was given up on when [tooSlow], and that WebGPU
  /// was passed over because of [webGpuFailure].
  const OcrEngineReport({
    required this.backend,
    this.benchmark,
    this.loadTime,
    this.tooSlow = false,
    this.webGpuFailure,
  });

  /// The build this report is about: the one that loaded, or the last one
  /// that was tried.
  final OcrBackend backend;

  /// How long the WebAssembly timing loop took, fastest of three runs.
  ///
  /// Only measured on [OcrBackend.wasm], where it decides [tooSlow]. An
  /// iPhone takes 4 to 15 ms normally; 55 ms and more is the slow state
  /// some iOS 27 Safari processes get into.
  final Duration? benchmark;

  /// How long it took from starting the worker to an engine that can read
  /// a frame. `null` when it never got that far.
  final Duration? loadTime;

  /// Whether the engine was abandoned because WebAssembly runs too slowly
  /// here for a scan to finish. The scanner reported
  /// [CardScannerException.tooSlow] and sent no frames.
  final bool tooSlow;

  /// Why WebGPU was not used although the browser offered it, when this
  /// load was the one that found out. `null` on a load that never tried
  /// WebGPU, which includes every later load on the same page.
  final String? webGpuFailure;

  /// Whether an engine was left running to read frames.
  bool get isLoaded => loadTime != null;

  @override
  String toString() =>
      'OcrEngineReport(${backend.name}'
      '${benchmark == null ? '' : ', benchmark ${benchmark!.inMilliseconds} ms'}'
      '${loadTime == null ? '' : ', loaded in ${loadTime!.inMilliseconds} ms'}'
      '${tooSlow ? ', too slow' : ''}'
      '${webGpuFailure == null ? '' : ', WebGPU failed: $webGpuFailure'})';
}

/// Where engine reports go on their way out of the package.
///
/// A broadcast of its own rather than a member of [CardScannerPlatform]:
/// only the browser has anything to say here, and adding to that interface
/// breaks every fake of it for the sake of a stream that stays silent on a
/// phone.
abstract final class OcrEngineReports {
  static final _reports = StreamController<OcrEngineReport>.broadcast();
  static OcrEngineReport? _last;

  /// Every report, as it is made.
  static Stream<OcrEngineReport> get stream => _reports.stream;

  /// The most recent report, for a listener that arrived after it.
  static OcrEngineReport? get last => _last;

  /// Publishes [report].
  static void add(OcrEngineReport report) {
    _last = report;
    _reports.add(report);
  }
}

/// One engine worker, as far as choosing between builds goes.
///
/// The browser's `Worker` sits behind this so the choosing can be tested
/// without a browser.
abstract interface class EngineWorker {
  /// Completes once the worker's script has run and is listening. Fails
  /// when the script could not be fetched at all.
  Future<void> get started;

  /// Times a short fixed WebAssembly loop inside the worker, in
  /// milliseconds. `null` when it could not be timed.
  ///
  /// Loads nothing, so it is safe to ask before [load].
  Future<double?> benchmark();

  /// Loads OpenCV, the runtime and the models. Fails with the reason when
  /// any of them is missing or will not start.
  Future<void> load();

  /// Stops the worker and fails whatever was still waiting on it.
  void terminate();
}

/// What a page has learned about its engines, kept for as long as the
/// page lives.
///
/// A WebGPU load that failed will fail again: the browser has no adapter,
/// or keeps WebGPU from workers, and neither changes between two scans.
/// Trying it every time would add the failure to every scan.
class EngineMemory {
  /// Whether WebGPU was tried on this page and did not load.
  bool webGpuFailed = false;

  /// The memory every scanner on the page shares.
  static final page = EngineMemory();
}

/// Chooses a build of the engine and loads it: WebGPU first where the
/// browser has it, WebAssembly once that fails, and nothing at all where
/// WebAssembly is too slow to finish a scan.
///
/// Loading is its own step, apart from frames, because the two fail for
/// different reasons and want different answers. A load that fails means
/// try the other build. A frame that fails means try the next frame.
class EngineLoader<W extends EngineWorker> {
  /// A loader starting workers with [launch].
  ///
  /// [webGpuAvailable] says whether the page has WebGPU, which is what
  /// makes it worth trying. [loadTimeout] bounds each build's load.
  /// [slowAbove] is the benchmark time past which WebAssembly is taken to
  /// be in the slow state. [memory] carries a failed WebGPU load from one
  /// scan to the next, and [onReport] hears what happened.
  EngineLoader({
    required this.launch,
    required this.webGpuAvailable,
    this.loadTimeout = const Duration(minutes: 2),
    this.slowAbove = defaultSlowAbove,
    EngineMemory? memory,
    this.onReport,
  }) : memory = memory ?? EngineMemory.page;

  /// The benchmark time past which a scan is not attempted.
  ///
  /// Between the two states with room on both sides: an iPhone in its
  /// normal state takes 4 to 15 ms, one in the slow state 55 to 87 ms, and
  /// desktop Chromium under load has been seen at 33 ms for a single run.
  static const defaultSlowAbove = Duration(milliseconds: 40);

  /// Starts the worker for a build.
  final W Function(OcrBackend backend) launch;

  /// Whether the page has WebGPU.
  final bool Function() webGpuAvailable;

  /// How long one build has to become usable.
  ///
  /// This is what a slow connection is given to fetch the engine, tens of
  /// megabytes the first time.
  final Duration loadTimeout;

  /// The benchmark time past which WebAssembly is taken to be too slow.
  final Duration slowAbove;

  /// What earlier loads on this page found out.
  final EngineMemory memory;

  /// Called once per load with what happened, whether it worked or not.
  final void Function(OcrEngineReport report)? onReport;

  W? _current;
  bool _cancelled = false;

  /// Loads an engine and returns its worker, ready for frames.
  ///
  /// Throws [CardScannerException.tooSlow] when WebAssembly is in the slow
  /// state, and whatever the load failed with otherwise. No worker is left
  /// running after a failure.
  Future<W> load() async {
    String? webGpuFailure;

    if (!memory.webGpuFailed && webGpuAvailable()) {
      final watch = Stopwatch()..start();
      final worker = _start(OcrBackend.webGpu);
      try {
        await _bounded(() async {
          await worker.started;
          await worker.load();
        });
        _checkWanted();
        // No benchmark on this path. The phones that are too slow in
        // WebAssembly read cards here at about a second a frame, because
        // the models are the slow part and they are on the GPU.
        _report(
          OcrEngineReport(backend: OcrBackend.webGpu, loadTime: watch.elapsed),
        );
        return worker;
      } catch (error) {
        _stop(worker);
        // A scan closed while it loaded says nothing about WebGPU.
        _checkWanted();
        memory.webGpuFailed = true;
        webGpuFailure = _reason(error);
      }
    }

    final watch = Stopwatch()..start();
    final worker = _start(OcrBackend.wasm);
    Duration? benchmark;
    try {
      await _bounded(() async {
        await worker.started;

        // Asked before the load, so a browser in the slow state does not
        // fetch and compile an engine it is about to throw away.
        benchmark = _duration(await worker.benchmark());
        if (_tooSlow(benchmark)) throw _slow(benchmark!);

        await worker.load();

        // And again after it, which is where the slow state was actually
        // measured in the field. Nobody has shown that it is always there
        // before the engine is in memory, and a second look costs a few
        // milliseconds.
        final loaded = _duration(await worker.benchmark());
        benchmark = loaded ?? benchmark;
        if (_tooSlow(loaded)) throw _slow(loaded!);
      });
      _checkWanted();
    } catch (error) {
      _stop(worker);
      _checkWanted();
      _report(
        OcrEngineReport(
          backend: OcrBackend.wasm,
          benchmark: benchmark,
          tooSlow: _isTooSlow(error),
          webGpuFailure: webGpuFailure,
        ),
      );
      rethrow;
    }

    _report(
      OcrEngineReport(
        backend: OcrBackend.wasm,
        benchmark: benchmark,
        loadTime: watch.elapsed,
        webGpuFailure: webGpuFailure,
      ),
    );
    return worker;
  }

  /// Gives up on a load in progress: stops its worker and starts no other.
  ///
  /// The [load] it interrupts fails. Nothing is remembered or reported
  /// about it, because it says nothing about the browser.
  void cancel() {
    _cancelled = true;
    final worker = _current;
    if (worker != null) _stop(worker);
  }

  W _start(OcrBackend backend) {
    _checkWanted();
    return _current = launch(backend);
  }

  void _stop(W worker) {
    if (identical(_current, worker)) _current = null;
    worker.terminate();
  }

  void _checkWanted() {
    if (_cancelled) throw StateError('The engine load was cancelled');
  }

  Future<void> _bounded(Future<void> Function() steps) =>
      steps().timeout(loadTimeout);

  void _report(OcrEngineReport report) => onReport?.call(report);

  bool _tooSlow(Duration? benchmark) =>
      benchmark != null && benchmark > slowAbove;

  CardScannerException _slow(Duration benchmark) => CardScannerException(
    CardScannerException.tooSlow,
    'WebAssembly is running too slowly in this browser to scan a card: '
    'the timing loop took ${benchmark.inMilliseconds} ms, and a scan is '
    'not attempted above ${slowAbove.inMilliseconds} ms',
  );

  static bool _isTooSlow(Object error) =>
      error is CardScannerException &&
      error.code == CardScannerException.tooSlow;

  static Duration? _duration(double? milliseconds) =>
      milliseconds == null || !milliseconds.isFinite || milliseconds < 0
      ? null
      : Duration(microseconds: (milliseconds * 1000).round());

  static String _reason(Object error) => error is TimeoutException
      ? 'the load timed out'
      : error is StateError
      ? error.message
      : '$error';
}
