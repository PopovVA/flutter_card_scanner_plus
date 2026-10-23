import 'package:flutter/material.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
// The channel implementation is not exported: an app gets it through
// CardScannerPlatform.instance.
import 'package:flutter_card_scanner_plus/src/channel/card_scanner_platform.dart'
    show MethodChannelCardScannerPlatform;
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

const _portrait = CameraHandle(
  textureId: 7,
  previewWidth: 1080,
  previewHeight: 1920,
);
const _landscape = CameraHandle(
  textureId: 7,
  previewWidth: 1920,
  previewHeight: 1080,
);

/// A platform whose preview records the handle it was built from.
class RecordingPlatform extends FakeScannerPlatform {
  RecordingPlatform(super.handle);

  final previews = <CameraHandle>[];

  @override
  Widget buildPreview(CameraHandle handle) {
    previews.add(handle);
    return const Placeholder();
  }
}

void main() {
  testWidgets('the view shows the preview the platform builds', (tester) async {
    final fake = RecordingPlatform(_portrait);
    final controller = CardScannerController(platform: fake);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CardScannerView(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsOne);
    expect(fake.previews, isNotEmpty);
    expect(fake.previews.last, _portrait);
  });

  testWidgets('the preview is handed the whole view to fill', (tester) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = RecordingPlatform(_portrait);
    final controller = CardScannerController(platform: fake);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CardScannerView(controller: controller)),
    );
    await tester.pumpAndSettle();

    // Not the camera's pixel size: a platform view cannot be scaled by a
    // widget on the web, so each platform covers its own box instead.
    expect(tester.getSize(find.byType(Placeholder)), const Size(393, 852));
  });

  test('the method channel platform covers the box it is given', () {
    final preview = MethodChannelCardScannerPlatform().buildPreview(_portrait);

    final fitted = preview as FittedBox;
    expect(fitted.fit, BoxFit.cover);
    final box = fitted.child! as SizedBox;
    expect(box.width, 1080);
    expect(box.height, 1920);
  });

  testWidgets('a rotation rebuilds the preview from the new handle', (
    tester,
  ) async {
    final fake = RecordingPlatform(_portrait);
    final controller = CardScannerController(platform: fake);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CardScannerView(controller: controller)),
    );
    await tester.pumpAndSettle();

    fake.rotate(_landscape);
    await tester.pumpAndSettle();

    expect(fake.previews.last, _landscape);
  });

  test('the method channel platform draws a rotated texture', () {
    final platform = MethodChannelCardScannerPlatform();
    final preview = platform.buildPreview(
      const CameraHandle(
        textureId: 3,
        previewWidth: 1080,
        previewHeight: 1920,
        rotation: 90,
      ),
    );

    final box = (preview as FittedBox).child! as SizedBox;
    final rotated = box.child! as RotatedBox;
    expect(rotated.quarterTurns, 1);
    expect((rotated.child! as Texture).textureId, 3);
  });
}
