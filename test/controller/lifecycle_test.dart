import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_scanner_platform.dart';

const _handle = CameraHandle(
  textureId: 1,
  previewWidth: 1080,
  previewHeight: 1920,
);

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Flutter only accepts legal lifecycle transitions, so a test has to walk
/// the same path the platform does.
Future<void> background(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  // Cancelling the frame subscriptions takes an event loop turn, which
  // pumpAndSettle alone does not give.
  await tester.idle();
  await tester.pumpAndSettle();
}

Future<void> foreground(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  // Cancelling the frame subscriptions takes an event loop turn, which
  // pumpAndSettle alone does not give.
  await tester.idle();
  await tester.pumpAndSettle();
}

void main() {
  group('a camera that fails after it started', () {
    test('reaches the state and leaves the camera stopped', () async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.value.isRunning, isTrue);

      fake.fail(
        const CardScannerException(
          CardScannerException.cameraInterrupted,
          'Another app is using the camera',
        ),
      );
      await settle();

      expect(
        controller.value.error?.code,
        CardScannerException.cameraInterrupted,
      );
      expect(controller.value.isRunning, isFalse);
      expect(controller.value.camera, isNull);
      expect(fake.started, isFalse);
    });

    test('a cancelled start is not an error', () async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await controller.start();
      fake.fail(const CardScannerException(CardScannerException.cancelled));
      await settle();

      expect(controller.value.error, isNull);
      expect(controller.value.isRunning, isTrue);
    });

    test('scanOnce fails with the camera error', () async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await controller.start();
      final pending = controller.scanOnce();
      fake.fail(const CardScannerException(CardScannerException.cameraError));

      await expectLater(pending, throwsA(isA<CardScannerException>()));
    });
  });

  group('start and stop do not overlap', () {
    test('a reopen waits for the teardown before it', () async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await controller.start();
      expect(fake.starts, 1);

      // The platform has not finished tearing down yet.
      fake.holdStop = Completer<void>();
      final stopping = controller.stop();
      final starting = controller.start();
      await settle();
      expect(fake.starts, 1, reason: 'the reopen is still queued');

      fake.holdStop!.complete();
      await stopping;
      await starting;

      expect(fake.stops, 1);
      expect(fake.starts, 2);
      expect(fake.started, isTrue);
      expect(controller.value.isRunning, isTrue);
    });
  });

  group('app lifecycle', () {
    testWidgets('the camera is released in the background and taken back', (
      tester,
    ) async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: CardScannerView(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(fake.started, isTrue);

      await background(tester);
      expect(fake.started, isFalse);
      expect(controller.value.isRunning, isFalse);

      await foreground(tester);
      expect(fake.started, isTrue);
      expect(controller.value.isRunning, isTrue);
    });

    testWidgets('a transient inactive state is left alone', (tester) async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: CardScannerView(controller: controller)),
      );
      await tester.pumpAndSettle();

      // A permission dialog or a notification banner. Stopping here would
      // fight the start that asked for permission.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(fake.started, isTrue);
      expect(fake.stops, 0);
    });

    testWidgets('a camera that was not running is not started on return', (
      tester,
    ) async {
      final fake = FakeScannerPlatform(_handle);
      final controller = CardScannerController(platform: fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CardScannerView(controller: controller, autoStart: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.started, isFalse);

      await background(tester);
      await foreground(tester);
      expect(fake.starts, 0);
    });
  });
}
