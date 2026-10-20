import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../core/recognized_text.dart';
import 'scan_crop.dart';
import 'scan_loop.dart';

/// Where the browser scanner loads its recognizer from.
///
/// The files are served by the app, not bundled into the package: the
/// models and the runtime come to about 40 MB, which has no business inside
/// an iOS or Android build. `dart run flutter_card_scanner_plus:install_web`
/// puts them in place.
abstract final class OcrAssets {
  /// Folder the installer writes to, under the app's `web/`.
  static const defaultDirectory = 'flutter_card_scanner_plus';

  /// The worker script inside that folder.
  static const workerFile = 'card_ocr_worker.js';
}

/// Runs the OCR engine in a Web Worker and speaks to it one frame at a
/// time.
///
/// A worker rather than the page: recognition takes about a second, and a
/// second of a blocked main thread is a frozen app. The worker is classic
/// rather than a module, because the engine loads OpenCV with
/// `importScripts`.
class OcrWorker implements ScanRecognizer {
  /// A recognizer loading its worker from [directory], which is a path
  /// under the app's web root.
  ///
  /// [loadTimeout] bounds the first frame, which waits for about 40 MB of
  /// models to arrive. Without it a missing file leaves the scanner saying
  /// it is getting ready for ever.
  OcrWorker({
    this.directory = OcrAssets.defaultDirectory,
    this.loadTimeout = const Duration(minutes: 2),
  });

  /// Folder the engine was installed into, under the app's web root.
  final String directory;

  /// How long the engine has to become usable.
  final Duration loadTimeout;

  web.Worker? _worker;
  Completer<void>? _loading;
  var _nextId = 0;
  final _pending = <int, Completer<RecognizedFrame>>{};

  /// Whether a worker is loaded and answering.
  bool get isLoaded => _worker != null && (_loading?.isCompleted ?? false);

  @override
  Future<RecognizedFrame> recognize(Object frame, ScanCrop crop) async {
    final worker = await _ready();
    final id = _nextId++;
    final answer = Completer<RecognizedFrame>();
    _pending[id] = answer;

    final bitmap = frame as web.ImageBitmap;
    final message = JSObject()
      ..['id'] = id.toJS
      ..['bitmap'] = bitmap;
    // The bitmap is transferred rather than copied: a megabyte a frame is
    // not worth copying, and the worker closes it when it is done.
    worker.postMessage(message, [bitmap].toJS);

    return answer.future;
  }

  /// Loads the worker if needed and returns it once it reports ready.
  Future<web.Worker> _ready() async {
    final existing = _worker;
    if (existing != null) {
      await _loading!.future;
      return existing;
    }

    final loading = _loading = Completer<void>();
    final worker = _worker = web.Worker(
      '$directory/${OcrAssets.workerFile}'.toJS,
    );
    worker.onmessage = ((web.MessageEvent event) {
      _onMessage(event, loading);
    }).toJS;
    // A worker that cannot even be fetched reports an error event and
    // nothing else, so the load has to fail on it rather than wait.
    worker.onerror = ((web.Event _) {
      if (!loading.isCompleted) {
        loading.completeError(StateError('The recognizer could not be loaded'));
      }
    }).toJS;

    try {
      await loading.future.timeout(loadTimeout);
    } catch (_) {
      restart();
      throw StateError('The recognizer could not be loaded');
    }
    return worker;
  }

  void _onMessage(web.MessageEvent event, Completer<void> loading) {
    final data = event.data;
    if (!data.isA<JSObject>()) return;
    final message = data as JSObject;

    if (message.has('ready')) {
      if (!loading.isCompleted) loading.complete();
      return;
    }
    if (!message.has('id')) return;

    final id = (message['id'] as JSNumber?)?.toDartInt;
    final answer = id == null ? null : _pending.remove(id);
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

  @override
  void restart() {
    _worker?.terminate();
    _worker = null;
    _loading = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(StateError('The recognizer was replaced'));
      }
    }
    _pending.clear();
  }

  @override
  Future<void> dispose() async => restart();
}
