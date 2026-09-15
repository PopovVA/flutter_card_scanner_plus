import 'package:meta/meta.dart';

import 'card_brand.dart';
import 'luhn.dart';
import 'ocr_normalizer.dart';
import 'recognized_text.dart';

/// A primary account number found in OCR output.
@immutable
class PanCandidate {
  const PanCandidate({
    required this.number,
    required this.brand,
    required this.box,
    required this.confidence,
  });

  /// Digits only, e.g. `4111111111111111`.
  final String number;
  final CardBrand brand;

  /// Location of the text this number was extracted from.
  final TextBox box;

  /// `0..1`, combines engine confidence with how much OCR repair was needed.
  final double confidence;

  @override
  String toString() =>
      'PanCandidate(${brand.name}, ****${number.substring(number.length - 4)}, '
      'c=${confidence.toStringAsFixed(2)})';
}

/// Extracts card numbers from OCR text lines.
///
/// A candidate must pass the Luhn check, belong to a supported [CardBrand]
/// and have a length valid for that brand.
abstract final class PanParser {
  /// Lengths to try when scanning a longer digit run for an embedded PAN.
  static const _windowLengths = [16, 15, 19];

  /// Confidence penalty applied per repaired (letter → digit) character.
  static const _repairPenalty = 0.08;

  /// Minimum share of real digits a token must have to be treated as part
  /// of a number. Protects words like "SOLO" from becoming "5010".
  static const _minTokenDigitRatio = 0.5;

  /// Returns the best PAN found in [text], or `null`.
  static PanCandidate? parse(
    String text, {
    TextBox box = TextBox.zero,
    double confidence = 1.0,
  }) {
    PanCandidate? best;
    for (final run in _numericRuns(text)) {
      final candidate = _evaluateRun(run, box, confidence);
      if (candidate == null) continue;
      if (best == null || candidate.confidence > best.confidence) {
        best = candidate;
      }
    }
    return best;
  }

  /// Convenience: parse a [TextLine].
  static PanCandidate? parseLine(TextLine line) =>
      parse(line.text, box: line.box, confidence: line.confidence);

  /// Splits [text] into runs of adjacent numeric-looking tokens.
  static List<_Run> _numericRuns(String text) {
    final runs = <_Run>[];
    _Run? current;

    for (final token in text.split(RegExp(r'\s+'))) {
      final cleaned = token.replaceAll(RegExp(r'[-–—._]'), '');
      if (_isNumericToken(cleaned)) {
        final repaired = OcrNormalizer.repairDigits(cleaned);
        final repairs = _countRepairs(cleaned, repaired);
        current = (current ?? _Run.empty()).append(repaired, repairs);
      } else if (current != null) {
        runs.add(current);
        current = null;
      }
    }
    if (current != null) runs.add(current);
    return runs;
  }

  static bool _isNumericToken(String token) {
    if (token.isEmpty) return false;
    if (!RegExp('^${OcrNormalizer.numericToken.pattern}\$').hasMatch(token)) {
      return false;
    }
    return OcrNormalizer.digitRatio(token) >= _minTokenDigitRatio;
  }

  static int _countRepairs(String before, String after) {
    var count = 0;
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) count++;
    }
    return count;
  }

  static PanCandidate? _evaluateRun(
    _Run run,
    TextBox box,
    double lineConfidence,
  ) {
    final digits = run.digits;
    if (digits.length < 15) return null;

    final baseConfidence = (lineConfidence * (1 - run.repairs * _repairPenalty))
        .clamp(0.0, 1.0);

    // Whole run is a valid PAN — strongest signal.
    final brand = _validate(digits);
    if (brand != null) {
      return PanCandidate(
        number: digits,
        brand: brand,
        box: box,
        confidence: baseConfidence,
      );
    }

    // Otherwise look for a PAN embedded in a longer run (OCR glued
    // neighbouring text onto the number). Slightly lower confidence.
    for (final length in _windowLengths) {
      if (digits.length <= length) continue;
      for (var start = 0; start + length <= digits.length; start++) {
        final window = digits.substring(start, start + length);
        final windowBrand = _validate(window);
        if (windowBrand != null) {
          return PanCandidate(
            number: window,
            brand: windowBrand,
            box: box,
            confidence: (baseConfidence * 0.8).clamp(0.0, 1.0),
          );
        }
      }
    }
    return null;
  }

  /// Returns the brand if [digits] is a complete, valid PAN.
  static CardBrand? _validate(String digits) {
    if (!OcrNormalizer.isAllDigits(digits)) return null;
    final brand = CardBrand.detect(digits);
    if (brand == null || !brand.matchesLength(digits.length)) return null;
    if (!Luhn.isValid(digits)) return null;
    return brand;
  }
}

class _Run {
  const _Run(this.digits, this.repairs);

  factory _Run.empty() => const _Run('', 0);

  final String digits;
  final int repairs;

  _Run append(String more, int moreRepairs) =>
      _Run(digits + more, repairs + moreRepairs);
}
