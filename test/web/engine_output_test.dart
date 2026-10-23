import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the browser engine actually returns, copied from a run of
/// `example/web/worker_harness.html` in Chrome against a synthetic card.
///
/// The point of pinning it is the shape rather than the text: PaddleOCR
/// hands back whole printed rows, so the name and the expiry date arrive
/// as one line, and the parser has to take them apart. A unit test written
/// from imagination tends to hand over one tidy field per line.
const _recognized = RecognizedFrame(
  lines: [
    TextLine(
      text: 'ZEBRA MONEY',
      box: TextBox(left: 0.042, top: 0.128, width: 0.336, height: 0.056),
      confidence: 0.97,
    ),
    TextLine(
      text: '4111 1111 1111 1111',
      box: TextBox(left: 0.048, top: 0.452, width: 0.842, height: 0.084),
      confidence: 0.98,
    ),
    TextLine(
      text: 'ALICE GREEN 12/28',
      box: TextBox(left: 0.040, top: 0.732, width: 0.753, height: 0.059),
      confidence: 0.99,
    ),
  ],
);

void main() {
  final parsed = CardFrameParser.parse(_recognized, now: DateTime(2026, 10));

  test('the number is read', () {
    expect(parsed.pan?.number, '4111111111111111');
    expect(parsed.pan?.brand, CardBrand.visa);
  });

  test('the expiry date is taken out of the row it shares', () {
    expect(parsed.expiry?.month, 12);
    expect(parsed.expiry?.year, 2028);
  });

  test('the name is taken out of the same row, without the date', () {
    expect(parsed.name?.name, 'ALICE GREEN');
  });

  test('the issuer at the top of the card is not the name', () {
    expect(parsed.name?.name, isNot('ZEBRA MONEY'));
  });

  test('a scan completes on one frame of this', () {
    final result = CardScanner.resultFromFrame(parsed, ScanRequirements.full);
    expect(result.number, '4111111111111111');
    expect(result.formattedExpiry, '12/28');
    expect(result.cardholderName, 'ALICE GREEN');
    expect(result.isComplete, isTrue);
  });
}
