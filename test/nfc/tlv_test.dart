import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real PPSE reply: FCI naming 2PAY.SYS.DDF01, one Visa application.
const ppseResponse =
    '6F2F'
    '840E325041592E5359532E4444463031'
    'A51D'
    'BF0C1A'
    '6118'
    '4F07A0000000031010'
    '500A56495341204445424954'
    '870101';

void main() {
  group('TlvParser', () {
    test('parses a primitive element', () {
      final tlv = TlvParser.parse(TlvParser.fromHex('4F07A0000000031010'));
      expect(tlv.length, 1);
      expect(tlv.single.tag, 0x4F);
      expect(tlv.single.hex, 'A0000000031010');
      expect(tlv.single.isConstructed, isFalse);
    });

    test('recurses into constructed elements', () {
      final tlv = TlvParser.parse(TlvParser.fromHex(ppseResponse));
      expect(tlv.length, 1);
      expect(tlv.single.tag, 0x6F);
      expect(tlv.single.isConstructed, isTrue);
      expect(TlvParser.find(tlv, 0x84)?.value.length, 14);
    });

    test('reads a multi byte tag', () {
      final tlv = TlvParser.parse(TlvParser.fromHex(ppseResponse));
      expect(TlvParser.find(tlv, 0xBF0C), isNotNull);
      expect(TlvParser.find(tlv, 0x61), isNotNull);
    });

    test('finds the AID at any depth', () {
      final tlv = TlvParser.parse(TlvParser.fromHex(ppseResponse));
      expect(TlvParser.find(tlv, EmvIds.tagAid)?.hex, 'A0000000031010');
      expect(
        TlvParser.find(tlv, EmvIds.tagApplicationLabel)?.hex,
        '56495341204445424954',
      );
    });

    test('findAll returns every match in order', () {
      // Two application templates in one directory.
      final two = TlvParser.parse(
        TlvParser.fromHex(
          '6F19BF0C16'
          '61094F07A0000000031010'
          '61094F07A0000000041010',
        ),
      );
      final aids = TlvParser.findAll(two, EmvIds.tagAid).map((t) => t.hex);
      expect(aids, ['A0000000031010', 'A0000000041010']);
    });

    test('reads a two byte length', () {
      final long = '70820104${'00' * 260}';
      final tlv = TlvParser.parse(TlvParser.fromHex(long));
      expect(tlv.single.tag, 0x70);
      expect(tlv.single.value.length, 260);
    });

    test('skips padding between elements', () {
      final tlv = TlvParser.parse(
        TlvParser.fromHex('00FF4F07A000000003101000'),
      );
      expect(tlv.single.tag, 0x4F);
    });

    test('stops instead of throwing on truncated input', () {
      // Declares 7 bytes, provides 3.
      expect(TlvParser.parse(TlvParser.fromHex('4F07A00000')), isEmpty);
      expect(TlvParser.parse(TlvParser.fromHex('4F')), isEmpty);
      expect(TlvParser.parse(TlvParser.fromHex('')), isEmpty);
    });

    test('hex round trip', () {
      expect(
        TlvParser.toHex(TlvParser.fromHex('A0 00 00 00 03')),
        'A000000003',
      );
    });
  });
}
