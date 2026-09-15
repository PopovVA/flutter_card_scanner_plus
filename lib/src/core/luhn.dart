/// Luhn (mod 10) checksum used by all major card networks.
abstract final class Luhn {
  /// Returns `true` if [digits] (ASCII digits only) passes the Luhn check.
  ///
  /// Any non-digit character makes the check fail.
  static bool isValid(String digits) {
    if (digits.length < 2) return false;

    var sum = 0;
    var doubleIt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      final code = digits.codeUnitAt(i) - 0x30;
      if (code < 0 || code > 9) return false;

      var value = code;
      if (doubleIt) {
        value *= 2;
        if (value > 9) value -= 9;
      }
      sum += value;
      doubleIt = !doubleIt;
    }
    return sum % 10 == 0;
  }
}
