/// Card networks the scanner recognizes.
///
/// A network is listed here only when its prefixes and lengths are
/// documented well enough to reject OCR noise. Every candidate must also
/// pass the Luhn check, so cards issued outside the checksum (a few
/// 19-digit UnionPay ranges) are not detected.
enum CardBrand {
  visa,
  mastercard,
  amex,
  discover,
  jcb,
  diners,
  unionpay;

  /// Human-readable brand name.
  String get displayName => switch (this) {
    CardBrand.visa => 'Visa',
    CardBrand.mastercard => 'Mastercard',
    CardBrand.amex => 'American Express',
    CardBrand.discover => 'Discover',
    CardBrand.jcb => 'JCB',
    CardBrand.diners => 'Diners Club',
    CardBrand.unionpay => 'UnionPay',
  };

  /// PAN lengths that are valid for this brand.
  List<int> get validLengths => switch (this) {
    CardBrand.visa => const [16, 19],
    CardBrand.mastercard => const [16],
    CardBrand.amex => const [15],
    CardBrand.discover => const [16, 19],
    CardBrand.jcb => const [16, 17, 18, 19],
    CardBrand.diners => const [14, 16],
    CardBrand.unionpay => const [16, 17, 18, 19],
  };

  /// Digit grouping used when formatting a PAN of [length] for display.
  ///
  /// Only Diners Club differs by length: the classic 14-digit card is
  /// printed 4-6-4, while its 16-digit cards follow the usual blocks.
  List<int> groupingFor(int length) => switch (this) {
    CardBrand.amex => const [4, 6, 5],
    CardBrand.diners => length <= 14 ? const [4, 6, 4] : const [4, 4, 4, 4, 3],
    CardBrand.visa ||
    CardBrand.mastercard ||
    CardBrand.discover ||
    CardBrand.jcb ||
    CardBrand.unionpay => const [4, 4, 4, 4, 3],
  };

  /// Grouping for this brand's most common PAN length.
  List<int> get grouping => groupingFor(validLengths.first);

  /// Detects the brand from the leading digits of [digits].
  ///
  /// Returns `null` if the prefix does not belong to a supported network.
  /// Length is not validated here — see [matchesLength].
  ///
  /// Discover and UnionPay both claim 622126-622925. Discover is matched
  /// on its own prefixes only (6011, 644-649, 65), so that shared range
  /// resolves to UnionPay, which is what the issuer printed on the card.
  static CardBrand? detect(String digits) {
    if (digits.isEmpty) return null;

    if (digits.startsWith('4')) return CardBrand.visa;

    if (digits.length >= 2) {
      final p2 = int.tryParse(digits.substring(0, 2));
      if (p2 != null) {
        if (p2 == 34 || p2 == 37) return CardBrand.amex;
        if (p2 >= 51 && p2 <= 55) return CardBrand.mastercard;
        if (p2 == 36 || p2 == 38 || p2 == 39) return CardBrand.diners;
        if (p2 == 65) return CardBrand.discover;
        if (p2 == 62 || p2 == 81) return CardBrand.unionpay;
      }
    }

    if (digits.length >= 3) {
      final p3 = int.tryParse(digits.substring(0, 3));
      if (p3 != null) {
        if (p3 >= 300 && p3 <= 305) return CardBrand.diners;
        if (p3 >= 644 && p3 <= 649) return CardBrand.discover;
      }
    }

    if (digits.length >= 4) {
      final p4 = int.tryParse(digits.substring(0, 4));
      if (p4 != null) {
        if (p4 >= 2221 && p4 <= 2720) return CardBrand.mastercard;
        if (p4 >= 3528 && p4 <= 3589) return CardBrand.jcb;
        if (p4 == 6011) return CardBrand.discover;
        if (p4 == 3095) return CardBrand.diners;
      }
    }

    return null;
  }

  /// Whether [length] is a valid PAN length for this brand.
  bool matchesLength(int length) => validLengths.contains(length);

  /// Formats [digits] with the brand's standard grouping, e.g.
  /// `4111 1111 1111 1111` or `3782 822463 10005`.
  String format(String digits) {
    final buffer = StringBuffer();
    var index = 0;
    for (final size in groupingFor(digits.length)) {
      if (index >= digits.length) break;
      if (buffer.isNotEmpty) buffer.write(' ');
      final end = (index + size).clamp(0, digits.length);
      buffer.write(digits.substring(index, end));
      index = end;
    }
    if (index < digits.length) {
      buffer.write(' ');
      buffer.write(digits.substring(index));
    }
    return buffer.toString();
  }
}
