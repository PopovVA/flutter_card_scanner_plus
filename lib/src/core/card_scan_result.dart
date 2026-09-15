import 'package:meta/meta.dart';

import 'card_brand.dart';

/// Result of a card scan. Fields are `null` until recognized.
///
/// [toString] never prints the full card number.
@immutable
class CardScanResult {
  const CardScanResult({
    this.number,
    this.brand,
    this.expiryMonth,
    this.expiryYear,
    this.cardholderName,
    this.isComplete = false,
  });

  static const empty = CardScanResult();

  /// Digits only, e.g. `4111111111111111`.
  final String? number;

  final CardBrand? brand;

  /// `1..12`.
  final int? expiryMonth;

  /// Four-digit year.
  final int? expiryYear;

  /// Upper-case name as printed on the card.
  final String? cardholderName;

  /// `true` once every required field has been confirmed across
  /// multiple frames. See `ScanRequirements`.
  final bool isComplete;

  bool get hasNumber => number != null;
  bool get hasExpiry => expiryMonth != null && expiryYear != null;
  bool get hasName => cardholderName != null;

  /// Number grouped for display, e.g. `4111 1111 1111 1111`.
  String? get formattedNumber =>
      number == null ? null : (brand?.format(number!) ?? number);

  /// Number with all but the last four digits hidden, e.g. `•••• 1111`.
  String? get maskedNumber {
    final n = number;
    if (n == null) return null;
    return '•••• ${n.substring(n.length - 4)}';
  }

  /// Last four digits, or `null`.
  String? get last4 => number?.substring(number!.length - 4);

  /// `MM/YY`, or `null`.
  String? get formattedExpiry {
    if (!hasExpiry) return null;
    final mm = expiryMonth!.toString().padLeft(2, '0');
    final yy = (expiryYear! % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }

  /// Whether the expiry date is in the past relative to [now].
  bool isExpired({DateTime? now}) {
    if (!hasExpiry) return false;
    final today = now ?? DateTime.now();
    if (expiryYear! != today.year) return expiryYear! < today.year;
    return expiryMonth! < today.month;
  }

  CardScanResult copyWith({
    String? number,
    CardBrand? brand,
    int? expiryMonth,
    int? expiryYear,
    String? cardholderName,
    bool? isComplete,
  }) => CardScanResult(
    number: number ?? this.number,
    brand: brand ?? this.brand,
    expiryMonth: expiryMonth ?? this.expiryMonth,
    expiryYear: expiryYear ?? this.expiryYear,
    cardholderName: cardholderName ?? this.cardholderName,
    isComplete: isComplete ?? this.isComplete,
  );

  @override
  bool operator ==(Object other) =>
      other is CardScanResult &&
      other.number == number &&
      other.brand == brand &&
      other.expiryMonth == expiryMonth &&
      other.expiryYear == expiryYear &&
      other.cardholderName == cardholderName &&
      other.isComplete == isComplete;

  @override
  int get hashCode => Object.hash(
    number,
    brand,
    expiryMonth,
    expiryYear,
    cardholderName,
    isComplete,
  );

  /// Masked representation — safe to log.
  @override
  String toString() =>
      'CardScanResult(${brand?.name ?? '-'} ${maskedNumber ?? '-'} '
      'exp ${formattedExpiry ?? '-'} name ${cardholderName ?? '-'}'
      '${isComplete ? ' ✓' : ''})';
}
