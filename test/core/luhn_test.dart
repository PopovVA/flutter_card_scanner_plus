import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Luhn', () {
    test('accepts valid numbers', () {
      for (final n in [
        '4111111111111111',
        '4012888888881881',
        '5555555555554444',
        '2223003122003222',
        '378282246310005',
        '371449635398431',
        '4111111111111111110',
        '79927398713',
      ]) {
        expect(Luhn.isValid(n), isTrue, reason: n);
      }
    });

    test('rejects invalid numbers', () {
      for (final n in [
        '4111111111111112',
        '1234567812345678',
        '378282246310006',
        '0',
        '',
      ]) {
        expect(Luhn.isValid(n), isFalse, reason: '"$n"');
      }
    });

    test('rejects non-digit input', () {
      expect(Luhn.isValid('4111 1111 1111 1111'), isFalse);
      expect(Luhn.isValid('4111111111111111a'), isFalse);
    });
  });
}
