import 'package:meta/meta.dart';

/// A printed cardholder name split into the parts a payment form asks for.
///
/// Cards print one line and never say where the surname starts, so this is
/// a convention, not a fact:
///
/// * the first word is always the given name, because a card prints one;
/// * the last word is the surname;
/// * a particle in front of the surname belongs to it;
/// * a generational suffix at the end belongs to it too.
///
/// It gets "MARIA DE LA CRUZ", "WREN A. NGUYEN", "DEL SMITH" and
/// "JOHN SMITH JR" right and will get some names wrong, so let people
/// correct it.
@immutable
class CardholderName {
  /// A name already divided into its [given] and [family] parts.
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

  /// Generational suffixes, which belong to the surname they follow.
  ///
  /// Punctuation is ignored, so "JR" and "JR." are the same word.
  static const suffixes = {'JR', 'SR', 'II', 'III', 'IV'};

  /// Everything before the surname, middle names and initials included.
  /// Empty when the name is a single word.
  final String given;

  /// The surname, with any particles in front of it and any suffix after
  /// it. Empty only when there was nothing usable to split.
  final String family;

  /// Splits [printed] as described above.
  ///
  /// ```dart
  /// CardholderName.split('MARIA DE LA CRUZ'); // MARIA | DE LA CRUZ
  /// CardholderName.split('WREN A. NGUYEN');   // WREN A. | NGUYEN
  /// CardholderName.split('JOHN SMITH JR');    // JOHN | SMITH JR
  /// CardholderName.split('DEL SMITH');        // DEL | SMITH
  /// ```
  factory CardholderName.split(String printed) {
    final words = printed.trim().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const CardholderName(given: '', family: '');
    if (words.length == 1) {
      return CardholderName(given: '', family: words.single);
    }

    // A suffix joins the surname only while a given name and a surname are
    // left in front of it, so "ADA II" keeps II as the surname rather than
    // leaving nothing behind.
    var end = words.length;
    while (end > 2 && suffixes.contains(_bare(words[end - 1]))) {
      end--;
    }

    // Particles walk back from the surname but never take the first word:
    // DEL, LE and DU are given names as often as they are particles, and a
    // card always prints a given name.
    var start = end - 1;
    while (start > 1 && particles.contains(_bare(words[start - 1]))) {
      start--;
    }

    return CardholderName(
      given: words.sublist(0, start).join(' '),
      family: words.sublist(start).join(' '),
    );
  }

  /// Whether nothing was recognized at all.
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
