import 'package:flutter/material.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

const _portrait = CameraHandle(
  textureId: 1,
  previewWidth: 1080,
  previewHeight: 1920,
);

/// Pumps the view at [size] and returns the region it asked OCR to read.
Future<TextBox> regionFor(
  WidgetTester tester,
  Size size, {
  double padding = 0,
  CameraHandle camera = _portrait,
}) async {
  tester.view
    ..physicalSize = size * tester.view.devicePixelRatio
    ..devicePixelRatio = tester.view.devicePixelRatio;
  addTearDown(tester.view.reset);

  final fake = FakeScannerPlatform(camera);
  final controller = CardScannerController(platform: fake);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: CardScannerView(
        controller: controller,
        frameRegionPadding: padding,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(fake.regions, isNotEmpty);
  return fake.regions.last;
}

void main() {
  const phone = Size(393, 852);
  const cardAspect = CardScannerView.iso7810AspectRatio;

  testWidgets('the region read is the frame the user sees', (tester) async {
    final roi = await regionFor(tester, phone);

    // Inside the preview, and shaped like a card once the preview's own
    // aspect ratio is taken into account.
    expect(roi.left, greaterThanOrEqualTo(0));
    expect(roi.top, greaterThanOrEqualTo(0));
    expect(roi.right, lessThanOrEqualTo(1));
    expect(roi.bottom, lessThanOrEqualTo(1));
    expect(
      (roi.width * _portrait.previewWidth) /
          (roi.height * _portrait.previewHeight),
      closeTo(cardAspect, 0.01),
    );
    expect(roi.centerX, closeTo(0.5, 0.01));
  });

  testWidgets('nothing outside the frame is read by default', (tester) async {
    final tight = await regionFor(tester, phone);
    final padded = await regionFor(tester, phone, padding: 0.15);

    expect(padded.width, greaterThan(tight.width));
    expect(padded.height, greaterThan(tight.height));
    expect(tight.left, greaterThan(padded.left));
    expect(tight.top, greaterThan(padded.top));
  });

  testWidgets('the region still fits the frame in landscape', (tester) async {
    const landscapeCamera = CameraHandle(
      textureId: 1,
      previewWidth: 1920,
      previewHeight: 1080,
    );
    final roi = await regionFor(
      tester,
      const Size(852, 393),
      camera: landscapeCamera,
    );

    expect(roi.right, lessThanOrEqualTo(1));
    expect(roi.bottom, lessThanOrEqualTo(1));
    expect(
      (roi.width * landscapeCamera.previewWidth) /
          (roi.height * landscapeCamera.previewHeight),
      closeTo(cardAspect, 0.01),
    );
  });
}
