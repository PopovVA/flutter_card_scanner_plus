import 'dart:typed_data';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandApdu', () {
    test('SELECT by name', () {
      final apdu = CommandApdu.select(EmvIds.visa);
      expect(TlvParser.toHex(apdu.toBytes()), '00A4040007A000000003101000');
    });

    test('SELECT PPSE', () {
      final apdu = CommandApdu.select(EmvIds.ppse);
      expect(
        TlvParser.toHex(apdu.toBytes()),
        '00A404000E325041592E5359532E444446303100',
      );
    });

    test('READ RECORD encodes the short file identifier', () {
      expect(
        TlvParser.toHex(CommandApdu.readRecord(1, 1).toBytes()),
        '00B2010C00',
      );
      expect(
        TlvParser.toHex(CommandApdu.readRecord(2, 3).toBytes()),
        '00B2031400',
      );
    });

    test('GET PROCESSING OPTIONS wraps the PDOL data in tag 83', () {
      expect(
        TlvParser.toHex(
          CommandApdu.getProcessingOptions([0x00, 0x00]).toBytes(),
        ),
        '80A8000004830200 0000'.replaceAll(' ', ''),
      );
    });

    test('a command without data omits Lc', () {
      const apdu = CommandApdu(cla: 0x00, ins: 0xB2, p1: 0x01, p2: 0x0C);
      expect(apdu.toBytes().length, 5);
    });
  });

  group('ResponseApdu', () {
    test('splits payload and status word', () {
      final response = ResponseApdu.fromBytes(
        TlvParser.fromHex('4F07A00000000310109000'),
      );
      expect(response.isSuccess, isTrue);
      expect(response.statusWord, 0x9000);
      expect(TlvParser.toHex(response.data), '4F07A0000000031010');
      expect(response.tlv.single.tag, 0x4F);
    });

    test('recognizes a failure status', () {
      final response = ResponseApdu.fromBytes(TlvParser.fromHex('6A82'));
      expect(response.isSuccess, isFalse);
      expect(response.statusWord, 0x6A82);
      expect(response.data, isEmpty);
    });

    test('recognizes 61xx as more data pending', () {
      expect(
        ResponseApdu.fromBytes(TlvParser.fromHex('6115')).hasMoreData,
        isTrue,
      );
      expect(
        ResponseApdu.fromBytes(TlvParser.fromHex('9000')).hasMoreData,
        isFalse,
      );
    });

    test('tolerates a reply that is too short to hold a status word', () {
      final response = ResponseApdu.fromBytes(Uint8List.fromList([0x90]));
      expect(response.isSuccess, isFalse);
    });
  });
}
