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

const _strings = CardScannerStrings.defaults;

void main() {
  late FakeScannerPlatform fake;
  late CardScannerPlatform original;

  setUp(() {
    fake = FakeScannerPlatform(_handle);
    original = CardScannerPlatform.instance;
    CardScannerPlatform.instance = fake;
  });

  tearDown(() => CardScannerPlatform.instance = original);

  /// Opens the page the way an app does, through a route.
  ///
  /// [settle] is off while a spinner is on screen: an indeterminate
  /// progress indicator animates for ever and pumpAndSettle would time out.
  Future<void> openPage(
    WidgetTester tester, {
    VoidCallback? onOpenSettings,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                CardScannerPage.show(context, onOpenSettings: onOpenSettings),
            child: const Text('scan'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('scan'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  group('the camera could not be opened', () {
    testWidgets('a refusal explains itself and offers another try', (
      tester,
    ) async {
      fake.failStartWith = const CardScannerException(
        CardScannerException.permissionDenied,
      );
      await openPage(tester);

      expect(find.text(_strings.permissionDenied), findsOne);
      expect(find.text(_strings.retry), findsOne);
      expect(find.text(_strings.openSettings), findsNothing);
      // Leaving is always possible.
      expect(find.byType(CloseButton), findsOne);
    });

    testWidgets('settings are offered when the app can open them', (
      tester,
    ) async {
      var asked = 0;
      fake.failStartWith = const CardScannerException(
        CardScannerException.permissionDenied,
      );
      await openPage(tester, onOpenSettings: () => asked++);

      await tester.tap(find.text(_strings.openSettings));
      expect(asked, 1);
    });

    testWidgets('a busy camera says so', (tester) async {
      fake.failStartWith = const CardScannerException(
        CardScannerException.cameraInterrupted,
      );
      await openPage(tester);
      expect(find.text(_strings.cameraBusy), findsOne);
    });

    testWidgets('any other failure gets the generic message', (tester) async {
      fake.failStartWith = const CardScannerException(
        CardScannerException.noCamera,
      );
      await openPage(tester);
      expect(find.text(_strings.cameraFailed), findsOne);
    });

    testWidgets('trying again opens the camera', (tester) async {
      fake.failStartWith = const CardScannerException(
        CardScannerException.permissionDenied,
      );
      await openPage(tester);
      expect(fake.starts, 1);

      fake.failStartWith = null;
      await tester.tap(find.text(_strings.retry));
      await tester.pumpAndSettle();

      expect(fake.starts, 2);
      expect(find.text(_strings.permissionDenied), findsNothing);
      expect(find.text(_strings.alignCard), findsOne);
    });
  });

  testWidgets('opening the camera shows progress, not a blank screen', (
    tester,
  ) async {
    fake.holdStart = Completer<void>();
    await openPage(tester, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOne);

    fake.holdStart!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(_strings.alignCard), findsOne);
  });

  testWidgets('closing takes the preview down before the route leaves', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.byType(CardScannerView), findsOne);

    await tester.tap(find.byType(CloseButton));
    await tester.pump();
    expect(
      find.byType(CardScannerView),
      findsNothing,
      reason: 'the texture is gone before the exit animation',
    );

    await tester.pumpAndSettle();
    expect(find.byType(CardScannerPage), findsNothing);
  });
}
