import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../channel/card_scanner_platform.dart';
import '../core/recognized_text.dart';
import 'ocr_engine.dart';
import 'scan_crop.dart';
import 'scan_loop.dart';

/// Where the browser scanner loads its recognizer from.
///
/// The files are served by the app, not bundled into the package: the
/// models and the runtimes come to about 50 MB, which has no business
/// inside an iOS or Android build.
/// `dart run flutter_card_scanner_plus:install_web` puts them in place.
abstract final class OcrAssets {
  /// Folder the installer writes to, under the app's `web/`.
  static const defaultDirectory = 'flutter_card_scanner_plus';

  /// The worker that runs the models in WebAssembly.
  static const workerFile = 'card_ocr_worker.js';

  /// The worker that runs the models on the GPU.
  static const webGpuWorkerFile = 'card_ocr_worker_webgpu.js';

  /// The worker script for [backend], inside the folder.
  static String workerFor(OcrBackend backend) => switch (backend) {
    OcrBackend.webGpu => webGpuWorkerFile,
    OcrBackend.wasm => workerFile,
  };
}

/// Runs the OCR engine in a Web Worker and speaks to it one frame at a
/// time.
///
/// A worker rather than the page: recognition takes up to a second, and a
/// second of a blocked main thread is a frozen app. The worker is classic
/// rather than a module, because the engine loads OpenCV with
/// `importScripts`.
///
/// There are two workers to choose from, and [EngineLoader] does the
/// choosing: the WebGPU build where the browser has WebGPU, the
/// WebAssembly build once that fails to load, and no engine at all where
/// WebAssembly is too slow to finish a scan.
class OcrWorker implements ScanRecognizer {
  /// A recognizer loading its worker from [directory], which is a path
  /// under the app's web root.
  ///
  /// [loadTimeout] bounds the load of one build, which waits for tens of
  /// megabytes of models and runtime to arrive. Without it a missing file
  /// leaves the scanner saying it is getting ready for ever.
  ///
  /// [slowAbove] is how long the WebAssembly timing loop may take before
  /// the browser is taken to be too slow to scan in, and [onReport] hears
  /// which build loaded and how that loop went.
  OcrWorker({
    this.directory = OcrAssets.defaultDirectory,
    this.loadTimeout = const Duration(minutes: 2),
    this.slowAbove = EngineLoader.defaultSlowAbove,
    this.onReport,
  });

  /// Folder the engine was installed into, under the app's web root.
  final String directory;

  /// How long one build of the engine has to become usable.
  final Duration loadTimeout;

  /// The benchmark time past which a scan is not attempted.
  final Duration slowAbove;

  /// Called with what each load found.
  final void Function(OcrEngineReport report)? onReport;

  _BrowserWorker? _worker;
  Future<_BrowserWorker>? _loading;
  EngineLoader<_BrowserWorker>? _loader;

  /// Whether a worker is loaded and answering.
  bool get isLoaded => _worker != null;

  /// Whether the page has WebGPU at all.
  ///
  /// The page having it does not promise the worker does. The WebGPU
  /// worker checks for itself and fails its load, which is what moves the
  /// scanner on to WebAssembly.
  static bool get pageHasWebGpu {
    final navigator = web.window.navigator as JSObject;
    return navigator.has('gpu') && navigator['gpu'].isDefinedAndNotNull;
  }

  @override
  Future<void> prepare() => _ready();

  @override
  Future<RecognizedFrame> recognize(Object frame, ScanCrop crop) async {
    final worker = await _ready();
    return worker.recognize(frame as web.ImageBitmap);
  }

  /// Loads an engine if needed and returns its worker once it can read a
  /// frame.
  Future<_BrowserWorker> _ready() => _loading ??= _load();

  Future<_BrowserWorker> _load() async {
    final loader = _loader = EngineLoader<_BrowserWorker>(
      launch: (backend) =>
          _BrowserWorker('$directory/${OcrAssets.workerFor(backend)}'),
      webGpuAvailable: () => pageHasWebGpu,
      loadTimeout: loadTimeout,
      slowAbove: slowAbove,
      onReport: onReport,
    );
    try {
      return _worker = await loader.load();
    } catch (error) {
      // Forgotten rather than kept: the next scan gets a fresh attempt,
      // not a future that already failed. Unless something else replaced
      // this load meanwhile, in which case it is not ours to forget.
      if (identical(_loader, loader)) restart();
      // Too slow is the one failure with a meaning of its own.
      if (error is CardScannerException) rethrow;
      // The reason is kept for a log. It names a file or a browser
      // feature, never anything about a card.
      throw CardScannerException(
        'ocrUnavailable',
        'The recognizer could not be loaded: ${_reasonFor(error)}',
      );
    }
  }

  static String _reasonFor(Object error) => error is TimeoutException
      ? 'it took too long'
      : error is StateError
      ? error.message
      : '$error';

