import 'dart:collection';

import 'package:meta/meta.dart';

import 'card_brand.dart';
import 'card_frame_parser.dart';
import 'card_scan_result.dart';

/// A field the scanner can extract from a card.
enum CardField { number, expiry, name }

/// Controls which fields are needed and when a scan is considered complete.
///
/// * [required] — the result is not complete until each of these has been
///   confirmed. [CardField.number] is always required.
/// * [preferred] — once the required fields are confirmed, wait up to
///   [preferredTimeout] for these, then complete without them. Use this for
///   fields that are nice to have but unreliable, such as the cardholder
///   name.
/// * Any other field is still filled in if it happens to be recognized,
///   but never delays completion.
@immutable
class ScanRequirements {
  const ScanRequirements({
    this.required = const {CardField.number, CardField.expiry},
    this.preferred = const {CardField.name},
    this.preferredTimeout = const Duration(milliseconds: 1500),
    this.preferredGrace = const Duration(seconds: 5),
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

  /// Fields that must be confirmed before the scan completes.
  final Set<CardField> required;

  /// Fields to wait for after [required] are confirmed.
  final Set<CardField> preferred;

  /// How long to keep waiting for [preferred] fields once every required
  /// field is confirmed.
  ///
  /// Measured from the frames themselves, not the wall clock: a gap longer
  /// than one frame interval counts as one interval, so a scan paused in the
  /// background does not time out while nothing is being recognized.
  final Duration preferredTimeout;

  /// Extra time granted when a preferred field has votes but not yet
  /// enough of them. Without it a name arriving on the last frame before
  /// the timeout is thrown away.
  final Duration preferredGrace;

  /// How many frames must agree on a value before it is accepted.
  final int panVotes;
  final int expiryVotes;
  final int nameVotes;

  /// Number of most recent frames considered when counting votes. A field
  /// already confirmed is kept whatever leaves the window.
  final int windowSize;

  /// Number and expiry required, name if it shows up quickly (default).
  static const standard = ScanRequirements();

  /// Only the number; finish as soon as it is confirmed.
  static const numberOnly = ScanRequirements(
    required: {CardField.number},
    preferred: {},
  );

  /// Number, expiry and name — wait for all three.
  static const full = ScanRequirements(
    required: {CardField.number, CardField.expiry, CardField.name},
    preferred: {},
  );

  /// Accept the first Luhn-valid number and expiry immediately, don't wait
  /// for the name — fastest, least safe.
  static const fast = ScanRequirements(
    preferred: {},
    panVotes: 1,
    expiryVotes: 1,
    nameVotes: 1,
  );

  /// For cards that print the name on the other side: long enough for the
  /// holder to notice the prompt, turn the card over and hold it still.
  static const twoSided = ScanRequirements(
    preferredTimeout: Duration(seconds: 15),
  );

  bool isRequired(CardField field) =>
      field == CardField.number || required.contains(field);

  bool isPreferred(CardField field) =>
      !isRequired(field) && preferred.contains(field);

  /// Whether a result holding [found] is complete after [waited] with every
  /// required field confirmed. Fields in [confirming] have votes but not
  /// yet enough, and are granted [preferredGrace] beyond the timeout.
  bool isSatisfied(
    Set<CardField> found,
    Duration waited, {
    Set<CardField> confirming = const {},
  }) {
    for (final field in CardField.values) {
      if (found.contains(field)) continue;
      if (isRequired(field)) return false;
      if (!isPreferred(field)) continue;
      final limit = confirming.contains(field)
          ? preferredTimeout + preferredGrace
          : preferredTimeout;
      if (waited < limit) return false;
    }
    return true;
  }

  /// Whether every required field is in [found].
  bool requiredSatisfied(Set<CardField> found) =>
      CardField.values.every((f) => !isRequired(f) || found.contains(f));

  ScanRequirements copyWith({
    Set<CardField>? required,
    Set<CardField>? preferred,
    Duration? preferredTimeout,
    Duration? preferredGrace,
    int? panVotes,
    int? expiryVotes,
    int? nameVotes,
    int? windowSize,
  }) => ScanRequirements(
    required: required ?? this.required,
    preferred: preferred ?? this.preferred,
    preferredTimeout: preferredTimeout ?? this.preferredTimeout,
    preferredGrace: preferredGrace ?? this.preferredGrace,
    panVotes: panVotes ?? this.panVotes,
    expiryVotes: expiryVotes ?? this.expiryVotes,
    nameVotes: nameVotes ?? this.nameVotes,
    windowSize: windowSize ?? this.windowSize,
  );
}

/// Turns a stream of parsed frames into one result.
///
/// Implement this to change the scan rules without touching the camera
/// pipeline, and pass the implementation to `CardScannerController`.
abstract interface class ScanSession {
  /// Latest result.
  CardScanResult get current;

  /// Fields that have a candidate but not yet enough votes to be accepted.
  /// A UI can use this to say it is still working rather than stuck.
  Set<CardField> get confirming;

  /// Feeds one frame and returns the updated result. [at] is when the frame
  /// was recognized, and defaults to now.
  CardScanResult add(FrameParseResult frame, {DateTime? at});

  /// Forgets everything, ready for the next card.
  void reset();
}

/// Accumulates per-frame parse results and emits a [CardScanResult] once
/// values have been confirmed across several frames.
///
/// OCR output flickers: a digit may be misread in one frame and correct in
/// the next. Requiring agreement over multiple frames filters out those
/// glitches without needing a perfect single frame.
///
/// A confirmed field is then kept. Frames that show nothing, which is every
/// frame while a card is being turned over, cannot take it away, and only a
/// different number confirmed in its own right starts a new card. That is
/// what lets a card with the name on the back be read in two passes.
class FrameAggregator implements ScanSession {
  FrameAggregator({this.requirements = ScanRequirements.standard})
    : _panVotes = _Votes<String>(requirements.windowSize),
      _expiryVotes = _Votes<String>(requirements.windowSize),
      _nameVotes = _Votes<String>(requirements.windowSize);

  final ScanRequirements requirements;

  /// A gap longer than this means frames stopped arriving rather than that
  /// time passed while scanning, so only this much of it is counted.
  static const _maxFrameGap = Duration(milliseconds: 500);

  final _Votes<String> _panVotes;
  final _Votes<String> _expiryVotes;
  final _Votes<String> _nameVotes;

  String? _pan;
  String? _expiry;
  String? _name;

  Duration _waited = Duration.zero;
  DateTime? _lastFrame;
  CardScanResult _current = CardScanResult.empty;

  @override
  CardScanResult get current => _current;

  /// Number of frames processed since the last [reset].
  int get frameCount => _frameCount;
  int _frameCount = 0;

  @override
  Set<CardField> get confirming => {
    if (_pan == null && _panVotes.isBuilding(requirements.panVotes, _pan))
      CardField.number,
    if (_expiry == null &&
        _expiryVotes.isBuilding(requirements.expiryVotes, _pan))
      CardField.expiry,
    if (_name == null && _nameVotes.isBuilding(requirements.nameVotes, _pan))
      CardField.name,
  };

  @override
  CardScanResult add(FrameParseResult frame, {DateTime? at}) {
    final now = at ?? DateTime.now();
    _frameCount++;

    final framePan = frame.pan?.number;

    // A number other than the confirmed one means either a misread or a
    // second card in view. Its fields are kept apart until the number
    // itself is confirmed, at which point it is a new card.
    final foreign = _pan != null && framePan != null && framePan != _pan;
    _panVotes.add(framePan, framePan);

    if (foreign) {
      // Taking over needs both enough votes of its own and more of them
      // than the number already confirmed. Two cards in view would
      // otherwise swap the result back and forth every frame.
      final challenger = _panVotes.count(framePan, framePan);
      if (challenger >= requirements.panVotes &&
          challenger > _panVotes.count(_pan, _pan)) {
        reset();
        _pan = framePan;
        _panVotes.add(framePan, framePan);
        return _emit(now);
      }
    }

    if (!foreign) {
      _expiryVotes.add(
        frame.expiry == null
            ? null
            : '${frame.expiry!.month}/${frame.expiry!.year}',
        framePan,
      );
      _nameVotes.add(frame.name?.name, framePan);
    }

    _pan ??= _panVotes.stable(requirements.panVotes, null);
    _expiry ??= _expiryVotes.stable(requirements.expiryVotes, _pan);
    _name ??= _nameVotes.stable(requirements.nameVotes, _pan);

    return _emit(now);
  }

  CardScanResult _emit(DateTime now) {
    final found = {
      if (_pan != null) CardField.number,
      if (_expiry != null) CardField.expiry,
      if (_name != null) CardField.name,
    };

    if (requirements.requiredSatisfied(found)) {
      final last = _lastFrame;
      if (last != null) {
        final gap = now.difference(last);
        _waited += gap > _maxFrameGap ? _maxFrameGap : gap;
      }
    } else {
      _waited = Duration.zero;
    }
    _lastFrame = now;

    int? month;
    int? year;
    final expiry = _expiry;
    if (expiry != null) {
      final parts = expiry.split('/');
      month = int.parse(parts[0]);
      year = int.parse(parts[1]);
    }

    return _current = CardScanResult(
      number: _pan,
      brand: _pan == null ? null : CardBrand.detect(_pan!),
      expiryMonth: month,
      expiryYear: year,
      cardholderName: _name,
      isComplete: requirements.isSatisfied(
        found,
        _waited,
        confirming: confirming,
      ),
    );
  }

  @override
  void reset() {
    _panVotes.clear();
    _expiryVotes.clear();
    _nameVotes.clear();
    _pan = null;
    _expiry = null;
    _name = null;
    _waited = Duration.zero;
    _lastFrame = null;
    _frameCount = 0;
    _current = CardScanResult.empty;
  }
}

/// Sliding-window vote count where every vote remembers the card number
/// visible in the same frame.
///
/// Filtering by that tag is what stops a second card in view, or a misread
/// number, from lending its expiry date and name to the card being scanned.
class _Votes<T> {
  _Votes(this.windowSize);

  final int windowSize;
  final Queue<_Vote<T>> _window = Queue();

  void add(T? value, String? card) {
    _window.addLast(_Vote(value, card));
    if (_window.length > windowSize) _window.removeFirst();
  }

  /// Votes for [value] that could belong to the card numbered [card].
  /// A vote from a frame with no number in it belongs to whatever card is
  /// being scanned, so it always counts.
  int count(T? value, String? card) {
    if (value == null) return 0;
    var total = 0;
    for (final vote in _window) {
      if (vote.value != value) continue;
      if (card != null && vote.card != null && vote.card != card) continue;
      total++;
    }
    return total;
  }

  /// The value with the most votes, if it has at least [minVotes].
  T? stable(int minVotes, String? card) {
    T? best;
    var bestCount = 0;
    for (final vote in _window) {
      final value = vote.value;
      if (value == null) continue;
      final votes = count(value, card);
      if (votes > bestCount) {
        best = value;
        bestCount = votes;
      }
    }
    return bestCount >= minVotes ? best : null;
  }

  /// Whether some value is gathering votes but has not reached [minVotes].
  bool isBuilding(int minVotes, String? card) {
    for (final vote in _window) {
      final value = vote.value;
      if (value == null) continue;
      final votes = count(value, card);
      if (votes > 0 && votes < minVotes) return true;
    }
    return false;
  }

  void clear() => _window.clear();
}

class _Vote<T> {
  const _Vote(this.value, this.card);

  final T? value;
  final String? card;
}
