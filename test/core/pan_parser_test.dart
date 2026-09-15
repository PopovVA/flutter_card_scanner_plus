import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PanParser.parse', () {
    test('clean visa with spaces', () {
      final c = PanParser.parse('4111 1111 1111 1111')!;
      expect(c.number, '4111111111111111');
      expect(c.brand, CardBrand.visa);
      expect(c.confidence, 1.0);
    });

    test('clean amex 4-6-5 grouping', () {
      final c = PanParser.parse('3782 822463 10005')!;
      expect(c.number, '378282246310005');
      expect(c.brand, CardBrand.amex);
    });

    test('mastercard 2-series without spaces', () {
      final c = PanParser.parse('2223003122003222')!;
      expect(c.number, '2223003122003222');
      expect(c.brand, CardBrand.mastercard);
    });

    test('19-digit visa', () {
      final c = PanParser.parse('4111 1111 1111 1111 110')!;
      expect(c.number, '4111111111111111110');
      expect(c.brand, CardBrand.visa);
    });

    test('repairs O→0 and I→1 confusions', () {
      final c = PanParser.parse('4O12 8888 8888 I881')!;
      expect(c.number, '4012888888881881');
      expect(c.brand, CardBrand.visa);
      expect(c.confidence, lessThan(1.0));
      expect(c.confidence, greaterThan(0.7));
    });

    test('repairs S→5 and B→8', () {
      expect(
        PanParser.parse('5S55 5555 5555 4444')?.number,
        '5555555555554444',
      );
      expect(
        PanParser.parse('4012 8B88 8888 1881')?.number,
        '4012888888881881',
      );
    });

    test('a token that is mostly letters is not treated as digits', () {
      // "SSSS" has no real digits — could be a word, so it breaks the run.
      expect(PanParser.parse('SSSS 5555 5555 4444'), isNull);
    });

    test('dashes as separators', () {
      expect(
        PanParser.parse('4111-1111-1111-1111')?.number,
        '4111111111111111',
      );
    });

    test('finds number embedded in surrounding text', () {
      final c = PanParser.parse('4111 1111 1111 1111 VALID')!;
      expect(c.number, '4111111111111111');
    });

    test('finds number when OCR glued digits to it', () {
      // e.g. a "1" from the chip/logo artefact glued to the front.
      final c = PanParser.parse('14111 1111 1111 1111')!;
      expect(c.number, '4111111111111111');
      expect(c.confidence, lessThan(1.0));
    });

    test('rejects luhn failure', () {
      expect(PanParser.parse('4111 1111 1111 1112'), isNull);
    });

    test('rejects unsupported brand even when luhn-valid', () {
      expect(PanParser.parse('6011 1111 1111 1117'), isNull);
    });

    test('rejects wrong length for brand', () {
      // 13-digit Visa test number: luhn-valid, but 13 digits are no longer issued.
      expect(PanParser.parse('4222 2222 22222'), isNull);
    });

    test('recovers a 15-digit amex from a 16-digit run', () {
      // Trailing artefact glued to the number.
      expect(PanParser.parse('3782822463100050')?.number, '378282246310005');
    });

    test('ignores ordinary words and short numbers', () {
      expect(PanParser.parse('VALID THRU 12/26'), isNull);
      expect(PanParser.parse('JOHN SMITH'), isNull);
      expect(PanParser.parse('SOLO BOSS'), isNull);
      expect(PanParser.parse(''), isNull);
    });

    test('does not repair a word into digits', () {
      // All look-alike letters, zero real digits — must not become a PAN.
      expect(PanParser.parse('OOOO OOOO OOOO OOOO'), isNull);
    });

    test('propagates line confidence and box', () {
      const box = TextBox(left: 0.1, top: 0.5, width: 0.8, height: 0.1);
      final c = PanParser.parseLine(
        const TextLine(text: '4111 1111 1111 1111', box: box, confidence: 0.9),
      )!;
      expect(c.box, box);
      expect(c.confidence, closeTo(0.9, 1e-9));
    });

    test('toString masks the number', () {
      final s = PanParser.parse('4111 1111 1111 1111').toString();
      expect(s, isNot(contains('4111111111111111')));
      expect(s, contains('1111'));
    });
  });
}
