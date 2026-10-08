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

/// Frames arrive about eight times a second, so that is the step a test
/// takes unless it is deliberately simulating a stall.
const _interval = Duration(milliseconds: 125);

/// Feeds the same frame [times] over, one frame interval apart.
CardScanResult feed(
  FrameAggregator agg,
  FrameParseResult f, {
  int times = 1,
  Duration every = _interval,
}) {
  var result = agg.current;
  for (var i = 0; i < times; i++) {
    _clock = _clock.add(every);
    result = agg.add(f, at: _clock);
  }
  return result;
}

DateTime _clock = DateTime(2026, 1, 1);

void main() {
  setUp(() => _clock = DateTime(2026, 1, 1));

  const visa = '4111111111111111';
  const visa2 = '4012888888881881';

  group('voting', () {
    test('requires N agreeing frames before accepting a number', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3),
      );
      expect(feed(agg, frame(pan: visa)).number, isNull);
      expect(feed(agg, frame(pan: visa)).number, isNull);
      final r = feed(agg, frame(pan: visa));
      expect(r.number, visa);
      expect(r.brand, CardBrand.visa);
    });

    test('a one-off misread does not win the vote', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3),
      );
      feed(agg, frame(pan: visa));
      feed(agg, frame(pan: visa2));
      feed(agg, frame(pan: visa), times: 2);
      expect(agg.current.number, visa);
    });

    test('a value never confirmed falls out of the window', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2, windowSize: 3),
      );
      feed(agg, frame(pan: visa));
      feed(agg, frame(), times: 3); // the single vote is evicted
      feed(agg, frame(pan: visa));
      expect(agg.current.number, isNull);
    });

    test('confirming lists what is still gathering votes', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3, nameVotes: 3),
      );
      feed(agg, frame(pan: visa, name: 'ADA LOVELACE'));
      expect(agg.confirming, contains(CardField.number));
      expect(agg.confirming, contains(CardField.name));

      feed(agg, frame(pan: visa, name: 'ADA LOVELACE'), times: 2);
      expect(agg.confirming, isEmpty);
      expect(agg.current.number, visa);
    });
  });

  group('a confirmed field stays confirmed', () {
    test('blank frames cannot take it away', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2, nameVotes: 2),
      );
      feed(agg, frame(pan: visa, name: 'ADA LOVELACE'), times: 2);
      expect(agg.current.cardholderName, 'ADA LOVELACE');

      // Long enough to empty the window several times over, which is what
      // turning a card over looks like.
      feed(agg, frame(), times: 40);
      expect(agg.current.number, visa);
      expect(agg.current.cardholderName, 'ADA LOVELACE');
    });

    test('text that appears later cannot replace a confirmed name', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2, nameVotes: 2),
      );
      feed(agg, frame(pan: visa, name: 'ADA LOVELACE'), times: 2);
      feed(agg, frame(name: 'OPTION COMMAND'), times: 20);
      expect(agg.current.cardholderName, 'ADA LOVELACE');
    });

    test('an unconfirmed competing number overwrites nothing', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3, expiryVotes: 2),
      );
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 3);
      expect(agg.current.number, visa);

      // Two frames of another card is one short of confirming it.
      feed(agg, frame(pan: visa2, expiry: '01/30'), times: 2);
      expect(agg.current.number, visa);
      expect(agg.current.formattedExpiry, '12/28');
    });

    test('a different number, once confirmed, starts a new card', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 2, expiryVotes: 2),
      );
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 2);
      expect(agg.current.formattedExpiry, '12/28');

      // One more frame than the old card has votes: a tie leaves the card
      // already confirmed in place.
      feed(agg, frame(pan: visa2, expiry: '01/30'), times: 2);
      expect(agg.current.number, visa, reason: 'a tie changes nothing');

      feed(agg, frame(pan: visa2, expiry: '01/30'));
      expect(agg.current.number, visa2);
      expect(agg.current.hasExpiry, isFalse, reason: 'the old date is gone');

      feed(agg, frame(pan: visa2, expiry: '01/30'), times: 2);
      expect(agg.current.formattedExpiry, '01/30');
    });

    test('two numbers in view never pool their dates', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(panVotes: 3, expiryVotes: 2),
      );
      // Alternating cards: the date printed on the losing card must not be
      // attributed to the winner.
      for (var i = 0; i < 3; i++) {
        feed(agg, frame(pan: visa, expiry: '12/28'));
        feed(agg, frame(pan: visa2, expiry: '01/30'));
      }
      expect(agg.current.number, visa);
      expect(agg.current.formattedExpiry, '12/28');
    });
  });

  group('waiting for a preferred field', () {
    test('completes at once when the name arrives with the rest', () {
      final agg = FrameAggregator();
      feed(
        agg,
        frame(pan: visa, expiry: '12/28', name: 'ADA LOVELACE'),
        times: 3,
      );
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.cardholderName, 'ADA LOVELACE');
    });

    test('gives up on the name after the timeout', () {
      final agg = FrameAggregator();
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 3);
      expect(agg.current.isComplete, isFalse);

      // 1.5 s of frames at eight a second.
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 12);
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.cardholderName, isNull);
    });

    test('the clock only runs while frames arrive', () {
      final agg = FrameAggregator();
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 3);

      // The app spent a minute in the background. One frame on return must
      // not carry the whole minute with it.
      feed(
        agg,
        frame(pan: visa, expiry: '12/28'),
        every: const Duration(minutes: 1),
      );
      expect(agg.current.isComplete, isFalse);
    });

    test('the timer does not start until the required fields are in', () {
      final agg = FrameAggregator();
      feed(agg, frame(pan: visa), times: 40); // no expiry
      expect(agg.current.isComplete, isFalse);

      feed(agg, frame(pan: visa, expiry: '12/28'), times: 2);
      expect(agg.current.isComplete, isFalse);
    });

    test('a name mid-confirmation is granted the grace period', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(
          preferredTimeout: Duration(milliseconds: 500),
          preferredGrace: Duration(seconds: 2),
          nameVotes: 3,
        ),
      );
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 3);
      // Past the timeout, but a name has one vote, so it is still worth
      // waiting for.
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 4);
      feed(agg, frame(pan: visa, expiry: '12/28', name: 'ADA LOVELACE'));
      expect(agg.current.isComplete, isFalse);

      feed(
        agg,
        frame(pan: visa, expiry: '12/28', name: 'ADA LOVELACE'),
        times: 2,
      );
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.cardholderName, 'ADA LOVELACE');
    });

    test('twoSided waits long enough to turn a card over', () {
      final agg = FrameAggregator(requirements: ScanRequirements.twoSided);
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 3);

      // Ten seconds of blank frames, the card being turned over.
      feed(agg, frame(), times: 80);
      expect(agg.current.isComplete, isFalse);

      feed(agg, frame(name: 'ADA LOVELACE'), times: 3);
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.number, visa);
      expect(agg.current.cardholderName, 'ADA LOVELACE');
    });
  });

  group('requirements', () {
    test('not complete without an expiry when it is required', () {
      final agg = FrameAggregator();
      feed(agg, frame(pan: visa), times: 5);
      expect(agg.current.number, visa);
      expect(agg.current.isComplete, isFalse);
    });

    test('numberOnly completes with just the number', () {
      final agg = FrameAggregator(requirements: ScanRequirements.numberOnly);
      feed(agg, frame(pan: visa), times: 3);
      expect(agg.current.isComplete, isTrue);
    });

    test('number is always required even if omitted from the set', () {
      const r = ScanRequirements(required: {}, preferred: {});
      expect(r.isRequired(CardField.number), isTrue);
      expect(r.isRequired(CardField.expiry), isFalse);
      expect(r.isPreferred(CardField.expiry), isFalse);
    });

    test('a field in both sets is treated as required', () {
      const r = ScanRequirements(
        required: {CardField.expiry},
        preferred: {CardField.expiry},
      );
      expect(r.isRequired(CardField.expiry), isTrue);
      expect(r.isPreferred(CardField.expiry), isFalse);
    });

    test('full waits for the name however long it takes', () {
      final agg = FrameAggregator(requirements: ScanRequirements.full);
      feed(agg, frame(pan: visa, expiry: '12/28'), times: 40);
      expect(agg.current.isComplete, isFalse);

      feed(
        agg,
        frame(pan: visa, expiry: '12/28', name: 'ADA LOVELACE'),
        times: 3,
      );
      expect(agg.current.isComplete, isTrue);
    });

    test('the expiry can be preferred instead of required', () {
      final agg = FrameAggregator(
        requirements: const ScanRequirements(
          required: {CardField.number},
          preferred: {CardField.expiry},
          preferredTimeout: Duration(milliseconds: 250),
        ),
      );
      feed(agg, frame(pan: visa), times: 3);
      expect(agg.current.isComplete, isFalse);
      feed(agg, frame(pan: visa), times: 2);
      expect(agg.current.isComplete, isTrue);
      expect(agg.current.hasExpiry, isFalse);
    });

    test('fast accepts the first frame', () {
      final agg = FrameAggregator(requirements: ScanRequirements.fast);
      expect(feed(agg, frame(pan: visa, expiry: '12/28')).isComplete, isTrue);
    });

    test('reset clears everything', () {
      final agg = FrameAggregator(requirements: ScanRequirements.fast);
      feed(agg, frame(pan: visa, expiry: '12/28'));
      agg.reset();
      expect(agg.current, CardScanResult.empty);
      expect(agg.frameCount, 0);
      expect(agg.confirming, isEmpty);
    });
  });
}
