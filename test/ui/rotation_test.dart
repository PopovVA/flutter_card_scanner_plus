import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

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
