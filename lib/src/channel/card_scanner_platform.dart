import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../core/recognized_text.dart';

/// Error raised by the native camera/OCR layer.
@immutable
class CardScannerException implements Exception {
  const CardScannerException(this.code, [this.message]);

  /// One of [permissionDenied], [noCamera], [cameraError],
  /// [alreadyRunning], [cameraInterrupted], [cameraDetached], [cancelled]
  /// or a platform-specific code.
  final String code;
  final String? message;

  static const permissionDenied = 'permissionDenied';
  static const noCamera = 'noCamera';
  static const cameraError = 'cameraError';
  static const alreadyRunning = 'alreadyRunning';

  /// Another app holds the camera.
  static const cameraInterrupted = 'cameraInterrupted';

  /// The host Activity went away, taking the camera with it (Android).
  static const cameraDetached = 'cameraDetached';

  /// A start that was stopped before it finished opening. Not a failure:
  /// the controller swallows it.
  static const cancelled = 'cancelled';

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

  factory CameraHandle.fromMap(Map<Object?, Object?> map) => CameraHandle(
    textureId: (map['textureId'] as num).toInt(),
    previewWidth: (map['previewWidth'] as num).toInt(),
    previewHeight: (map['previewHeight'] as num).toInt(),
    rotation: (map['rotation'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      other is CameraHandle &&
      other.textureId == textureId &&
      other.previewWidth == previewWidth &&
      other.previewHeight == previewHeight &&
      other.rotation == rotation;

  @override
  int get hashCode =>
      Object.hash(textureId, previewWidth, previewHeight, rotation);

  @override
  String toString() =>
      'CameraHandle($textureId, ${previewWidth}x$previewHeight, rot $rotation)';
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

  /// Emits a new handle whenever a device rotation changes the shape of the
  /// preview, so the texture and the region of interest can follow.
  Stream<CameraHandle> get previewUpdates;

  /// Emits when the camera fails after it started: another app took it, the
  /// device ran out of resources, or the host Activity went away. The camera
  /// is no longer running once one of these arrives.
  Stream<CardScannerException> get errors;

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
  Stream<Map<Object?, Object?>>? _raw;

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

  /// One broadcast of the native channel, split by the key each event
  /// carries: `lines` for OCR output, `preview` for a rotation, `error` for
  /// a camera that stopped working.
  Stream<Map<Object?, Object?>> get _stream =>
      _raw ??= _events.receiveBroadcastStream().cast<Map<Object?, Object?>>();

  @override
  Stream<RecognizedFrame> get frames => _stream
      .where((event) => event.containsKey('lines'))
      .map(RecognizedFrame.fromMap);

  @override
  Stream<CameraHandle> get previewUpdates => _stream
      .where((event) => event['preview'] is Map)
      .map(
        (event) =>
            CameraHandle.fromMap(event['preview']! as Map<Object?, Object?>),
      );

  @override
  Stream<CardScannerException> get errors =>
      _stream.where((event) => event['error'] is Map).map((event) {
        final error = event['error']! as Map<Object?, Object?>;
        return CardScannerException(
          error['code'] as String? ?? CardScannerException.cameraError,
          error['message'] as String?,
        );
      });
}
