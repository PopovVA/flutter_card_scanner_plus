import 'package:meta/meta.dart';

import 'recognized_text.dart';

/// A cardholder name found in OCR output.
@immutable
class NameCandidate {
  const NameCandidate({
    required this.name,
    required this.box,
    required this.confidence,
    this.score = 0,
  });

  /// Upper-case name as printed, e.g. `JOHN A SMITH`.
  final String name;
  final TextBox box;
  final double confidence;

  /// Heuristic ranking score; higher is more likely to be the holder name.
  final int score;

  NameCandidate withScore(int value) =>
      NameCandidate(name: name, box: box, confidence: confidence, score: value);

  @override
  bool operator ==(Object other) =>
      other is NameCandidate && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'NameCandidate("$name", score=$score)';
}

/// Extracts the cardholder name from OCR text lines.
///
/// There is no structural marker for the name on a card, so this relies on
/// heuristics: an upper-case Latin line of 2–4 words, no digits, not a
/// known label/brand word, ideally located below the card number.
abstract final class NameParser {
  /// Words that appear on cards but are never part of a holder name.
  static const Set<String> stopWords = {
    // Field labels
    'VALID', 'THRU', 'FROM', 'GOOD', 'EXPIRES', 'EXPIRY', 'EXP', 'END',
    'MONTH', 'YEAR', 'DATE', 'MEMBER', 'SINCE', 'AUTHORIZED', 'SIGNATURE',
    'CARDHOLDER', 'ACCOUNT', 'NUMBER',
    // Card types / tiers
    'DEBIT', 'CREDIT', 'PREPAID', 'GIFT', 'BUSINESS', 'CORPORATE',
    'PLATINUM', 'GOLD', 'SILVER', 'TITANIUM', 'BLACK', 'WORLD', 'ELITE',
    'INFINITE', 'CLASSIC', 'STANDARD', 'PREMIER', 'PREFERRED',
    'REWARDS', 'CASH', 'BACK', 'CENTURION', 'SAPPHIRE', 'FREEDOM',
    'UNLIMITED', 'EVERYDAY', 'BLUE', 'GREEN', 'SELECT', 'PLUS', 'PRO',
    // Networks
    'VISA', 'MASTERCARD', 'MASTER', 'CARD', 'AMERICAN', 'EXPRESS', 'AMEX',
    'ELECTRON', 'MAESTRO', 'CIRRUS', 'DISCOVER', 'DINERS', 'CLUB', 'JCB',
    'UNIONPAY',
    // Common issuers
    'BANK', 'CHASE', 'CITI', 'CITIBANK', 'CAPITAL', 'ONE', 'WELLS', 'FARGO',
    'BARCLAYS', 'HSBC', 'SANTANDER', 'MONZO', 'REVOLUT', 'WISE', 'N26',
    'APPLE', 'GOLDMAN', 'SACHS', 'AMERICA', 'NATIONAL', 'FEDERAL', 'UNION',
    'SAVINGS', 'TRUST', 'FINANCIAL', 'SERVICES',
    // Misc printed text
    'CONTACTLESS', 'INTERNATIONAL', 'SECURE', 'CHIP', 'PIN', 'ONLINE',
    'CUSTOMER', 'SERVICE', 'CALL', 'LOST', 'STOLEN', 'PROPERTY', 'ISSUED',
    'NOT', 'TRANSFERABLE', 'SEE', 'REVERSE', 'SIDE', 'USE', 'SUBJECT',
    'TERMS', 'CONDITIONS', 'WWW', 'COM', 'HTTP', 'HTTPS',
  };

  static final RegExp _linePattern = RegExp(
    r"^[A-Z][A-Z'\-\.]*(?: [A-Z][A-Z'\-\.]*){1,3}$",
  );

  /// Returns `true` if [text] looks like a printed cardholder name.
  static bool looksLikeName(String text) {
    final normalized = _normalize(text);
    if (!_linePattern.hasMatch(normalized)) return false;

    final words = normalized.split(' ');
    var realWords = 0;
    for (final word in words) {
      final bare = word.replaceAll(RegExp(r"[.'\-]"), '');
      if (bare.isEmpty) return false;
      if (stopWords.contains(bare)) return false;
      if (bare.length > 1) realWords++;
    }
    // Initials ("J.", "C F") are fine, but at least one full word is needed.
    return realWords >= 1;
  }

  /// Ranks all name-like [lines] and returns the best candidate.
  ///
  /// [panBox] and [expiryBox], when known, boost lines positioned below
  /// them — the holder name is printed at the bottom of the card.
  static NameCandidate? parse(
    List<TextLine> lines, {
    TextBox? panBox,
    TextBox? expiryBox,
  }) {
    NameCandidate? best;
    for (final line in lines) {
      if (!looksLikeName(line.text)) continue;

      var score = 0;
      if (panBox != null) {
        if (line.box.top >= panBox.bottom) {
          score += 3;
        } else if (line.box.top < panBox.top) {
          // Above the number: almost certainly the bank name.
          score -= 3;
        }
      }
      if (expiryBox != null && line.box.top >= expiryBox.top) score += 1;

      final wordCount = _normalize(line.text).split(' ').length;
      if (wordCount == 2 || wordCount == 3) score += 1;

      final candidate = NameCandidate(
        name: _normalize(line.text),
        box: line.box,
        confidence: line.confidence,
        score: score,
      );

      if (best == null ||
          candidate.score > best.score ||
          (candidate.score == best.score && candidate.box.top > best.box.top)) {
        best = candidate;
      }
    }
    return best;
  }

  static String _normalize(String text) =>
      text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}
