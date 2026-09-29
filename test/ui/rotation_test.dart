import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera that never opens, but lets a test push rotations.
class FakeScannerPlatform implements CardScannerPlatform {
  FakeScannerPlatform(this.handle);

  final CameraHandle handle;
  final _frames = StreamController<RecognizedFrame>.broadcast();
  final _previews = StreamController<CameraHandle>.broadcast();
  final regions = <TextBox>[];
  bool started = false;

  void rotate(CameraHandle next) => _previews.add(next);

  @override
  Future<CameraHandle> start({TextBox? regionOfInterest}) async {
    started = true;
    return handle;
  }

  @override
  Future<void> stop() async => started = false;

  @override
  Future<void> setTorch(bool enabled) async {}

  @override
  Future<void> setRegionOfInterest(TextBox box) async => regions.add(box);

  @override
  Stream<RecognizedFrame> get frames => _frames.stream;

  @override
  Stream<CameraHandle> get previewUpdates => _previews.stream;

  @override
  Future<RecognizedFrame> recognizeImage(
    Uint8List bytes, {
    TextBox? regionOfInterest,
  }) async => RecognizedFrame.empty;
}

const portrait = CameraHandle(
  textureId: 1,
  previewWidth: 1080,
  previewHeight: 1920,
);
const landscape = CameraHandle(
  textureId: 1,
  previewWidth: 1920,
  previewHeight: 1080,
);

void main() {
  test('a rotation reaches the controller state', () async {
    final fake = FakeScannerPlatform(portrait);
    final controller = CardScannerController(platform: fake);
    addTearDown(controller.dispose);

    await controller.start();
    expect(controller.value.camera, portrait);

    fake.rotate(landscape);
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.camera, landscape);
    expect(controller.value.camera!.aspectRatio, greaterThan(1));
  });

  test('rotations are ignored once the camera is stopped', () async {
    final fake = FakeScannerPlatform(portrait);
    final controller = CardScannerController(platform: fake);
    addTearDown(controller.dispose);

    await controller.start();
    await controller.stop();
    fake.rotate(landscape);
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.camera, isNull);
  });

  test('CameraHandle carries the rotation the texture needs', () {
    const handle = CameraHandle(
      textureId: 1,
      previewWidth: 1080,
      previewHeight: 1920,
      rotation: 270,
    );
    expect(handle.quarterTurns, 3);
    expect(
      const CameraHandle(
        textureId: 1,
        previewWidth: 1,
        previewHeight: 1,
      ).quarterTurns,
      0,
    );
  });

  test(
    'handles compare by shape, so an unchanged rotation is not a change',
    () {
      expect(
        portrait,
        const CameraHandle(
          textureId: 1,
          previewWidth: 1080,
          previewHeight: 1920,
        ),
      );
      expect(portrait, isNot(landscape));
    },
  );

  test('a handle parses the map the native side sends', () {
    final handle = CameraHandle.fromMap(const {
      'textureId': 7,
      'previewWidth': 1920,
      'previewHeight': 1080,
      'rotation': 90,
    });
    expect(handle.textureId, 7);
    expect(handle.previewWidth, 1920);
    expect(handle.rotation, 90);
  });
}
