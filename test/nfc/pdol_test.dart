import 'dart:math';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedDate = DateTime(2026, 9, 22);
  final rng = Random(1);

  group('Dol.parse', () {
    test('reads single and multi byte tags', () {
      final entries = Dol.parse(TlvParser.fromHex('9F6604 9F1A02 9505'));
      expect(entries.map((e) => e.tag), [0x9F66, 0x9F1A, 0x95]);
      expect(entries.map((e) => e.length), [4, 2, 5]);
    });

    test('stops on a truncated entry instead of throwing', () {
      expect(Dol.parse(TlvParser.fromHex('9F66')), isEmpty);
      expect(Dol.parse(TlvParser.fromHex('')), isEmpty);
    });
  });

  group('Dol.buildValues', () {
    test('supplies the transaction qualifiers and country code', () {
      final values = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9F66049F1A02')),
        now: fixedDate,
        random: rng,
      );
      expect(TlvParser.toHex(values), '360040000840');
    });

    test('honours a custom profile', () {
      final values = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9F1A025F2A02')),
        profile: const TerminalProfile(
          countryCode: 0x0643,
          currencyCode: 0x0978,
        ),
        now: fixedDate,
        random: rng,
      );
      expect(TlvParser.toHex(values), '06430978');
    });

    test('encodes the transaction date as BCD YYMMDD', () {
      final values = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9A03')),
        now: fixedDate,
        random: rng,
      );
      expect(TlvParser.toHex(values), '260922');
    });

    test('sends zeros for amounts and anything unknown', () {
      final values = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9F02069F03069C01')),
        now: fixedDate,
        random: rng,
      );
      expect(TlvParser.toHex(values), '0' * 26);
    });

    test('pads a short value and cuts a long one to the asked length', () {
      // 9F66 is four bytes; ask for two and six.
      final short = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9F6602')),
        now: fixedDate,
        random: rng,
      );
      final long = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9F6606')),
        now: fixedDate,
        random: rng,
      );
      expect(TlvParser.toHex(short), '3600');
      expect(TlvParser.toHex(long), '360040000000');
    });

    test('the unpredictable number fills its four bytes', () {
      final values = Dol.buildValues(
        Dol.parse(TlvParser.fromHex('9F3704')),
        now: fixedDate,
        random: Random(7),
      );
      expect(values.length, 4);
    });

    test('an empty list builds nothing', () {
      expect(Dol.buildValues(const [], now: fixedDate, random: rng), isEmpty);
    });
  });
}
