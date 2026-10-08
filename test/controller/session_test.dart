import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

/// A session that completes on the first frame carrying any number, and
/// records what it was given. Nothing like the real rules, which is the
/// point: an app can replace them without touching the camera.
class FirstFrameSession implements ScanSession {
  int frames = 0;
  int resets = 0;
  CardScanResult _current = CardScanResult.empty;

  @override
  CardScanResult get current => _current;

  @override
  Set<CardField> get confirming =>
      _current.hasNumber ? const {} : const {CardField.number};

  @override
  CardScanResult add(FrameParseResult frame, {DateTime? at}) {
    frames++;
    final pan = frame.pan;
    if (pan == null) return _current;
    return _current = CardScanResult(
      number: pan.number,
      brand: pan.brand,
      isComplete: true,
    );
  }

  @override
  void reset() {
    resets++;
    _current = CardScanResult.empty;
  }
}

const _handle = CameraHandle(
  textureId: 1,
  previewWidth: 1080,
  previewHeight: 1920,
);

const _panLine = TextLine(
  text: '4111 1111 1111 1111',
  box: TextBox(left: 0.06, top: 0.46, width: 0.8, height: 0.09),
);

void main() {
  test('the controller runs the session it was given', () async {
    final fake = FakeScannerPlatform(_handle);
    final session = FirstFrameSession();
    final controller = CardScannerController(
      platform: fake,
      session: session,
      stopWhenComplete: false,
    );
    addTearDown(controller.dispose);

    await controller.start();
    fake.recognize(const [_panLine]);
    await Future<void>.delayed(Duration.zero);

    expect(session.frames, 1);
    expect(controller.value.result.number, '4111111111111111');
    expect(controller.value.isComplete, isTrue);
    expect(controller.value.confirming, isEmpty);
  });

  test('reset goes to the session', () async {
    final fake = FakeScannerPlatform(_handle);
    final session = FirstFrameSession();
    final controller = CardScannerController(platform: fake, session: session);
    addTearDown(controller.dispose);

    controller.reset();
    expect(session.resets, 1);
    expect(controller.value.result, CardScanResult.empty);
  });

  test('the default session reports what it is confirming', () async {
    final fake = FakeScannerPlatform(_handle);
    final controller = CardScannerController(
      platform: fake,
      requirements: const ScanRequirements(panVotes: 3),
      stopWhenComplete: false,
    );
    addTearDown(controller.dispose);

    await controller.start();
    fake.recognize(const [_panLine]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.result.hasNumber, isFalse);
    expect(controller.value.confirming, contains(CardField.number));
  });
}
