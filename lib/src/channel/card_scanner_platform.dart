import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../core/recognized_text.dart';

/// Error raised by the native camera/OCR layer.
@immutable
class CardScannerException implements Exception {
  const CardScannerException(this.code, [this.message]);

  /// One of [permissionDenied], [noCamera], [cameraError], [alreadyRunning]
  /// or a platform-specific code.
  final String code;
  final String? message;

  static const permissionDenied = 'permissionDenied';
  static const noCamera = 'noCamera';
  static const cameraError = 'cameraError';
  static const alreadyRunning = 'alreadyRunning';

  bool get isPermissionDenied => code == permissionDenied;

  @override
  String toString() =>
      'CardScannerException($code${message == null ? '' : ': $message'})';
}

/// Returned by [CardScannerPlatform.start].
@immutable
class CameraHandle {
  const CameraHandle({
    required this.textureId,
    required this.previewWidth,
    required this.previewHeight,
    this.rotation = 0,
  });

  /// Texture to render with `Texture(textureId: ...)`.
  final int textureId;

  /// Preview dimensions in pixels, upright (portrait) orientation — i.e.
  /// after [rotation] has been applied.
  final int previewWidth;
  final int previewHeight;

  /// Clockwise rotation in degrees (0/90/180/270) to apply to the raw
  /// texture so it displays upright. Android delivers sensor-oriented
  /// buffers; iOS rotates them natively and reports 0.
  final int rotation;

  int get quarterTurns => (rotation ~/ 90) % 4;

  double get aspectRatio => previewWidth / previewHeight;
}

/// Contract implemented by the native side. Replace [instance] in tests.
abstract class CardScannerPlatform {
  static CardScannerPlatform instance = MethodChannelCardScannerPlatform();

  /// Opens the camera and starts OCR. Throws [CardScannerException].
  Future<CameraHandle> start({TextBox? regionOfInterest});

  Future<void> stop();

  Future<void> setTorch(bool enabled);

  /// Restricts OCR to [box] (normalized preview coordinates, top-left origin).
  Future<void> setRegionOfInterest(TextBox box);

  /// OCR output, one event per analyzed frame while running.
  Stream<RecognizedFrame> get frames;

  /// Runs OCR once on an encoded image (JPEG, PNG, HEIC…).
  ///
  /// Independent of the camera; may be called while it is running or not.
  /// Throws [CardScannerException] with code `invalidImage` if the bytes
  /// cannot be decoded.
  Future<RecognizedFrame> recognizeImage(
    Uint8List bytes, {
    TextBox? regionOfInterest,
  });
}

/// Default implementation talking to the plugin over platform channels.
class MethodChannelCardScannerPlatform implements CardScannerPlatform {
  MethodChannelCardScannerPlatform({
    @visibleForTesting MethodChannel? methodChannel,
    @visibleForTesting EventChannel? eventChannel,
  }) : _methods =
           methodChannel ??
           const MethodChannel('flutter_card_scanner_plus/methods'),
       _events =
           eventChannel ??
           const EventChannel('flutter_card_scanner_plus/frames');

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<RecognizedFrame>? _frames;

  @override
  Future<CameraHandle> start({TextBox? regionOfInterest}) async {
    try {
      final reply = await _methods.invokeMapMethod<String, Object?>('start', {
        if (regionOfInterest != null)
          'regionOfInterest': regionOfInterest.toMap(),
      });
      return CameraHandle(
        textureId: reply!['textureId'] as int,
        previewWidth: (reply['previewWidth'] as num).toInt(),
        previewHeight: (reply['previewHeight'] as num).toInt(),
        rotation: (reply['rotation'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw CardScannerException(e.code, e.message);
    }
  }

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<void> setTorch(bool enabled) =>
      _methods.invokeMethod<void>('setTorch', {'enabled': enabled});

  @override
  Future<void> setRegionOfInterest(TextBox box) =>
      _methods.invokeMethod<void>('setRegionOfInterest', box.toMap());

  @override
  Future<RecognizedFrame> recognizeImage(
    Uint8List bytes, {
    TextBox? regionOfInterest,
  }) async {
    try {
      final reply = await _methods.invokeMapMethod<Object?, Object?>(
        'recognizeImage',
        {
          'bytes': bytes,
          if (regionOfInterest != null)
            'regionOfInterest': regionOfInterest.toMap(),
        },
      );
      return RecognizedFrame.fromMap(reply ?? const {});
    } on PlatformException catch (e) {
      throw CardScannerException(e.code, e.message);
    }
  }

  @override
  Stream<RecognizedFrame> get frames => _frames ??= _events
      .receiveBroadcastStream()
      .map((event) => RecognizedFrame.fromMap(event as Map<Object?, Object?>));
}
