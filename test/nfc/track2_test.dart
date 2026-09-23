import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Track2Parser.parse', () {
    test('splits number and expiry on the D separator', () {
      final data = Track2Parser.parse('4111111111111111D28122010000000F')!;
      expect(data.pan, '4111111111111111');
      expect(data.brand, CardBrand.visa);
      expect(data.expiryMonth, 12);
      expect(data.expiryYear, 2028);
    });

    test('reads the expiry as YYMM, not MMYY', () {
      // 2812 is December 2028; read the other way it would be month 28.
      expect(Track2Parser.parse('4111111111111111D2812201')!.expiryMonth, 12);
    });

    test('accepts an Amex track', () {
      final data = Track2Parser.parse('378282246310005D30122011')!;
      expect(data.pan, '378282246310005');
      expect(data.brand, CardBrand.amex);
      expect(data.expiryMonth, 12);
      expect(data.expiryYear, 2030);
    });

    test('accepts the = separator used by some cards', () {
      expect(
        Track2Parser.parse('5555555555554444=2812201')?.pan,
        '5555555555554444',
      );
    });

    test('strips F padding from the number', () {
      expect(
        Track2Parser.parse('378282246310005FD2812201')?.pan,
        '378282246310005',
      );
    });

    test('returns null without a separator but a valid number', () {
      final data = Track2Parser.parse('4111111111111111');
      expect(data?.pan, '4111111111111111');
      expect(data?.hasExpiry, isFalse);
    });

    test('rejects a number that fails the Luhn check', () {
      expect(Track2Parser.parse('4111111111111112D2812201'), isNull);
    });

    test('rejects an unsupported network', () {
      // Discover, Luhn valid but out of scope for this package.
      expect(Track2Parser.parse('6011111111111117D2812201'), isNull);
    });

    test('rejects a malformed month', () {
      final data = Track2Parser.parse('4111111111111111D2813201');
      expect(data?.pan, '4111111111111111');
      expect(data?.expiryMonth, isNull);
    });

    test('rejects junk', () {
      expect(Track2Parser.parse(''), isNull);
      expect(Track2Parser.parse('D2812201'), isNull);
      expect(Track2Parser.parse('123D2812201'), isNull);
    });
  });

  group('Track2Parser.fromPan', () {
    test('reads tag 5A and drops padding', () {
      expect(Track2Parser.fromPan('4111111111111111')?.brand, CardBrand.visa);
      expect(Track2Parser.fromPan('378282246310005F')?.pan, '378282246310005');
    });

    test('rejects an invalid number', () {
      expect(Track2Parser.fromPan('4111111111111112'), isNull);
    });
  });

  group('Track2Parser.parseExpiryDate', () {
    test('reads tag 5F24 as YYMMDD', () {
      expect(Track2Parser.parseExpiryDate('281231'), (12, 2028));
      expect(Track2Parser.parseExpiryDate('3001'), (1, 2030));
    });

    test('rejects a malformed date', () {
      expect(Track2Parser.parseExpiryDate('2813'), isNull);
      expect(Track2Parser.parseExpiryDate('28'), isNull);
    });
  });
}
