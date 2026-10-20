import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// One OCR box, in card-relative coordinates: the region of interest is the
/// card, so 0.5 is the middle of it whatever the device does.
TextLine at(String text, double left, double top, {double w = 0.3}) => TextLine(
  text: text,
  box: TextBox(left: left, top: top, width: w, height: 0.07),
  confidence: 1,
);

/// The blocks every card has, laid out the way they are printed.
const _pan = TextLine(
  text: '4111 1111 1111 1111',
  box: TextBox(left: 0.06, top: 0.46, width: 0.80, height: 0.09),
);
final _expiry = at('VALID THRU 12/28', 0.06, 0.64, w: 0.26);

RecognizedFrame card(List<TextLine> extra) =>
    RecognizedFrame(lines: [_pan, _expiry, ...extra]);

String? nameIn(List<TextLine> extra) =>
    CardFrameParser.parse(card(extra), now: DateTime(2026, 9, 15)).name?.name;

void main() {
  group('a name split across OCR boxes', () {
    test('words on one row are joined', () {
      expect(
        nameIn([at('ADA', 0.06, 0.78, w: 0.12), at('LOVELACE', 0.20, 0.78)]),
        'ADA LOVELACE',
      );
    });

    test('branding on the same row is dropped, the name survives', () {
      expect(
        nameIn([
          at('ADA', 0.06, 0.78, w: 0.12),
          at('LOVELACE', 0.20, 0.78),
          at('VISA', 0.80, 0.78, w: 0.12),
        ]),
        'ADA LOVELACE',
      );
    });

    test('a number glued to the end of the row is dropped', () {
      expect(
        nameIn([
          at('ADA LOVELACE', 0.06, 0.78),
          at('1234', 0.78, 0.78, w: 0.1),
        ]),
        'ADA LOVELACE',
      );
    });

    test('words on different rows are not joined', () {
      expect(
        nameIn([at('ADA', 0.06, 0.70, w: 0.12), at('LOVELACE', 0.06, 0.82)]),
        isNull,
      );
    });

    test('branding alone is not a name', () {
      expect(nameIn([at('VISA PLATINUM', 0.06, 0.78)]), isNull);
      expect(
        nameIn([at('VISA', 0.06, 0.78, w: 0.12), at('PLATINUM', 0.20, 0.78)]),
        isNull,
      );
    });
  });

  group('card words that are also names', () {
    test('a colour or a bank keeps its place beside a plain word', () {
      expect(nameIn([at('ALICE GREEN', 0.06, 0.78)]), 'ALICE GREEN');
      expect(nameIn([at('JOHN A BLACK', 0.06, 0.78)]), 'JOHN A BLACK');
      expect(nameIn([at('MARY SILVER', 0.06, 0.78)]), 'MARY SILVER');
      expect(nameIn([at('CHASE SMITH', 0.06, 0.78)]), 'CHASE SMITH');
      expect(nameIn([at('ROSA GOLD', 0.06, 0.78)]), 'ROSA GOLD');
    });

    test('the same word alone is still card art', () {
      expect(nameIn([at('VISA GOLD', 0.06, 0.78)]), isNull);
      expect(nameIn([at('AMEX GREEN', 0.06, 0.78)]), isNull);
      expect(nameIn([at('CHASE SAPPHIRE', 0.06, 0.78)]), isNull);
      expect(nameIn([at('BLACK CARD', 0.06, 0.78)]), isNull);
      expect(nameIn([at('WELLS FARGO', 0.06, 0.78)]), isNull);
      expect(
        nameIn([at('CHASE SAPPHIRE PREFERRED', 0.06, 0.78, w: 0.5)]),
        isNull,
      );
    });

    test('a row keeps the whole name, whichever end the card word sits at', () {
      expect(
        nameIn([
          at('JOHN', 0.06, 0.78, w: 0.12),
          at('A', 0.2, 0.78, w: 0.04),
          at('BLACK', 0.26, 0.78, w: 0.16),
        ]),
        'JOHN A BLACK',
      );
      expect(
        nameIn([at('ALICE', 0.06, 0.78, w: 0.16), at('GREEN', 0.24, 0.78)]),
        'ALICE GREEN',
      );
      expect(
        nameIn([at('GREEN', 0.06, 0.78, w: 0.16), at('ALICE', 0.24, 0.78)]),
        'GREEN ALICE',
      );
    });

    test('every name-like word is also an ordinary stop word', () {
      expect(NameParser.stopWords, containsAll(NameParser.nameLikeStopWords));
    });
  });

  group('name shapes', () {
    test('a middle initial', () {
      expect(
        nameIn([at('WREN A. NGUYEN', 0.06, 0.78, w: 0.4)]),
        'WREN A. NGUYEN',
      );
    });

    test('a middle name', () {
      expect(
        nameIn([at('WREN ADA NGUYEN', 0.06, 0.78, w: 0.4)]),
        'WREN ADA NGUYEN',
      );
    });

    test('particles stay in the name', () {
      expect(
        nameIn([at('MARIA DE LA CRUZ', 0.06, 0.78, w: 0.44)]),
        'MARIA DE LA CRUZ',
      );
    });

    test('a hyphenated surname', () {
      expect(
        nameIn([at('AMARA OKOYE-BELL', 0.06, 0.78, w: 0.4)]),
        'AMARA OKOYE-BELL',
      );
    });
  });

  group('text printed beside the name block', () {
    test('a material claim does not become the name', () {
      // The card that reported this: the holder name is printed above the
      // number, the claim to the right of where the name usually goes.
      expect(
        nameIn([
          at('ADA LOVELACE', 0.06, 0.36),
          at('RECYCLED', 0.62, 0.70, w: 0.2),
          at('PLASTIC', 0.62, 0.78, w: 0.18),
        ]),
        'ADA LOVELACE',
      );
    });

    test(
      'an unknown phrase right of the number loses to a left aligned name',
      () {
        expect(
          nameIn([
            at('ADA LOVELACE', 0.06, 0.36),
            at('PURE EARTH', 0.62, 0.70),
          ]),
          'ADA LOVELACE',
        );
      },
    );

    test('the same phrase still loses when the name is below the number', () {
      expect(
        nameIn([at('ADA LOVELACE', 0.06, 0.78), at('PURE EARTH', 0.62, 0.70)]),
        'ADA LOVELACE',
      );
    });

    test('the issuer name at the top of the card is not the holder', () {
      expect(
        nameIn([at('ZEBRA MONEY', 0.06, 0.06), at('ADA LOVELACE', 0.06, 0.78)]),
        'ADA LOVELACE',
      );
    });
  });
}
