import 'package:flutter/material.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sizes the real devices report, in logical pixels.
const portraitPhone = Size(393, 852);
const landscapePhone = Size(852, 393);
const landscapeTablet = Size(1194, 834);

/// Drives the view's layout without a camera by reading the rect the
/// overlay builder receives.
Future<Rect> cardRectFor(WidgetTester tester, Size size) async {
  late Rect captured;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: CardScannerView(
        controller: CardScannerController(),
        autoStart: false,
        overlayBuilder: (context, state, cardRect) {
          captured = cardRect;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('card frame fits the screen', () {
    testWidgets('portrait', (tester) async {
      final rect = await cardRectFor(tester, portraitPhone);
      expect(rect.width, closeTo(393 * 0.88, 0.5));
      expect(rect.right, lessThanOrEqualTo(portraitPhone.width + 0.5));
      expect(rect.bottom, lessThanOrEqualTo(portraitPhone.height + 0.5));
    });

    testWidgets('landscape phone keeps the frame on screen', (tester) async {
      final rect = await cardRectFor(tester, landscapePhone);
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.top, greaterThanOrEqualTo(-0.5));
      expect(rect.right, lessThanOrEqualTo(landscapePhone.width + 0.5));
      expect(rect.bottom, lessThanOrEqualTo(landscapePhone.height + 0.5));
    });

    testWidgets('landscape tablet keeps the frame on screen', (tester) async {
      final rect = await cardRectFor(tester, landscapeTablet);
      expect(rect.right, lessThanOrEqualTo(landscapeTablet.width + 0.5));
      expect(rect.bottom, lessThanOrEqualTo(landscapeTablet.height + 0.5));
    });

    testWidgets('the card keeps its aspect ratio in every orientation', (
      tester,
    ) async {
      for (final size in [portraitPhone, landscapePhone, landscapeTablet]) {
        final rect = await cardRectFor(tester, size);
        expect(
          rect.width / rect.height,
          closeTo(CardScannerView.iso7810AspectRatio, 0.01),
          reason: '$size',
        );
      }
    });
  });

  group('default overlay stays on screen', () {
    Future<void> pumpOverlay(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final rect = await cardRectFor(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              CardFrameOverlay(
                state: const CardScannerState(
                  result: CardScanResult(
                    number: '4111111111111111',
                    brand: CardBrand.visa,
                    expiryMonth: 12,
                    expiryYear: 2028,
                  ),
                ),
                cardRect: rect,
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('portrait renders without overflow', (tester) async {
      await pumpOverlay(tester, portraitPhone);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('4111'), findsOneWidget);
    });

    testWidgets('landscape renders without overflow', (tester) async {
      await pumpOverlay(tester, landscapePhone);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('4111'), findsOneWidget);
    });

    testWidgets('the recognized number is visible on a landscape phone', (
      tester,
    ) async {
      await pumpOverlay(tester, landscapePhone);
      final box = tester.getRect(find.textContaining('4111'));
      expect(box.bottom, lessThanOrEqualTo(landscapePhone.height));
      expect(box.top, greaterThanOrEqualTo(0));
    });
  });
}
