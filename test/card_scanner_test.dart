import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pan = PanCandidate(
    number: '4242424242424242',
    brand: CardBrand.visa,
    box: TextBox.zero,
    confidence: 1,
  );
  const expiry = ExpiryCandidate(
    month: 12,
    year: 2028,
    box: TextBox.zero,
    confidence: 1,
  );
  const name = NameCandidate(
    name: 'JOHN A SMITH',
    box: TextBox.zero,
    confidence: 1,
  );

  group('CardScanner.resultFromFrame', () {
    test('complete with pan + expiry under standard requirements', () {
      final r = CardScanner.resultFromFrame(
        const FrameParseResult(pan: pan, expiry: expiry),
        ScanRequirements.standard,
      );
      expect(r.number, '4242424242424242');
      expect(r.brand, CardBrand.visa);
      expect(r.formattedExpiry, '12/28');
      expect(r.isComplete, isTrue);
    });

    test('incomplete without expiry under standard requirements', () {
      final r = CardScanner.resultFromFrame(
        const FrameParseResult(pan: pan),
        ScanRequirements.standard,
      );
      expect(r.isComplete, isFalse);
    });

    test('full requirements need a name', () {
      expect(
        CardScanner.resultFromFrame(
          const FrameParseResult(pan: pan, expiry: expiry),
          ScanRequirements.full,
        ).isComplete,
        isFalse,
      );
      expect(
        CardScanner.resultFromFrame(
          const FrameParseResult(pan: pan, expiry: expiry, name: name),
          ScanRequirements.full,
        ).cardholderName,
        'JOHN A SMITH',
      );
    });

    test('empty frame gives empty result', () {
      expect(
        CardScanner.resultFromFrame(
          FrameParseResult.empty,
          ScanRequirements.standard,
        ),
        CardScanResult.empty,
      );
    });
  });
}
