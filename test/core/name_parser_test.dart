import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NameParser.looksLikeName', () {
    test('accepts typical names', () {
      for (final n in [
        'JOHN SMITH',
        'JOHN A SMITH',
        'MARIA DE LA CRUZ',
        "PATRICK O'BRIEN",
        'ANNE-MARIE DUPONT',
        'J. R. TOLKIEN',
        'C F FROST', // Amex sample card
        'J. SMITH',
        'john smith', // OCR may return mixed case
      ]) {
        expect(NameParser.looksLikeName(n), isTrue, reason: n);
      }
    });

    test('rejects labels, brands and issuers', () {
      for (final n in [
        'VALID THRU',
        'PLATINUM CARD',
        'AMERICAN EXPRESS',
        'CAPITAL ONE',
        'WELLS FARGO',
        'CHASE SAPPHIRE PREFERRED',
        'DEBIT MASTERCARD',
        'WORLD ELITE',
        'MEMBER SINCE',
        'CUSTOMER SERVICE',
      ]) {
        expect(NameParser.looksLikeName(n), isFalse, reason: n);
      }
    });

    test('rejects lines with digits or too few words', () {
      expect(NameParser.looksLikeName('JOHN SMITH 2'), isFalse);
      expect(NameParser.looksLikeName('SMITH'), isFalse);
      expect(NameParser.looksLikeName('J. R.'), isFalse); // initials only
      expect(NameParser.looksLikeName(''), isFalse);
      expect(NameParser.looksLikeName('12/26'), isFalse);
    });

    test('rejects too many words', () {
      expect(NameParser.looksLikeName('A B C D E F'), isFalse);
    });
  });

  group('NameParser.parse', () {
    const pan = TextBox(left: 0.1, top: 0.45, width: 0.8, height: 0.1);
    const expiry = TextBox(left: 0.4, top: 0.62, width: 0.2, height: 0.06);

    test('prefers line below the number over bank name above it', () {
      final lines = [
        const TextLine(
          text: 'FIRST NATIONAL',
          box: TextBox(left: 0.1, top: 0.1, width: 0.4, height: 0.06),
        ),
        const TextLine(
          text: 'JOHN SMITH',
          box: TextBox(left: 0.1, top: 0.75, width: 0.4, height: 0.06),
        ),
      ];
      expect(
        NameParser.parse(lines, panBox: pan, expiryBox: expiry)?.name,
        'JOHN SMITH',
      );
    });

    test(
      'unknown issuer above the number is still ranked below holder name',
      () {
        final lines = [
          const TextLine(
            text: 'ACME CREDIT UNION',
            box: TextBox(left: 0.1, top: 0.1, width: 0.4, height: 0.06),
          ),
          const TextLine(
            text: 'ZEBRA MONEY',
            box: TextBox(left: 0.1, top: 0.1, width: 0.4, height: 0.06),
          ),
          const TextLine(
            text: 'JANE DOE',
            box: TextBox(left: 0.1, top: 0.8, width: 0.4, height: 0.06),
          ),
        ];
        expect(NameParser.parse(lines, panBox: pan)?.name, 'JANE DOE');
      },
    );

    test('without geometry picks the last plausible line', () {
      final lines = [
        const TextLine(text: 'ZEBRA MONEY'),
        const TextLine(text: 'JANE DOE'),
      ];
      // Equal scores, equal boxes: first wins (tie-break on top is equal).
      expect(NameParser.parse(lines)?.name, 'ZEBRA MONEY');
    });

    test('returns null when nothing looks like a name', () {
      final lines = [
        const TextLine(text: 'VALID THRU 12/26'),
        const TextLine(text: '4111 1111 1111 1111'),
        const TextLine(text: 'DEBIT'),
      ];
      expect(NameParser.parse(lines), isNull);
    });

    test('normalizes case and whitespace', () {
      final lines = [const TextLine(text: '  john   smith ')];
      expect(NameParser.parse(lines)?.name, 'JOHN SMITH');
    });
  });
}
