import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const full = CardScanResult(
    number: '378282246310005',
    brand: CardBrand.amex,
    expiryMonth: 4,
    expiryYear: 2029,
    cardholderName: 'C F FROST',
    isComplete: true,
  );

  group('CardScanResult', () {
    test('formatting helpers', () {
      expect(full.formattedNumber, '3782 822463 10005');
      expect(full.maskedNumber, '•••• 0005');
      expect(full.last4, '0005');
      expect(full.formattedExpiry, '04/29');
    });

    test('empty result helpers are null', () {
      expect(CardScanResult.empty.formattedNumber, isNull);
      expect(CardScanResult.empty.maskedNumber, isNull);
      expect(CardScanResult.empty.formattedExpiry, isNull);
      expect(CardScanResult.empty.isExpired(), isFalse);
    });

    test('isExpired', () {
      expect(full.isExpired(now: DateTime(2029, 4, 30)), isFalse);
      expect(full.isExpired(now: DateTime(2029, 5, 1)), isTrue);
      expect(full.isExpired(now: DateTime(2030, 1, 1)), isTrue);
      expect(full.isExpired(now: DateTime(2026, 1, 1)), isFalse);
    });

    test('toString never leaks the full number', () {
      final s = full.toString();
      expect(s, isNot(contains('378282246310005')));
      expect(s, contains('0005'));
      expect(s, contains('04/29'));
    });

    test('equality and copyWith', () {
      expect(full, full.copyWith());
      expect(full.copyWith(cardholderName: 'X'), isNot(full));
    });
  });
}
