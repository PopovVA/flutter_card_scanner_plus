import 'package:flutter/services.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_card_scanner_plus/src/channel/card_scanner_platform.dart'
    show MethodChannelCardScannerPlatform;
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_card_scanner_plus/methods');
  final calls = <MethodCall>[];

  /// Answers [channel] with [reply]. A test that never calls this leaves
  /// the channel unhandled, which is how a platform that does not
  /// implement a method behaves.
  void mock(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('listCameras', () {
    test('parses the ranked list the platform sends', () async {
      mock(
        (_) => [
          {'id': 'phone', 'name': "Vadim's iPhone", 'kind': 'continuity'},
          {'id': 'usb', 'name': 'Logi Webcam', 'kind': 'external'},
          {'id': 'lid', 'name': 'FaceTime HD Camera', 'kind': 'builtIn'},
        ],
      );

      final cameras = await MethodChannelCardScannerPlatform().listCameras();

      expect(cameras, hasLength(3));
      expect(cameras.first.id, 'phone');
      expect(cameras.first.name, "Vadim's iPhone");
      expect(cameras.map((c) => c.kind), [
        CameraKind.continuityCamera,
        CameraKind.external,
        CameraKind.builtIn,
      ]);
    });

    test('an unknown kind is read as external rather than dropped', () {
      expect(CameraKind.fromName('somethingNew'), CameraKind.external);
      expect(CameraKind.fromName(null), CameraKind.external);
    });

    // iOS and Android do not implement the method, and should not have to.
    test('a platform without the method answers with no cameras', () async {
      final cameras = await MethodChannelCardScannerPlatform().listCameras();
      expect(cameras, isEmpty);
    });
  });

  group('start', () {
    test(
      'passes the chosen camera and reads back the one that opened',
      () async {
        mock(
          (_) => {
            'textureId': 7,
            'previewWidth': 1920,
            'previewHeight': 1080,
            'torchAvailable': false,
            'cameraId': 'lid',
          },
        );

        final handle = await MethodChannelCardScannerPlatform().start(
          cameraId: 'usb',
        );

        expect(calls.single.arguments, containsPair('cameraId', 'usb'));
        // The webcam was unplugged in between: the platform opened another
        // one rather than failing, and says which.
        expect(handle.cameraId, 'lid');
        expect(handle.torchAvailable, isFalse);
        expect(handle.previewWidth, 1920);
      },
    );

    test(
      'a platform that says nothing about a torch is taken to have one',
      () async {
        mock(
          (_) => {'textureId': 1, 'previewWidth': 1080, 'previewHeight': 1920},
        );

        final handle = await MethodChannelCardScannerPlatform().start();

        expect(calls.single.arguments, isNot(contains('cameraId')));
        expect(handle.torchAvailable, isTrue);
        expect(handle.cameraId, isNull);
      },
    );
  });

  group('CardScannerController.useCamera', () {
    test('a stopped controller just remembers the choice', () async {
      final platform = FakeScannerPlatform(
        const CameraHandle(
          textureId: 1,
          previewWidth: 1920,
          previewHeight: 1080,
        ),
      );
      final controller = CardScannerController(platform: platform);
      addTearDown(controller.dispose);

      await controller.useCamera('usb');

      expect(controller.cameraId, 'usb');
      expect(platform.starts, 0);
    });

    test('a running controller reopens on the new camera', () async {
      final platform = FakeScannerPlatform(
        const CameraHandle(
          textureId: 1,
          previewWidth: 1920,
          previewHeight: 1080,
        ),
      );
      final controller = CardScannerController(
        cameraId: 'lid',
        platform: platform,
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.useCamera('usb');

      expect(platform.cameraIds, ['lid', 'usb']);
      expect(platform.stops, 1);
      expect(controller.value.isRunning, isTrue);
    });

    test('choosing the camera already in use changes nothing', () async {
      final platform = FakeScannerPlatform(
        const CameraHandle(
          textureId: 1,
          previewWidth: 1920,
          previewHeight: 1080,
        ),
      );
      final controller = CardScannerController(
        cameraId: 'usb',
        platform: platform,
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.useCamera('usb');

      expect(platform.starts, 1);
      expect(platform.stops, 0);
    });
  });
}
