import 'package:meta/meta.dart';

import '../core/card_brand.dart';
import '../core/luhn.dart';

/// Card data recovered from an EMV record.
@immutable
class Track2Data {
  const Track2Data({
    required this.pan,
    required this.brand,
    this.expiryMonth,
    this.expiryYear,
  });

  /// Digits only.
  final String pan;
  final CardBrand brand;

  /// `1..12`, or `null` when the record carried no date.
  final int? expiryMonth;

  /// Four digit year, or `null`.
  final int? expiryYear;

  bool get hasExpiry => expiryMonth != null && expiryYear != null;

  @override
  String toString() =>
      'Track2Data(${brand.name}, ****${pan.substring(pan.length - 4)})';
}

/// Reads Track 2 Equivalent Data (EMV tag `57`).
///
/// The field is a hex encoded magnetic stripe track: the card number, the
/// separator `D`, the expiry as `YYMM`, a three digit service code, then
/// discretionary data padded with `F`.
abstract final class Track2Parser {
  /// Parses [hex], e.g. `4761739001010119D22122011758928889`.
  ///
  /// Returns `null` when the field is malformed, the number fails the Luhn
  /// check, or the network is not one this package supports.
  static Track2Data? parse(String hex) {
    final separator = hex.indexOf(RegExp('[DE=]', caseSensitive: false));
    final pan = (separator < 0 ? hex : hex.substring(0, separator)).replaceAll(
      RegExp('[Ff]'),
      '',
    );
    final validated = _validatePan(pan);
    if (validated == null) return null;

    int? month;
    int? year;
    if (separator >= 0 && hex.length >= separator + 5) {
      // Track 2 stores the expiry as YYMM, unlike tag 5F24 which is YYMMDD.
      final yy = int.tryParse(hex.substring(separator + 1, separator + 3));
      final mm = int.tryParse(hex.substring(separator + 3, separator + 5));
      if (yy != null && mm != null && mm >= 1 && mm <= 12) {
        month = mm;
        year = 2000 + yy;
      }
    }

    return Track2Data(
      pan: pan,
      brand: validated,
      expiryMonth: month,
      expiryYear: year,
    );
  }

  /// Parses a bare PAN from tag `5A`, which may be padded with `F`.
  static Track2Data? fromPan(String hex) {
    final pan = hex.replaceAll(RegExp('[Ff]'), '');
    final brand = _validatePan(pan);
    return brand == null ? null : Track2Data(pan: pan, brand: brand);
  }

  /// Parses tag `5F24`, the application expiry date, encoded as `YYMMDD`.
  ///
  /// Returns `(month, year)` or `null`.
  static (int, int)? parseExpiryDate(String hex) {
    if (hex.length < 4) return null;
    final yy = int.tryParse(hex.substring(0, 2));
    final mm = int.tryParse(hex.substring(2, 4));
    if (yy == null || mm == null || mm < 1 || mm > 12) return null;
    return (mm, 2000 + yy);
  }

  static CardBrand? _validatePan(String pan) {
    if (pan.length < 15 || pan.length > 19) return null;
    if (!RegExp(r'^\d+$').hasMatch(pan)) return null;
    final brand = CardBrand.detect(pan);
    if (brand == null || !brand.matchesLength(pan.length)) return null;
    if (!Luhn.isValid(pan)) return null;
    return brand;
  }
}
