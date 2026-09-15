import 'dart:collection';

import 'package:meta/meta.dart';

import 'card_brand.dart';
import 'card_frame_parser.dart';
import 'card_scan_result.dart';

/// Controls when a scan is considered complete.
@immutable
class ScanRequirements {
  const ScanRequirements({
    this.requireExpiry = true,
    this.requireName = false,
    this.nameTimeoutFrames = 20,
    this.panVotes = 3,
    this.expiryVotes = 2,
    this.nameVotes = 3,
    this.windowSize = 12,
  }) : assert(panVotes > 0),
       assert(expiryVotes > 0),
       assert(nameVotes > 0),
       assert(
         windowSize >= panVotes &&
             windowSize >= expiryVotes &&
             windowSize >= nameVotes,
       );

  /// Wait for an expiry date before completing.
  final bool requireExpiry;

  /// Wait for a cardholder name before completing.
  final bool requireName;

  /// When [requireName] is set: give up on the name and complete anyway
  /// after this many frames with a stable number (and expiry, if
  /// required). `null` waits indefinitely.
  final int? nameTimeoutFrames;

  /// How many frames must agree on a value before it is accepted.
  final int panVotes;
  final int expiryVotes;
  final int nameVotes;

  /// Number of most recent frames considered when counting votes.
  final int windowSize;

  /// Accept the first Luhn-valid number immediately — fastest, least safe.
  static const fast = ScanRequirements(
    panVotes: 1,
    expiryVotes: 1,
    nameVotes: 2,
  );

  /// Number and expiry only (default).
  static const standard = ScanRequirements();

  /// Number, expiry and name, waiting for all three.
  static const full = ScanRequirements(
    requireName: true,
    nameTimeoutFrames: null,
  );
}

/// Accumulates per-frame parse results and emits a [CardScanResult] once
/// values have been confirmed across several frames.
///
/// OCR output flickers: a digit may be misread in one frame and correct in
/// the next. Requiring agreement over multiple frames filters out those
/// glitches without needing a perfect single frame.
class FrameAggregator {
  FrameAggregator({this.requirements = ScanRequirements.standard})
    : _pan = _VoteCounter<String>(requirements.windowSize),
      _expiry = _VoteCounter<String>(requirements.windowSize),
      _name = _VoteCounter<String>(requirements.windowSize);

  final ScanRequirements requirements;

  final _VoteCounter<String> _pan;
  final _VoteCounter<String> _expiry;
  final _VoteCounter<String> _name;

  int _framesSinceRequiredStable = 0;
  CardScanResult _current = CardScanResult.empty;

  /// Latest aggregated result.
  CardScanResult get current => _current;

  /// Number of frames processed since the last [reset].
  int get frameCount => _frameCount;
  int _frameCount = 0;

  /// Feeds one frame and returns the updated result.
  CardScanResult add(FrameParseResult frame) {
    _frameCount++;

    _pan.add(frame.pan?.number);
    _expiry.add(
      frame.expiry == null
          ? null
          : '${frame.expiry!.month}/${frame.expiry!.year}',
    );
    _name.add(frame.name?.name);

    final pan = _pan.stable(requirements.panVotes);
    final expiry = _expiry.stable(requirements.expiryVotes);
    final name = _name.stable(requirements.nameVotes);

    final requiredStable =
        pan != null && (!requirements.requireExpiry || expiry != null);
    _framesSinceRequiredStable = requiredStable
        ? _framesSinceRequiredStable + 1
        : 0;

    final nameSatisfied =
        !requirements.requireName ||
        name != null ||
        (requirements.nameTimeoutFrames != null &&
            _framesSinceRequiredStable >= requirements.nameTimeoutFrames!);

    int? month;
    int? year;
    if (expiry != null) {
      final parts = expiry.split('/');
      month = int.parse(parts[0]);
      year = int.parse(parts[1]);
    }

    _current = CardScanResult(
      number: pan,
      brand: pan == null ? null : CardBrand.detect(pan),
      expiryMonth: month,
      expiryYear: year,
      cardholderName: name,
      isComplete: requiredStable && nameSatisfied,
    );
    return _current;
  }

  /// Clears all accumulated votes.
  void reset() {
    _pan.clear();
    _expiry.clear();
    _name.clear();
    _framesSinceRequiredStable = 0;
    _frameCount = 0;
    _current = CardScanResult.empty;
  }
}

/// Sliding-window majority vote with hysteresis: once a value is chosen it
/// is kept until another value has strictly more votes.
class _VoteCounter<T> {
  _VoteCounter(this.windowSize);

  final int windowSize;
  final Queue<T?> _window = Queue();
  final Map<T, int> _counts = {};
  T? _chosen;

  void add(T? value) {
    _window.addLast(value);
    if (value != null) _counts[value] = (_counts[value] ?? 0) + 1;

    if (_window.length > windowSize) {
      final evicted = _window.removeFirst();
      if (evicted != null) {
        final n = (_counts[evicted] ?? 1) - 1;
        if (n <= 0) {
          _counts.remove(evicted);
        } else {
          _counts[evicted] = n;
        }
      }
    }
  }

  T? stable(int minVotes) {
    T? best;
    var bestCount = 0;
    for (final entry in _counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    if (best == null || bestCount < minVotes) {
      // Keep a previously chosen value only while it still has support.
      if (_chosen != null && (_counts[_chosen] ?? 0) >= minVotes) {
        return _chosen;
      }
      _chosen = null;
      return null;
    }

    final chosenCount = _chosen == null ? 0 : (_counts[_chosen] ?? 0);
    if (_chosen == null || bestCount > chosenCount) _chosen = best;
    return _chosen;
  }

  void clear() {
    _window.clear();
    _counts.clear();
    _chosen = null;
  }
}
