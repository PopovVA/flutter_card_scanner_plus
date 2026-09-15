import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

TextLine line(
  String text,
  double left,
  double top, {
  double w = 0.3,
  double h = 0.06,
  double c = 1,
}) => TextLine(
  text: text,
  box: TextBox(left: left, top: top, width: w, height: h),
  confidence: c,
);

void main() {
  final now = DateTime(2026, 9, 15);

  group('CardFrameParser.groupIntoRows', () {
    test('merges horizontally adjacent fragments on one row', () {
      final rows = CardFrameParser.groupIntoRows([
        line('1111 1111', 0.5, 0.40, w: 0.3, h: 0.08),
        line('4111 1111', 0.1, 0.41, w: 0.3, h: 0.08),
      ]);
      expect(rows.length, 1);
      expect(rows.single.text, '4111 1111 1111 1111');
      expect(rows.single.box.left, 0.1);
      expect(rows.single.box.right, closeTo(0.8, 1e-9));
    });

    test('keeps vertically separated lines apart', () {
      final rows = CardFrameParser.groupIntoRows([
        line('JOHN SMITH', 0.1, 0.8),
        line('4111 1111 1111 1111', 0.1, 0.4),
      ]);
      expect(rows.map((r) => r.text), ['4111 1111 1111 1111', 'JOHN SMITH']);
    });

    test('averages confidence of merged fragments', () {
      final rows = CardFrameParser.groupIntoRows([
        line('A', 0.1, 0.4, c: 0.8),
        line('B', 0.5, 0.4, c: 0.4),
      ]);
      expect(rows.single.confidence, closeTo(0.6, 1e-9));
    });

    test('lines without geometry are never merged', () {
      final rows = CardFrameParser.groupIntoRows([
        const TextLine(text: 'A'),
        const TextLine(text: 'B'),
      ]);
      expect(rows.length, 2);
    });
  });

  group('CardFrameParser.parse', () {
    test('typical visa layout', () {
      final frame = RecognizedFrame(
        lines: [
          line('BIG BANK', 0.05, 0.05),
          line('4111 1111 1111 1111', 0.05, 0.45, w: 0.8, h: 0.1),
          line('VALID THRU', 0.3, 0.62, w: 0.15, h: 0.04),
          line('12/28', 0.5, 0.62, w: 0.12, h: 0.06),
          line('JOHN SMITH', 0.05, 0.78),
          line('VISA', 0.8, 0.85, w: 0.15),
        ],
      );
      final r = CardFrameParser.parse(frame, now: now);
      expect(r.pan?.number, '4111111111111111');
      expect(r.pan?.brand, CardBrand.visa);
      expect(r.expiry?.formatted, '12/28');
      expect(r.name?.name, 'JOHN SMITH');
    });

    test('amex layout with member since and split number', () {
      final frame = RecognizedFrame(
        lines: [
          line('AMERICAN EXPRESS', 0.05, 0.05),
          line('3782', 0.05, 0.45, w: 0.15, h: 0.1),
          line('822463', 0.25, 0.45, w: 0.25, h: 0.1),
          line('10005', 0.55, 0.45, w: 0.2, h: 0.1),
          line('MEMBER SINCE 19', 0.05, 0.6, w: 0.3, h: 0.04),
          line('VALID THRU 04/29', 0.5, 0.6, w: 0.3, h: 0.04),
          line('C F FROST', 0.05, 0.8),
        ],
      );
      final r = CardFrameParser.parse(frame, now: now);
      expect(r.pan?.number, '378282246310005');
      expect(r.pan?.brand, CardBrand.amex);
      expect(r.expiry?.formatted, '04/29');
      expect(r.name?.name, 'C F FROST');
    });

    test('partial frame: number only', () {
      final frame = RecognizedFrame(
        lines: [line('5555 5555 5555 4444', 0.05, 0.45)],
      );
      final r = CardFrameParser.parse(frame, now: now);
      expect(r.pan?.brand, CardBrand.mastercard);
      expect(r.expiry, isNull);
      expect(r.name, isNull);
    });

    test('empty frame', () {
      expect(CardFrameParser.parse(RecognizedFrame.empty).isEmpty, isTrue);
    });

    test('name detection ignores lines above the number', () {
      final frame = RecognizedFrame(
        lines: [
          line('ZEBRA MONEY', 0.05, 0.05),
          line('4111 1111 1111 1111', 0.05, 0.45, w: 0.8, h: 0.1),
        ],
      );
      final r = CardFrameParser.parse(frame, now: now);
      // Only candidate is above the PAN — still returned, but negatively scored.
      expect(r.name?.name, 'ZEBRA MONEY');
      expect(r.name!.score, lessThan(0));
    });
  });
}
