import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CardBrand.detect', () {
    test('visa', () {
      expect(CardBrand.detect('4111111111111111'), CardBrand.visa);
      expect(CardBrand.detect('4'), CardBrand.visa);
    });

    test('mastercard legacy 51-55 range', () {
      for (final p in ['51', '52', '53', '54', '55']) {
        expect(
          CardBrand.detect('${p}00000000000000'),
          CardBrand.mastercard,
          reason: p,
        );
      }
      expect(CardBrand.detect('5000000000000000'), isNull);
      expect(CardBrand.detect('5600000000000000'), isNull);
    });

    test('mastercard 2-series range', () {
      expect(CardBrand.detect('2221000000000009'), CardBrand.mastercard);
      expect(CardBrand.detect('2720999999999996'), CardBrand.mastercard);
      expect(CardBrand.detect('2500000000000000'), CardBrand.mastercard);
      expect(CardBrand.detect('2220000000000000'), isNull);
      expect(CardBrand.detect('2721000000000000'), isNull);
    });

    test('amex', () {
      expect(CardBrand.detect('378282246310005'), CardBrand.amex);
      expect(CardBrand.detect('341111111111111'), CardBrand.amex);
      expect(CardBrand.detect('351111111111111'), isNull);
    });

    test('unsupported networks', () {
      expect(CardBrand.detect('6011111111111117'), isNull); // Discover
      expect(CardBrand.detect('3530111333300000'), isNull); // JCB
      expect(CardBrand.detect('30569309025904'), isNull); // Diners
      expect(CardBrand.detect(''), isNull);
    });
  });

  group('CardBrand lengths', () {
    test('valid lengths per brand', () {
      expect(CardBrand.visa.matchesLength(16), isTrue);
      expect(CardBrand.visa.matchesLength(19), isTrue);
      expect(CardBrand.visa.matchesLength(15), isFalse);
      expect(CardBrand.mastercard.matchesLength(16), isTrue);
      expect(CardBrand.mastercard.matchesLength(15), isFalse);
      expect(CardBrand.amex.matchesLength(15), isTrue);
      expect(CardBrand.amex.matchesLength(16), isFalse);
    });
  });

  group('CardBrand.format', () {
    test('4-4-4-4', () {
      expect(CardBrand.visa.format('4111111111111111'), '4111 1111 1111 1111');
    });
    test('4-4-4-4-3 for 19 digits', () {
      expect(
        CardBrand.visa.format('4111111111111111110'),
        '4111 1111 1111 1111 110',
      );
    });
    test('4-6-5 for amex', () {
      expect(CardBrand.amex.format('378282246310005'), '3782 822463 10005');
    });
  });
}
