import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

CardScannerState stateWith({
  String? number,
  String? expiry,
  String? name,
  bool isComplete = false,
}) => CardScannerState(
  result: CardScanResult(
    number: number,
    brand: number == null ? null : CardBrand.detect(number),
    expiryMonth: expiry == null ? null : int.parse(expiry.split('/')[0]),
    expiryYear: expiry == null ? null : 2000 + int.parse(expiry.split('/')[1]),
    cardholderName: name,
    isComplete: isComplete,
  ),
);

Future<void> pumpOverlay(
  WidgetTester tester,
  CardScannerState state, {
  ScanRequirements requirements = ScanRequirements.standard,
  bool enableHaptics = false,
  Duration numberOverdueAfter = const Duration(seconds: 4),
}) => tester.pumpWidget(
  MaterialApp(
    home: Stack(
      children: [
        CardFrameOverlay(
          state: state,
          cardRect: const Rect.fromLTWH(20, 100, 350, 220),
          requirements: requirements,
          enableHaptics: enableHaptics,
          numberOverdueAfter: numberOverdueAfter,
        ),
      ],
    ),
  ),
);

const _strings = CardScannerStrings.defaults;
const visa = '4111111111111111';

void main() {
  testWidgets('nothing recognized yet asks for the card', (tester) async {
    await pumpOverlay(tester, stateWith());
    expect(find.text(_strings.alignCard), findsOne);
  });

  testWidgets('the number alone asks for the expiry date', (tester) async {
    await pumpOverlay(tester, stateWith(number: visa));
    expect(find.text(_strings.lookingForExpiry), findsOne);
    expect(find.text('4111 1111 1111 1111'), findsOne);
  });

  testWidgets('number and date ask for the other side', (tester) async {
    await pumpOverlay(tester, stateWith(number: visa, expiry: '12/28'));
    expect(find.text(_strings.lookingForName), findsOne);
  });

  group('the name alone', () {
    testWidgets('does not send anyone to the back of the card at once', (
      tester,
    ) async {
      await pumpOverlay(tester, stateWith(name: 'ADA LOVELACE'));

      // A name regularly confirms a second or two before a number printed
      // beside it, and the number may well be on this side.
      expect(find.text(_strings.lookingForNumber), findsNothing);
      expect(find.text(_strings.alignCard), findsOne);
    });

    testWidgets('suggests turning it over once the number is overdue', (
      tester,
    ) async {
      await pumpOverlay(tester, stateWith(name: 'ADA LOVELACE'));
      await tester.pump(const Duration(seconds: 5));

      expect(find.text(_strings.lookingForNumber), findsOne);
    });

    testWidgets('says nothing about the back if the number arrives first', (
      tester,
    ) async {
      await pumpOverlay(tester, stateWith(name: 'ADA LOVELACE'));
      await tester.pump(const Duration(seconds: 2));
      await pumpOverlay(tester, stateWith(name: 'ADA LOVELACE', number: visa));
      await tester.pump(const Duration(seconds: 5));

      expect(find.text(_strings.lookingForNumber), findsNothing);
      expect(find.text(_strings.lookingForExpiry), findsOne);
    });

    testWidgets('drops the suggestion again when a number turns up', (
      tester,
    ) async {
      await pumpOverlay(tester, stateWith(name: 'ADA LOVELACE'));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(_strings.lookingForNumber), findsOne);

      await pumpOverlay(tester, stateWith(name: 'ADA LOVELACE', number: visa));
      expect(find.text(_strings.lookingForNumber), findsNothing);
    });

    testWidgets('the wait is configurable', (tester) async {
      await pumpOverlay(
        tester,
        stateWith(name: 'ADA LOVELACE'),
        numberOverdueAfter: const Duration(milliseconds: 100),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(_strings.lookingForNumber), findsOne);
    });
  });

  testWidgets('a scan that does not want the name does not ask for it', (
    tester,
  ) async {
    await pumpOverlay(
      tester,
      stateWith(number: visa, expiry: '12/28'),
      requirements: ScanRequirements.numberOnly,
    );
    expect(find.text(_strings.lookingForName), findsNothing);
    expect(find.text(_strings.alignCard), findsOne);
  });

  testWidgets('a field found starts the spinner', (tester) async {
    await pumpOverlay(tester, stateWith());
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await pumpOverlay(tester, stateWith(number: visa));
    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  testWidgets('a complete scan stops the spinner', (tester) async {
    await pumpOverlay(
      tester,
      stateWith(number: visa, expiry: '12/28', isComplete: true),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a field being confirmed starts the spinner', (tester) async {
    await pumpOverlay(
      tester,
      const CardScannerState(confirming: {CardField.number}),
    );
    expect(find.byType(CircularProgressIndicator), findsOne);
  });

  group('haptics', () {
    final taps = <String>[];

    setUp(() {
      taps.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              taps.add('${call.arguments}');
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    testWidgets('one tap per prompt, when asked for', (tester) async {
      await pumpOverlay(tester, stateWith(), enableHaptics: true);
      expect(taps, isEmpty);

      await pumpOverlay(tester, stateWith(number: visa), enableHaptics: true);
      expect(taps, hasLength(1));

      // Same prompt, no second tap.
      await pumpOverlay(tester, stateWith(number: visa), enableHaptics: true);
      expect(taps, hasLength(1));

      await pumpOverlay(
        tester,
        stateWith(number: visa, expiry: '12/28'),
        enableHaptics: true,
      );
      expect(taps, hasLength(2));
    });

    testWidgets('one tap when the overdue number prompt appears', (
      tester,
    ) async {
      await pumpOverlay(
        tester,
        stateWith(name: 'ADA LOVELACE'),
        enableHaptics: true,
      );
      taps.clear();

      await tester.pump(const Duration(seconds: 5));
      expect(taps, hasLength(1));
    });

    testWidgets('silent by default', (tester) async {
      await pumpOverlay(tester, stateWith());
      await pumpOverlay(tester, stateWith(number: visa));
      expect(taps, isEmpty);
    });
  });
}
