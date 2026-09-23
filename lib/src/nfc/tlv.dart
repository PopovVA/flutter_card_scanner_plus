import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One BER-TLV element as used by EMV.
@immutable
class Tlv {
  const Tlv({required this.tag, required this.value, required this.children});

  /// Tag bytes as an integer, e.g. `0x6F`, `0x4F`, `0xBF0C`.
  final int tag;

  /// Raw value. For a constructed element this is the encoded children.
  final Uint8List value;

  /// Parsed children, empty for a primitive element.
  final List<Tlv> children;

  bool get isConstructed => children.isNotEmpty;

  /// Value as uppercase hex, e.g. `A0000000031010`.
  String get hex => TlvParser.toHex(value);

  @override
  String toString() =>
      'Tlv(${tag.toRadixString(16).toUpperCase()}, ${value.length} bytes)';
}

/// BER-TLV reader for EMV responses.
///
/// Malformed input is tolerated: parsing stops at the first element that
/// does not fit, and whatever was read so far is returned. Cards do emit
/// padding bytes after the last element.
abstract final class TlvParser {
  /// Parses [bytes] into top level elements, recursing into constructed ones.
  static List<Tlv> parse(Uint8List bytes) => _parse(bytes, 0, bytes.length);

  static List<Tlv> _parse(Uint8List bytes, int start, int end) {
    final result = <Tlv>[];
    var i = start;

    while (i < end) {
      // Padding between elements.
      if (bytes[i] == 0x00 || bytes[i] == 0xFF) {
        i++;
        continue;
      }

      final tagStart = i;
      var tag = bytes[i];
      final constructed = (bytes[i] & 0x20) != 0;
      i++;

      // Multi byte tag: low five bits all set, then continue while bit 8 set.
      if ((bytes[tagStart] & 0x1F) == 0x1F) {
        while (i < end) {
          tag = (tag << 8) | bytes[i];
          final more = (bytes[i] & 0x80) != 0;
          i++;
          if (!more) break;
        }
      }
      if (i >= end) break;

      var length = bytes[i];
      i++;
      if (length > 0x80) {
        final count = length & 0x7F;
        if (count > 4 || i + count > end) break;
        length = 0;
        for (var n = 0; n < count; n++) {
          length = (length << 8) | bytes[i];
          i++;
        }
      } else if (length == 0x80) {
        // Indefinite length is not used by EMV.
        break;
      }

      if (i + length > end) break;
      final value = Uint8List.sublistView(bytes, i, i + length);
      i += length;

      result.add(
        Tlv(
          tag: tag,
          value: value,
          children: constructed ? _parse(bytes, i - length, i) : const [],
        ),
      );
    }
    return result;
  }

  /// Returns every element with [tag], at any depth, in document order.
  static List<Tlv> findAll(List<Tlv> elements, int tag) {
    final found = <Tlv>[];
    void walk(List<Tlv> list) {
      for (final element in list) {
        if (element.tag == tag) found.add(element);
        walk(element.children);
      }
    }

    walk(elements);
    return found;
  }

  /// Returns the first element with [tag] at any depth, or `null`.
  static Tlv? find(List<Tlv> elements, int tag) {
    final all = findAll(elements, tag);
    return all.isEmpty ? null : all.first;
  }

  /// Uppercase hex without separators.
  static String toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return buffer.toString();
  }

  /// Parses uppercase or lowercase hex, ignoring spaces.
  static Uint8List fromHex(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s'), '');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
