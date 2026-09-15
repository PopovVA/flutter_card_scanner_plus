/// Helpers for repairing common OCR confusions in numeric fields.
abstract final class OcrNormalizer {
  /// Letters that OCR engines commonly emit in place of digits when reading
  /// embossed or printed card numbers.
  static const Map<String, String> _digitLookalikes = {
    'O': '0',
    'o': '0',
    'D': '0',
    'Q': '0',
    'I': '1',
    'l': '1',
    '|': '1',
    'i': '1',
    '!': '1',
    'Z': '2',
    'z': '2',
    'S': '5',
    's': '5',
    'B': '8',
    'G': '6',
    'T': '7',
  };

  /// Characters that are allowed inside a numeric token before repair.
  static final RegExp numericToken = RegExp(
    '[0-9${RegExp.escape(_digitLookalikes.keys.join())}]+',
  );

  /// Replaces digit look-alike letters in [input] with the digit they most
  /// likely represent. Characters not in the look-alike table are kept.
  static String repairDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_digitLookalikes[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Fraction of characters in [input] that are ASCII digits (0..1).
  static double digitRatio(String input) {
    if (input.isEmpty) return 0;
    var digits = 0;
    for (final code in input.codeUnits) {
      if (code >= 0x30 && code <= 0x39) digits++;
    }
    return digits / input.length;
  }

  /// Whether [input] consists solely of ASCII digits.
  static bool isAllDigits(String input) =>
      input.isNotEmpty && digitRatio(input) == 1.0;
}
