import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../channel/card_scanner_platform.dart';
import '../core/recognized_text.dart';
import 'js_await.dart';
import 'ocr_worker.dart';
import 'scan_crop.dart';
import 'scan_loop.dart';
import 'web_camera.dart';

/// The browser implementation of [CardScannerPlatform].
///
/// The shape of a scan is the same as on a phone: open a camera, read the
/// area under the guide, hand the lines to the same parser. What differs is
/// everything underneath. There is no texture, so the preview is a
/// `<video>` element shown through a platform view. There is no system OCR,
/// so recognition runs in a Web Worker the app serves itself. And opening a
/// camera can take arbitrarily long, because it waits on a permission
/// prompt, so every open carries a token and a scan that was closed in the
/// meantime closes the camera it was handed.
class CardScannerPlusWeb extends CardScannerPlatform {
  /// A scanner reading its engine from [engineDirectory] under the app's
  /// web root, which is where
  /// `dart run flutter_card_scanner_plus:install_web` puts it.
  CardScannerPlusWeb({this.engineDirectory = OcrAssets.defaultDirectory});

  /// Registers this implementation. Called by the generated plugin
  /// registrant, which passes a registrar this platform does not need.
  static void registerWith([Object? registrar]) {
    CardScannerPlatform.instance = CardScannerPlusWeb();
  }

  /// Folder the OCR engine was installed into.
  final String engineDirectory;

  final _frames = StreamController<RecognizedFrame>.broadcast();
  final _previews = StreamController<CameraHandle>.broadcast();
  final _errors = StreamController<CardScannerException>.broadcast();

  /// Bumped by every start and every stop, so an open that finishes late
  /// knows it is no longer wanted.
  int _attempt = 0;

  /// Counts sessions, which names the platform view and keeps successive
  /// handles unequal.
  int _session = 0;

  WebCamera? _camera;
  ScanLoop? _loop;
  OcrWorker? _worker;
  TextBox? _region;
  StreamSubscription<void>? _shape;
  StreamSubscription<void>? _lost;

  @override
  Stream<RecognizedFrame> get frames => _frames.stream;

  @override
  Stream<CameraHandle> get previewUpdates => _previews.stream;

  @override
  Stream<CardScannerException> get errors => _errors.stream;

