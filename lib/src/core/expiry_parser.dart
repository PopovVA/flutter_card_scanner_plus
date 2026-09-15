import 'package:meta/meta.dart';

import 'ocr_normalizer.dart';
import 'recognized_text.dart';

/// An expiry date found in OCR output.
@immutable
class ExpiryCandidate implements Comparable<ExpiryCandidate> {
  const ExpiryCandidate({
    required this.month,
    required this.year,
    required this.box,
    required this.confidence,
  });

  /// `1..12`.
  final int month;

  /// Four-digit year.
  final int year;
  final TextBox box;
  final double confidence;

  /// `MM/YY` as printed on the card.
  String get formatted =>
      '${month.toString().padLeft(2, '0')}/${(year % 100).toString().padLeft(2, '0')}';

  /// Chronological order: earlier dates first.
  @override
  int compareTo(ExpiryCandidate other) => year != other.year
      ? year.compareTo(other.year)
      : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is ExpiryCandidate && other.month == month && other.year == year;

  @override
  int get hashCode => Object.hash(month, year);

  @override
  String toString() =>
      'ExpiryCandidate($formatted, c=${confidence.toStringAsFixed(2)})';
}

/// Extracts `MM/YY` and `MM/YYYY` dates from OCR text.
abstract final class ExpiryParser {
  /// Years further in the past than this are rejected outright.
  static const _maxYearsInPast = 15;

  /// Years further in the future than this are rejected outright.
  static const _maxYearsInFuture = 25;

  static final RegExp _pattern = RegExp(
    '(?<![0-9])'
    '([0-9OIlSBZG]{2})'
    r'\s*[/\-.]\s*'
    '([0-9OIlSBZG]{2}(?:[0-9OIlSBZG]{2})?)'
    '(?![0-9])',
  );

  /// Returns every plausible date in [text], in order of appearance.
  static List<ExpiryCandidate> parseAll(
    String text, {
    TextBox box = TextBox.zero,
    double confidence = 1.0,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final results = <ExpiryCandidate>[];

    for (final match in _pattern.allMatches(text)) {
      final rawMonth = match.group(1)!;
      final rawYear = match.group(2)!;

      final monthStr = OcrNormalizer.repairDigits(rawMonth);
      final yearStr = OcrNormalizer.repairDigits(rawYear);
      final month = int.tryParse(monthStr);
      var year = int.tryParse(yearStr);
      if (month == null || year == null) continue;
      if (month < 1 || month > 12) continue;

      if (yearStr.length == 2) year += 2000;
      if (year < today.year - _maxYearsInPast) continue;
      if (year > today.year + _maxYearsInFuture) continue;

      final repairs = _repairs(rawMonth, monthStr) + _repairs(rawYear, yearStr);
      results.add(
        ExpiryCandidate(
          month: month,
          year: year,
          box: box,
          confidence: (confidence * (1 - repairs * 0.1)).clamp(0.0, 1.0),
        ),
      );
    }
    return results;
  }

  /// Returns the latest date in [text], or `null`.
  ///
  /// Cards often print both a "valid from" and a "valid thru" date; the
  /// expiry is always the later one.
  static ExpiryCandidate? parse(
    String text, {
    TextBox box = TextBox.zero,
    double confidence = 1.0,
    DateTime? now,
  }) {
    final all = parseAll(text, box: box, confidence: confidence, now: now);
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
  }

  static int _repairs(String before, String after) {
    var count = 0;
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) count++;
    }
    return count;
  }
}