  @override
  void restart() {
    _loader?.cancel();
    _loader = null;
    _loading = null;
    _worker?.terminate();
    _worker = null;
  }

  @override
  Future<void> dispose() async => restart();
}

/// A `Worker` and the conversation with it.
///
/// The worker says four things: that its script ran, how fast WebAssembly
/// is, whether the engine loaded, and what a frame held. The first three
/// have one listener each; frames are matched by id.
class _BrowserWorker implements EngineWorker {
  _BrowserWorker(String url) : _worker = web.Worker(url.toJS) {
    _worker.onmessage = _onMessage.toJS;
    // A worker that cannot even be fetched reports an error event and
    // nothing else, so whatever is waiting has to fail on it rather than
    // wait. The same event reports an exception nothing in the worker
    // caught, which is as final.
    _worker.onerror = ((web.Event _) {
      _failSetup(
        StateError('the worker script could not be fetched, or threw'),
      );
    }).toJS;
  }

  final web.Worker _worker;
  final _started = Completer<void>();
  Completer<double?>? _benchmark;
  Completer<void>? _load;
  var _nextId = 0;
  final _frames = <int, Completer<RecognizedFrame>>{};

  @override
  Future<void> get started => _started.future;

  @override
  Future<double?> benchmark() {
    final answer = _benchmark = Completer<double?>();
    _worker.postMessage(JSObject()..['benchmark'] = true.toJS);
    return answer.future;
  }

  @override
  Future<void> load() {
    final answer = _load = Completer<void>();
    _worker.postMessage(JSObject()..['load'] = true.toJS);
    return answer.future;
  }

  /// Sends [bitmap] to be read.
  Future<RecognizedFrame> recognize(web.ImageBitmap bitmap) {
    final id = _nextId++;
    final answer = Completer<RecognizedFrame>();
    _frames[id] = answer;

    final message = JSObject()
      ..['id'] = id.toJS
      ..['bitmap'] = bitmap;
    // The bitmap is transferred rather than copied: a megabyte a frame is
    // not worth copying, and the worker closes it when it is done.
    _worker.postMessage(message, [bitmap].toJS);

    return answer.future;
  }

  void _onMessage(web.MessageEvent event) {
    final data = event.data;
    if (!data.isA<JSObject>()) return;
    final message = data as JSObject;

    if (message.has('ready')) {
      // A worker from before 0.4.0 says it is ready and names no backend.
      // It would never answer a benchmark or a load, only frames, so the
      // scanner would wait out the whole load timeout on it. That is an
      // app upgraded without its engine folder, and it is said at once.
      if (!message.has('backend')) {
        _failSetup(
          StateError(
            'The engine in the app\'s web folder is older than the package. '
            'Run `dart run flutter_card_scanner_plus:install_web` again',
          ),
        );
        return;
      }
      if (!_started.isCompleted) _started.complete();
      return;
    }
    if (message.has('benchmarkMs')) {
      final answer = _benchmark;
      _benchmark = null;
      if (answer == null || answer.isCompleted) return;
      final took = message['benchmarkMs'];
      answer.complete(
        took.isA<JSNumber>() ? (took as JSNumber).toDartDouble : null,
      );
      return;
    }
    if (message.has('loaded') || message.has('loadError')) {
      final answer = _load;
      _load = null;
      if (answer == null || answer.isCompleted) return;
      if (message.has('loadError')) {
        final reason = message['loadError'];
        answer.completeError(
          StateError(
            reason.isA<JSString>()
                ? (reason as JSString).toDart
                : 'The recognizer could not be loaded',
          ),
        );
      } else {
        answer.complete();
      }
      return;
    }
    if (!message.has('id')) return;

    final id = (message['id'] as JSNumber?)?.toDartInt;
    final answer = id == null ? null : _frames.remove(id);
    if (answer == null || answer.isCompleted) return;

    if (message.has('error')) {
      answer.completeError(StateError('The recognizer failed on a frame'));
      return;
    }
    final lines = message['lines'];
    answer.complete(
      lines == null
          ? RecognizedFrame.empty
          : RecognizedFrame.fromMap({'lines': lines.dartify()}),
    );
  }

  /// Fails everything that waits on the engine becoming usable.
  void _failSetup(Object error) {
    // Each is given a listener first. A load that was already abandoned,
    // by a timeout or by the scanner closing, has nobody left to hear the
    // error, and an error nobody hears is reported as uncaught.
    void fail<T>(Completer<T>? waiting) {
      if (waiting == null || waiting.isCompleted) return;
      waiting.future.ignore();
      waiting.completeError(error);
    }

    fail(_started);
    fail(_benchmark);
    fail(_load);
    _benchmark = null;
    _load = null;
  }

  @override
  void terminate() {
    _worker.terminate();
    final gone = StateError('The recognizer was replaced');
    _failSetup(gone);
    for (final pending in _frames.values) {
      if (!pending.isCompleted) {
        pending.future.ignore();
        pending.completeError(gone);
      }
    }
    _frames.clear();
  }
}
