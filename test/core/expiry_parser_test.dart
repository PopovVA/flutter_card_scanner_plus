import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 15);

  group('ExpiryParser', () {
    test('MM/YY', () {
      final e = ExpiryParser.parse('12/28', now: now)!;
      expect(e.month, 12);
      expect(e.year, 2028);
      expect(e.formatted, '12/28');
    });

    test('MM/YYYY', () {
      final e = ExpiryParser.parse('EXP 09/2027', now: now)!;
      expect(e.month, 9);
      expect(e.year, 2027);
    });

    test('with label and spaces around slash', () {
      expect(
        ExpiryParser.parse('VALID THRU 05 / 29', now: now)?.formatted,
        '05/29',
      );
      expect(
        ExpiryParser.parse('GOOD THRU 05-29', now: now)?.formatted,
        '05/29',
      );
    });

    test('picks the latest of several dates (valid from / thru)', () {
      final e = ExpiryParser.parse('03/22 03/27', now: now)!;
      expect(e.formatted, '03/27');
      final all = ExpiryParser.parseAll('03/22 03/27', now: now);
      expect(all.length, 2);
    });

    test('member since is earlier than expiry', () {
      expect(
        ExpiryParser.parse(
          'MEMBER SINCE 05/19 VALID THRU 11/28',
          now: now,
        )?.formatted,
        '11/28',
      );
    });

    test('repairs OCR confusions', () {
      expect(ExpiryParser.parse('I2/2B', now: now)?.formatted, '12/28');
      expect(ExpiryParser.parse('O9/3O', now: now)?.formatted, '09/30');
    });

    test('rejects impossible months', () {
      expect(ExpiryParser.parse('13/28', now: now), isNull);
      expect(ExpiryParser.parse('00/28', now: now), isNull);
    });

    test('rejects years far in the past or future', () {
      expect(ExpiryParser.parse('01/99', now: now), isNull);
      expect(ExpiryParser.parse('01/2005', now: now), isNull);
      expect(ExpiryParser.parse('01/60', now: now), isNull);
    });

    test('accepts recently expired cards', () {
      expect(ExpiryParser.parse('01/24', now: now)?.formatted, '01/24');
    });

    test('does not match inside longer digit runs', () {
      expect(ExpiryParser.parse('4111/1111', now: now), isNull);
      expect(ExpiryParser.parse('1234/2028', now: now), isNull);
    });

    test('single-digit month is not a date', () {
      expect(ExpiryParser.parse('1/28', now: now), isNull);
    });

    test('ordering', () {
      const a = ExpiryCandidate(
        month: 12,
        year: 2027,
        box: TextBox.zero,
        confidence: 1,
      );
      const b = ExpiryCandidate(
        month: 1,
        year: 2028,
        box: TextBox.zero,
        confidence: 1,
      );
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(a.compareTo(a), 0);
    });
  });
}
