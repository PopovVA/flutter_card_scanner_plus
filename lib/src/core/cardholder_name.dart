import 'package:meta/meta.dart';

/// A printed cardholder name split into the parts a payment form asks for.
///
/// Cards print one line and never say where the surname starts, so this is
/// a convention, not a fact: the last word is the surname, anything before
/// it is the given name, and a particle in front of the surname belongs to
/// it. It gets "MARIA DE LA CRUZ" and "WREN A. NGUYEN" right and will get
/// some names wrong, so let people correct it.
@immutable
class CardholderName {
  const CardholderName({required this.given, required this.family});

  /// Words that belong to the surname they precede.
  static const particles = {
    'DA',
    'DAS',
    'DE',
    'DEL',
    'DELLA',
    'DEN',
    'DER',
    'DI',
    'DO',
    'DOS',
    'DU',
    'LA',
    'LE',
    'VAN',
    'VON',
  };

  /// Everything before the surname, middle names and initials included.
  /// Empty when the name is a single word.
  final String given;

  /// The surname, with any particles in front of it. Empty only when
  /// [printed] held nothing usable.
  final String family;

  /// Splits [printed] as described above.
  ///
  /// ```dart
  /// CardholderName.split('MARIA DE LA CRUZ'); // MARIA | DE LA CRUZ
  /// CardholderName.split('WREN A. NGUYEN');   // WREN A. | NGUYEN
  /// ```
  factory CardholderName.split(String printed) {
    final words = printed.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const CardholderName(given: '', family: '');
    if (words.length == 1) {
      return CardholderName(given: '', family: words.single);
    }

    var start = words.length - 1;
    while (start > 0 && particles.contains(_bare(words[start - 1]))) {
      start--;
    }

    return CardholderName(
      given: words.sublist(0, start).join(' '),
      family: words.sublist(start).join(' '),
    );
  }

  bool get isEmpty => given.isEmpty && family.isEmpty;

  static String _bare(String word) =>
      word.replaceAll(RegExp(r"[.'\-]"), '').toUpperCase();

  @override
  bool operator ==(Object other) =>
      other is CardholderName && other.given == given && other.family == family;

  @override
  int get hashCode => Object.hash(given, family);

  @override
  String toString() => 'CardholderName($given | $family)';
}
