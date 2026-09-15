import 'package:meta/meta.dart';

import 'expiry_parser.dart';
import 'name_parser.dart';
import 'pan_parser.dart';
import 'recognized_text.dart';

/// Everything extracted from a single OCR frame. Any field may be `null`.
@immutable
class FrameParseResult {
  const FrameParseResult({this.pan, this.expiry, this.name});

  static const empty = FrameParseResult();

  final PanCandidate? pan;
  final ExpiryCandidate? expiry;
  final NameCandidate? name;

  bool get isEmpty => pan == null && expiry == null && name == null;

  @override
  String toString() =>
      'FrameParseResult(pan: $pan, expiry: $expiry, name: $name)';
}

/// Turns raw OCR lines from one frame into card fields.
///
/// OCR engines frequently split a single printed line (e.g. the card
/// number) into several [TextLine]s. Lines are first merged into visual
/// rows by vertical overlap, and numbers/dates are searched per row.
abstract final class CardFrameParser {
  /// Two lines belong to the same row if their vertical centers differ by
  /// less than this fraction of the shorter line's height.
  static const _rowTolerance = 0.6;

  static FrameParseResult parse(RecognizedFrame frame, {DateTime? now}) {
    if (frame.lines.isEmpty) return FrameParseResult.empty;

    final rows = groupIntoRows(frame.lines);

    PanCandidate? pan;
    for (final row in rows) {
      final candidate = PanParser.parseLine(row);
      if (candidate != null &&
          (pan == null || candidate.confidence > pan.confidence)) {
        pan = candidate;
      }
    }

    ExpiryCandidate? expiry;
    for (final row in rows) {
      final candidate = ExpiryParser.parse(
        row.text,
        box: row.box,
        confidence: row.confidence,
        now: now,
      );
      if (candidate == null) continue;
      if (expiry == null || candidate.compareTo(expiry) > 0) expiry = candidate;
    }

    final name = NameParser.parse(
      frame.lines,
      panBox: pan?.box,
      expiryBox: expiry?.box,
    );

    return FrameParseResult(pan: pan, expiry: expiry, name: name);
  }

  /// Merges [lines] that sit on the same horizontal row into one
  /// [TextLine], ordered left to right. Rows are returned top to bottom.
  @visibleForTesting
  static List<TextLine> groupIntoRows(List<TextLine> lines) {
    final sorted = [...lines]
      ..sort((a, b) => a.box.centerY.compareTo(b.box.centerY));
    final rows = <List<TextLine>>[];

    for (final line in sorted) {
      if (rows.isNotEmpty && _sameRow(rows.last.last, line)) {
        rows.last.add(line);
      } else {
        rows.add([line]);
      }
    }

    return rows
        .map((row) {
          if (row.length == 1) return row.first;
          row.sort((a, b) => a.box.left.compareTo(b.box.left));
          final box = row.map((l) => l.box).reduce((a, b) => a.union(b));
          final confidence =
              row.map((l) => l.confidence).reduce((a, b) => a + b) / row.length;
          return TextLine(
            text: row.map((l) => l.text.trim()).join(' '),
            box: box,
            confidence: confidence,
          );
        })
        .toList(growable: false);
  }

  static bool _sameRow(TextLine a, TextLine b) {
    final minHeight = a.box.height < b.box.height ? a.box.height : b.box.height;
    if (minHeight <= 0) return false;
    return (a.box.centerY - b.box.centerY).abs() < minHeight * _rowTolerance;
  }
}
