import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One entry of a Data Object List: a tag the card wants and how many bytes
/// it expects for it.
@immutable
class DolEntry {
  const DolEntry({required this.tag, required this.length});

  final int tag;
  final int length;

  @override
  String toString() =>
      'DolEntry(${tag.toRadixString(16).toUpperCase()}, $length)';
}

/// The terminal values handed to the card in GET PROCESSING OPTIONS.
///
/// A card asks for whatever it needs through its PDOL; anything this profile
/// does not know is sent as zeros, which cards accept for a read that never
/// goes on to authorize a payment.
@immutable
class TerminalProfile {
  const TerminalProfile({
    this.countryCode = 0x0840,
    this.currencyCode = 0x0840,
    this.terminalType = 0x22,
    this.transactionQualifiers = const [0x36, 0x00, 0x40, 0x00],
  });

  /// ISO 3166 numeric, BCD encoded. Defaults to 0840 (US).
  final int countryCode;

  /// ISO 4217 numeric, BCD encoded. Defaults to 0840 (USD).
  final int currencyCode;

  /// EMV tag `9F35`. `0x22` is an attended, offline capable terminal.
  final int terminalType;

  /// EMV tag `9F66`, Terminal Transaction Qualifiers.
  final List<int> transactionQualifiers;

  static const standard = TerminalProfile();
}

/// Parses Data Object Lists and builds the values a card asks for.
abstract final class Dol {
  /// Parses a DOL, e.g. the PDOL from tag `9F38`.
  ///
  /// Stops at the first malformed entry rather than throwing.
  static List<DolEntry> parse(Uint8List bytes) {
    final entries = <DolEntry>[];
    var i = 0;
    while (i < bytes.length) {
      var tag = bytes[i];
      final first = bytes[i];
      i++;
      if ((first & 0x1F) == 0x1F) {
        while (i < bytes.length) {
          tag = (tag << 8) | bytes[i];
          final more = (bytes[i] & 0x80) != 0;
          i++;
          if (!more) break;
        }
      }
      if (i >= bytes.length) break;
      entries.add(DolEntry(tag: tag, length: bytes[i]));
      i++;
    }
    return entries;
  }

  /// Concatenates the values for [entries], in order, each padded or cut to
  /// the length the card asked for.
  static Uint8List buildValues(
    List<DolEntry> entries, {
    TerminalProfile profile = TerminalProfile.standard,
    DateTime? now,
    Random? random,
  }) {
    final today = now ?? DateTime.now();
    final rng = random ?? Random.secure();
    final out = <int>[];

    for (final entry in entries) {
      out.addAll(_fit(_valueFor(entry.tag, profile, today, rng), entry.length));
    }
    return Uint8List.fromList(out);
  }

  static List<int> _valueFor(
    int tag,
    TerminalProfile profile,
    DateTime now,
    Random rng,
  ) {
    switch (tag) {
      case 0x9F66: // Terminal Transaction Qualifiers
        return profile.transactionQualifiers;
      case 0x9F1A: // Terminal Country Code
        return _bcd16(profile.countryCode);
      case 0x5F2A: // Transaction Currency Code
        return _bcd16(profile.currencyCode);
      case 0x9F35: // Terminal Type
        return [profile.terminalType];
      case 0x9A: // Transaction Date, YYMMDD
        return [_bcd8(now.year % 100), _bcd8(now.month), _bcd8(now.day)];
      case 0x9F37: // Unpredictable Number
        return List<int>.generate(4, (_) => rng.nextInt(256));
      case 0x9F4E: // Merchant Name and Location
        return List<int>.filled(20, 0x20);
      default:
        // Amounts, TVR, CVM results, transaction type and anything unknown:
        // zeros are what a read only terminal sends.
        return const [];
    }
  }

  /// Pads with zeros on the right or truncates to [length].
  static List<int> _fit(List<int> value, int length) {
    if (value.length == length) return value;
    if (value.length > length) return value.sublist(0, length);
    return [...value, ...List<int>.filled(length - value.length, 0x00)];
  }

  /// Encodes a four digit number as two BCD bytes, e.g. 0840 to `08 40`.
  static List<int> _bcd16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

  /// Encodes a two digit number as one BCD byte, e.g. 25 to `0x25`.
  static int _bcd8(int value) => ((value ~/ 10) << 4) | (value % 10);
}
