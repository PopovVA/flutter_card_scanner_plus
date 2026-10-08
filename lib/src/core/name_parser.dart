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
/// heuristics: an upper-case Latin line of 2-4 words, no digits, no known
/// label or brand word, positioned like the name block relative to the
/// number.
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
    // Material and sustainability claims, printed in the same block as the
    // name on recent cards
    'RECYCLED', 'RECYCLABLE', 'RECOVERED', 'PLASTIC', 'MADE', 'WITH',
    'OCEAN', 'BOUND', 'ECO',
    // Misc printed text
    'CONTACTLESS', 'INTERNATIONAL', 'SECURE', 'CHIP', 'PIN', 'ONLINE',
    'CUSTOMER', 'SERVICE', 'CALL', 'LOST', 'STOLEN', 'PROPERTY', 'ISSUED',
    'NOT', 'TRANSFERABLE', 'SEE', 'REVERSE', 'SIDE', 'USE', 'SUBJECT',
    'TERMS', 'CONDITIONS', 'WWW', 'COM', 'HTTP', 'HTTPS',
  };

  static final RegExp _linePattern = RegExp(
    r"^[A-Z][A-Z'\-\.]*(?: [A-Z][A-Z'\-\.]*){1,3}$",
  );

  static final RegExp _wordPattern = RegExp(r"^[A-Z][A-Z'\-\.]*$");

  /// Returns `true` if [text] looks like a printed cardholder name.
  static bool looksLikeName(String text) {
    final normalized = _normalize(text);
    if (!_linePattern.hasMatch(normalized)) return false;

    final words = normalized.split(' ');
    var realWords = 0;
    for (final word in words) {
      final bare = _bare(word);
      if (bare.isEmpty) return false;
      if (stopWords.contains(bare)) return false;
      if (bare.length > 1) realWords++;
    }
    // Initials ("J.", "C F") are fine, but at least one full word is needed.
    return realWords >= 1;
  }

  /// Ranks all name-like [lines] and returns the best candidate.
  ///
  /// Each line is considered on its own. Use [parseRows] when the lines
  /// have been grouped into visual rows, which is what OCR output needs:
  /// engines routinely return a printed name as one box per word.
  static NameCandidate? parse(
    List<TextLine> lines, {
    TextBox? panBox,
    TextBox? expiryBox,
  }) => parseRows(
    lines.map((line) => [line]).toList(growable: false),
    panBox: panBox,
    expiryBox: expiryBox,
  );

  /// Ranks the rows produced by `CardFrameParser.groupRowParts` and returns
  /// the best candidate.
  ///
  /// Within a row, leading and trailing words that cannot belong to a name
  /// are dropped before the rest is tested, so "ADA LOVELACE" still reads
  /// as a name when the network logo shares its row. A row of nothing but
  /// such words, "VISA PLATINUM", yields nothing.
  static NameCandidate? parseRows(
    List<List<TextLine>> rows, {
    TextBox? panBox,
    TextBox? expiryBox,
  }) {
    NameCandidate? best;
    for (final row in rows) {
      final candidate = _fromRow(row, panBox: panBox, expiryBox: expiryBox);
      if (candidate == null) continue;
      if (best == null ||
          candidate.score > best.score ||
          (candidate.score == best.score && candidate.box.top > best.box.top)) {
        best = candidate;
      }
    }
    return best;
  }

  static NameCandidate? _fromRow(
    List<TextLine> row, {
    TextBox? panBox,
    TextBox? expiryBox,
  }) {
    final words = <_Word>[];
    for (final line in row) {
      for (final word in _normalize(line.text).split(' ')) {
        if (word.isEmpty) continue;
        words.add(_Word(word, line.box, line.confidence));
      }
    }

    var start = 0;
    var end = words.length;
    while (start < end && _isNoise(words[start].text)) {
      start++;
    }
    while (end > start && _isNoise(words[end - 1].text)) {
      end--;
    }
    if (start == end) return null;

    final kept = words.sublist(start, end);
    final text = kept.map((w) => w.text).join(' ');
    if (!looksLikeName(text)) return null;

    final box = kept.map((w) => w.box).reduce((a, b) => a.union(b));
    final confidence =
        kept.map((w) => w.confidence).reduce((a, b) => a + b) / kept.length;
    return NameCandidate(
      name: text,
      box: box,
      confidence: confidence,
      score: _score(text, box, panBox, expiryBox),
    );
  }

  /// Whether [word] can never be part of a printed name: a known card word,
  /// or anything that is not letters with name punctuation.
  static bool _isNoise(String word) {
    final bare = _bare(word);
    if (bare.isEmpty) return true;
    if (stopWords.contains(bare)) return true;
    return !_wordPattern.hasMatch(word);
  }

  /// Positional ranking. The name block is printed flush with the left edge
  /// of the number and close to it, which is what separates it from card
  /// art and from text set beside the block.
  static int _score(
    String text,
    TextBox box,
    TextBox? panBox,
    TextBox? expiryBox,
  ) {
    var score = 0;

    if (panBox != null && panBox.width > 0) {
      if ((box.left - panBox.left).abs() <= panBox.width * 0.12) score += 3;
      // Text that starts past the middle of the number sits beside the name
      // block rather than in it: a tier label, a logo, a material claim.
      if (box.left > panBox.centerX) score -= 4;

      // Below the number there is little else but the name and the expiry,
      // so the window is wide. Above it the issuer logo starts almost at
      // once, so the window is narrow.
      if (box.top >= panBox.bottom) {
        score += box.top - panBox.bottom <= panBox.height * 4 ? 2 : -1;
      } else if (box.bottom <= panBox.top) {
        // Some cards print the name above the number. Further up is the
        // issuer name, not the holder.
        score += panBox.top - box.bottom <= panBox.height * 2 ? 1 : -2;
      }
    }

    if (expiryBox != null && expiryBox.height > 0) {
      if ((box.centerY - expiryBox.centerY).abs() <= expiryBox.height * 3) {
        score += 1;
      }
    }

    final wordCount = text.split(' ').length;
    if (wordCount == 2 || wordCount == 3) score += 1;

    return score;
  }

  static String _bare(String word) => word.replaceAll(RegExp(r"[.'\-]"), '');

  static String _normalize(String text) =>
      text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// One word of OCR output together with the box of the line it came from.
class _Word {
  const _Word(this.text, this.box, this.confidence);

  final String text;
  final TextBox box;
  final double confidence;
}