  @override
  Future<CameraHandle> start({TextBox? regionOfInterest}) async {
    if (_camera != null) {
      throw const CardScannerException(CardScannerException.alreadyRunning);
    }
    final token = ++_attempt;
    _region = regionOfInterest ?? _region;

    final session = ++_session;
    final viewType = 'flutter_card_scanner_plus/preview/$session';

    final camera = await WebCamera.open(viewType: viewType);
    // The prompt may have been on screen for minutes. If the scanner was
    // closed, or restarted, while it was, this camera belongs to nobody.
    if (token != _attempt) {
      camera.close();
      throw const CardScannerException(CardScannerException.cancelled);
    }

    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) => camera.video,
    );

    _camera = camera;
    final worker = _worker = OcrWorker(directory: engineDirectory);
    final loop = _loop = ScanLoop(
      source: _CanvasFrames(camera),
      recognizer: worker,
      onFrame: _frames.add,
      onError: (error) {
        _errors.add(error);
        unawaited(stop());
      },
    )..region = _region;
    loop.start();

    _shape = camera.shapeChanges.listen((_) {
      final handle = _handleFor(camera, session);
      if (handle != null) _previews.add(handle);
    });
    _lost = camera.lost.listen((_) {
      _errors.add(
        const CardScannerException(
          CardScannerException.cameraInterrupted,
          'The camera was closed by the browser',
        ),
      );
      unawaited(stop());
    });

    return _handleFor(camera, session) ??
        (throw const CardScannerException(
          CardScannerException.cameraError,
          'The camera reported no frame size',
        ));
  }

  @override
  Future<void> stop() async {
    // Cancels an open that is still waiting on the permission prompt.
    _attempt++;
    await _shape?.cancel();
    _shape = null;
    await _lost?.cancel();
    _lost = null;

    final loop = _loop;
    _loop = null;
    await loop?.dispose();
    _worker = null;

    final camera = _camera;
    _camera = null;
    camera?.close();
  }

  @override
  Future<void> setTorch(bool enabled) async =>
      _camera?.setTorch(enabled) ?? Future<void>.value();

  @override
  Future<void> setRegionOfInterest(TextBox box) async {
    _region = box;
    _loop?.region = box;
  }

  @override
  Widget buildPreview(CameraHandle handle) {
    final camera = _camera;
    if (camera == null) return const SizedBox.shrink();
    return HtmlElementView(viewType: camera.viewType);
  }

  @override
  Future<RecognizedFrame> recognizeImage(
    Uint8List bytes, {
    TextBox? regionOfInterest,
  }) async {
    final blob = web.Blob([bytes.toJS].toJS);
    final decoded = await settle(web.window.createImageBitmap(blob));
    final bitmap = decoded.value;
    if (bitmap == null) {
      throw const CardScannerException(
        'invalidImage',
        'The browser could not decode the image',
      );
    }

    final crop = ScanCrop.from(
      region: regionOfInterest,
      videoWidth: bitmap.width,
      videoHeight: bitmap.height,
    );
    if (crop == null) {
      bitmap.close();
      return RecognizedFrame.empty;
    }

    // One-shot recognition borrows the running worker when there is one,
    // so a scan in progress does not pay to load a second engine.
    final worker = _worker ?? OcrWorker(directory: engineDirectory);
    try {
      final frame = await _CanvasFrames.cropBitmap(bitmap, crop);
      try {
        return await worker.recognize(frame, crop);
      } finally {
        frame.close();
      }
    } catch (error) {
      throw const CardScannerException(
        'ocrUnavailable',
        'The recognizer could not read the image',
      );
    } finally {
      bitmap.close();
      if (worker != _worker) await worker.dispose();
    }
  }

  CameraHandle? _handleFor(WebCamera camera, int session) {
    final width = camera.width;
    final height = camera.height;
    if (width <= 0 || height <= 0) return null;
    return CameraHandle(
      // There is no texture here. The session number keeps two handles of
      // the same shape from comparing equal across a restart.
      textureId: session,
      previewWidth: width,
      previewHeight: height,
      torchAvailable: camera.hasTorch,
    );
  }
}

/// Takes the guide's area out of the video through a canvas.
///
/// Drawing to a canvas and then lifting an `ImageBitmap` off it is the one
/// path every browser supports: `createImageBitmap` can crop and resize on
/// its own, but not everywhere.
class _CanvasFrames implements ScanFrameSource {
  _CanvasFrames(this._camera);

  final WebCamera _camera;
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();

  @override
  ({int width, int height})? get frameSize {
    if (_camera.isClosed) return null;
    final width = _camera.width;
    final height = _camera.height;
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }

  @override
  Future<Object?> grab(ScanCrop crop) async {
    if (_camera.isClosed) return null;
    return _draw(_camera.video, crop);
  }

  @override
  void release(Object frame) => (frame as web.ImageBitmap).close();

  /// Crops [bitmap] the same way a camera frame is cropped.
  static Future<web.ImageBitmap> cropBitmap(
    web.ImageBitmap bitmap,
    ScanCrop crop,
  ) async {
    final frame = await _CanvasFrames._on(
      web.HTMLCanvasElement(),
      bitmap,
      crop,
    );
    if (frame == null) {
      throw StateError('The browser gave no 2d canvas');
    }
    return frame;
  }

  Future<web.ImageBitmap?> _draw(web.CanvasImageSource source, ScanCrop crop) =>
      _on(_canvas, source, crop);

  static Future<web.ImageBitmap?> _on(
    web.HTMLCanvasElement canvas,
    web.CanvasImageSource source,
    ScanCrop crop,
  ) async {
    canvas
      ..width = crop.outWidth
      ..height = crop.outHeight;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) return null;
    context.drawImage(
      source,
      crop.left.toDouble(),
      crop.top.toDouble(),
      crop.width.toDouble(),
      crop.height.toDouble(),
      0,
      0,
      crop.outWidth.toDouble(),
      crop.outHeight.toDouble(),
    );
    final lifted = await settle(web.window.createImageBitmap(canvas));
    return lifted.value;
  }
}
