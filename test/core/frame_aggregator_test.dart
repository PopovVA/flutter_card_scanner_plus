import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

FrameParseResult frame({String? pan, String? expiry, String? name}) =>
    FrameParseResult(
      pan: pan == null
          ? null
          : PanCandidate(
              number: pan,
              brand: CardBrand.detect(pan)!,
              box: TextBox.zero,
              confidence: 1,
            ),
      expiry: expiry == null
          ? null
          : ExpiryCandidate(
              month: int.parse(expiry.split('/')[0]),
              year: 2000 + int.parse(expiry.split('/')[1]),
              box: TextBox.zero,
              confidence: 1,
            ),
      name: name == null
          ? null
          : NameCandidate(name: name, box: TextBox.zero, confidence: 1),
    );

const visa = '4111111111111111';
const visa2 = '4012888888881881';

void main() {
  group('FrameAggregator', () {
    test('requires N agreeing frames before accepting a number', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3),
      );
      expect(agg.add(frame(pan: visa)).number, isNull);
      expect(agg.add(frame(pan: visa)).number, isNull);
      final r = agg.add(frame(pan: visa));
      expect(r.number, visa);
      expect(r.brand, CardBrand.visa);
    });

    test('one-off misread does not win the vote', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3),
      );
      agg.add(frame(pan: visa));
      agg.add(frame(pan: visa2));
      agg.add(frame(pan: visa));
      agg.add(frame(pan: visa));
      expect(agg.current.number, visa);
    });

    test('frames with nothing recognized do not reset progress', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2),
      );
      agg.add(frame(pan: visa));
      agg.add(frame());
      agg.add(frame());
      agg.add(frame(pan: visa));
      expect(agg.current.number, visa);
    });

    test('old votes fall out of the window', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2, windowSize: 3),
      );
      agg.add(frame(pan: visa));
      agg.add(frame());
      agg.add(frame());
      agg.add(frame()); // first vote evicted
      agg.add(frame(pan: visa));
      expect(agg.current.number, isNull);
    });

    test('complete once number and expiry are stable (default)', () {
      final agg = FrameAggregator();
      for (var i = 0; i < 3; i++) {
        agg.add(frame(pan: visa, expiry: '12/28'));
      }
      final r = agg.current;
      expect(r.isComplete, isTrue);
      expect(r.formattedExpiry, '12/28');
      expect(r.cardholderName, isNull);
    });

    test('not complete without expiry when it is required', () {
      final agg = FrameAggregator();
      for (var i = 0; i < 5; i++) {
        agg.add(frame(pan: visa));
      }
      expect(agg.current.number, visa);
      expect(agg.current.isComplete, isFalse);
    });

    test('complete with number only when expiry is not required', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(requireExpiry: false),
      );
      for (var i = 0; i < 3; i++) {
        agg.add(frame(pan: visa));
      }
      expect(agg.current.isComplete, isTrue);
    });

    test('name required: waits for name', () {
      final agg = FrameAggregator(requirements: ScanRequirements.full);
      for (var i = 0; i < 5; i++) {
        agg.add(frame(pan: visa, expiry: '12/28'));
      }
      expect(agg.current.isComplete, isFalse);
      for (var i = 0; i < 3; i++) {
        agg.add(frame(pan: visa, expiry: '12/28', name: 'JOHN SMITH'));
      }
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.cardholderName, 'JOHN SMITH');
    });

    test('name required with timeout: completes without name eventually', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(
          requireName: true,
          nameTimeoutFrames: 4,
        ),
      );
      for (var i = 0; i < 3; i++) {
        agg.add(frame(pan: visa, expiry: '12/28'));
      }
      // Stable since frame 3; timeout counts frames while stable.
      expect(agg.current.isComplete, isFalse);
      agg.add(frame(pan: visa, expiry: '12/28'));
      agg.add(frame(pan: visa, expiry: '12/28'));
      agg.add(frame(pan: visa, expiry: '12/28'));
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.cardholderName, isNull);
    });

    test('fast preset accepts first frame', () {
      final agg = FrameAggregator(requirements: ScanRequirements.fast);
      final r = agg.add(frame(pan: visa, expiry: '12/28'));
      expect(r.isComplete, isTrue);
    });

    test('a stronger competing value replaces the chosen one', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2, windowSize: 12),
      );
      agg.add(frame(pan: visa2));
      agg.add(frame(pan: visa2));
      expect(agg.current.number, visa2);
      for (var i = 0; i < 3; i++) {
        agg.add(frame(pan: visa));
      }
      expect(agg.current.number, visa);
    });

    test('reset clears everything', () {
      final agg = FrameAggregator(requirements: ScanRequirements.fast);
      agg.add(frame(pan: visa, expiry: '12/28'));
      agg.reset();
      expect(agg.current, CardScanResult.empty);
      expect(agg.frameCount, 0);
    });
  });
}
