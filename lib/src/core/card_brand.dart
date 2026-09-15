/// Card networks supported by the scanner.
enum CardBrand {
  visa,
  mastercard,
  amex;

  /// Human-readable brand name.
  String get displayName => switch (this) {
    CardBrand.visa => 'Visa',
    CardBrand.mastercard => 'Mastercard',
    CardBrand.amex => 'American Express',
  };

  /// PAN lengths that are valid for this brand.
  List<int> get validLengths => switch (this) {
    CardBrand.visa => const [16, 19],
    CardBrand.mastercard => const [16],
    CardBrand.amex => const [15],
  };

  /// Digit grouping used when formatting the PAN for display.
  List<int> get grouping => switch (this) {
    CardBrand.amex => const [4, 6, 5],
    CardBrand.visa || CardBrand.mastercard => const [4, 4, 4, 4, 3],
  };

  /// Detects the brand from the leading digits of [digits].
  ///
  /// Returns `null` if the prefix does not belong to a supported network.
  /// Length is not validated here — see [matchesLength].
  static CardBrand? detect(String digits) {
    if (digits.isEmpty) return null;

    if (digits.startsWith('4')) return CardBrand.visa;

    if (digits.length >= 2) {
      final p2 = int.tryParse(digits.substring(0, 2));
      if (p2 != null) {
        if (p2 == 34 || p2 == 37) return CardBrand.amex;
        if (p2 >= 51 && p2 <= 55) return CardBrand.mastercard;
      }
    }

    if (digits.length >= 4) {
      final p4 = int.tryParse(digits.substring(0, 4));
      if (p4 != null && p4 >= 2221 && p4 <= 2720) return CardBrand.mastercard;
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
    for (final size in grouping) {
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
