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

    test('discover', () {
      expect(CardBrand.detect('6011111111111117'), CardBrand.discover);
      expect(CardBrand.detect('6011000990139424'), CardBrand.discover);
      expect(CardBrand.detect('6445644564456445'), CardBrand.discover);
      expect(CardBrand.detect('6490000000000004'), CardBrand.discover);
      expect(CardBrand.detect('6500000000000002'), CardBrand.discover);
      expect(CardBrand.detect('6430000000000000'), isNull);
      expect(CardBrand.detect('6600000000000000'), isNull);
    });

    test('jcb', () {
      expect(CardBrand.detect('3530111333300000'), CardBrand.jcb);
      expect(CardBrand.detect('3566002020360505'), CardBrand.jcb);
      expect(CardBrand.detect('3528100000000005'), CardBrand.jcb);
      expect(CardBrand.detect('3527000000000000'), isNull);
      expect(CardBrand.detect('3590000000000000'), isNull);
    });

    test('diners club', () {
      expect(CardBrand.detect('30569309025904'), CardBrand.diners);
      expect(CardBrand.detect('38520000023237'), CardBrand.diners);
      expect(CardBrand.detect('30950000000000'), CardBrand.diners);
      expect(CardBrand.detect('39000000000005'), CardBrand.diners);
      expect(CardBrand.detect('30600000000000'), isNull);
    });

    test('unionpay', () {
      expect(CardBrand.detect('6200000000000005'), CardBrand.unionpay);
      expect(CardBrand.detect('8171999927660000'), CardBrand.unionpay);
      expect(CardBrand.detect('8100000000000002'), CardBrand.unionpay);
    });

    test('the range Discover and UnionPay share goes to unionpay', () {
      expect(CardBrand.detect('6221260000000000'), CardBrand.unionpay);
      expect(CardBrand.detect('6229250000000000'), CardBrand.unionpay);
    });

    test('still unsupported', () {
      expect(CardBrand.detect('5061000000000000'), isNull); // Verve
      expect(CardBrand.detect('5018000000000000'), isNull); // Maestro
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
      expect(CardBrand.discover.matchesLength(16), isTrue);
      expect(CardBrand.discover.matchesLength(19), isTrue);
      expect(CardBrand.discover.matchesLength(15), isFalse);
      expect(CardBrand.jcb.matchesLength(17), isTrue);
      expect(CardBrand.jcb.matchesLength(15), isFalse);
      expect(CardBrand.diners.matchesLength(14), isTrue);
      expect(CardBrand.diners.matchesLength(15), isFalse);
      expect(CardBrand.unionpay.matchesLength(19), isTrue);
    });

    test('every brand has a name and at least one length', () {
      for (final brand in CardBrand.values) {
        expect(brand.displayName, isNotEmpty, reason: brand.name);
        expect(brand.validLengths, isNotEmpty, reason: brand.name);
        expect(brand.grouping, isNotEmpty, reason: brand.name);
      }
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
    test('4-6-4 for a 14 digit diners card', () {
      expect(CardBrand.diners.format('30569309025904'), '3056 930902 5904');
    });
    test('a 16 digit diners card uses the usual blocks', () {
      expect(
        CardBrand.diners.format('3056930902590400'),
        '3056 9309 0259 0400',
      );
    });
  });
}
