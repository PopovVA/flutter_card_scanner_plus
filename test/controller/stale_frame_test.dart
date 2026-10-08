import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

const _portrait = CameraHandle(
  textureId: 1,
  previewWidth: 1080,
  previewHeight: 1920,
);
const _landscape = CameraHandle(
  textureId: 1,
  previewWidth: 1920,
  previewHeight: 1080,
);

const _card = [
  TextLine(
    text: '4111 1111 1111 1111',
    box: TextBox(left: 0.06, top: 0.46, width: 0.8, height: 0.09),
  ),
  TextLine(
    text: 'VALID THRU 12/28',
    box: TextBox(left: 0.06, top: 0.64, width: 0.26, height: 0.07),
  ),
];

const _roi = TextBox(left: 0.1, top: 0.3, width: 0.7, height: 0.3);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a frame from before a rotation is not scored', () async {
    final fake = FakeScannerPlatform(_portrait);
    final controller = CardScannerController(
      platform: fake,
      requirements: ScanRequirements.fast,
      stopWhenComplete: false,
    );
    addTearDown(controller.dispose);

    await controller.start();
    fake.rotate(_landscape);
    await settle();

    fake.recognize(_card);
    await settle();
    expect(
      controller.value.result.hasNumber,
      isFalse,
      reason: 'recognized against the portrait region',
    );

    // The view reacts to the new preview shape by moving the region.
    await controller.setRegionOfInterest(_roi);
    fake.recognize(_card);
    await settle();
    expect(controller.value.result.number, '4111111111111111');
  });

  test('frames resume even if the region is never moved', () async {
    final fake = FakeScannerPlatform(_portrait);
    final controller = CardScannerController(
      platform: fake,
      requirements: ScanRequirements.fast,
      stopWhenComplete: false,
    );
    addTearDown(controller.dispose);

    await controller.start();
    fake.rotate(_landscape);
    await settle();

    // Nothing calls setRegionOfInterest here, which is what happens to a
    // controller driven without CardScannerView.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    fake.recognize(_card);
    await settle();
    expect(controller.value.result.number, '4111111111111111');
  });

  test('frames are scored normally when nothing rotates', () async {
    final fake = FakeScannerPlatform(_portrait);
    final controller = CardScannerController(
      platform: fake,
      requirements: ScanRequirements.fast,
      stopWhenComplete: false,
    );
    addTearDown(controller.dispose);

    await controller.start();
    fake.recognize(_card);
    await settle();
    expect(controller.value.result.number, '4111111111111111');
    expect(controller.value.result.formattedExpiry, '12/28');
  });
}
