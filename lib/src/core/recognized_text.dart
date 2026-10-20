import 'package:meta/meta.dart';

/// Axis-aligned bounding box in normalized image coordinates (0..1),
/// origin at the top-left corner of the analyzed image.
@immutable
class TextBox {
  /// A box at [left] and [top] of the given [width] and [height], all as
  /// fractions of the analyzed image.
  const TextBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// A box covering nothing, used when the platform reports no geometry.
  static const zero = TextBox(left: 0, top: 0, width: 0, height: 0);

  /// Distance from the left edge of the image, as a fraction of its width.
  final double left;

  /// Distance from the top edge of the image, as a fraction of its height.
  final double top;

  /// Width as a fraction of the image's width.
  final double width;

  /// Height as a fraction of the image's height.
  final double height;

  /// Right edge, that is [left] plus [width].
  double get right => left + width;

  /// Bottom edge, that is [top] plus [height].
  double get bottom => top + height;

  /// Horizontal centre of the box.
  double get centerX => left + width / 2;

  /// Vertical centre of the box, which is what decides whether two lines
  /// sit on the same printed row.
  double get centerY => top + height / 2;

  /// Smallest box containing both this and [other].
  TextBox union(TextBox other) {
    final l = left < other.left ? left : other.left;
    final t = top < other.top ? top : other.top;
    final r = right > other.right ? right : other.right;
    final b = bottom > other.bottom ? bottom : other.bottom;
    return TextBox(left: l, top: t, width: r - l, height: b - t);
  }

  /// Reads a box from the platform channel's [map], treating anything
  /// missing as zero.
  factory TextBox.fromMap(Map<Object?, Object?> map) => TextBox(
    left: (map['left'] as num?)?.toDouble() ?? 0,
    top: (map['top'] as num?)?.toDouble() ?? 0,
    width: (map['width'] as num?)?.toDouble() ?? 0,
    height: (map['height'] as num?)?.toDouble() ?? 0,
  );

  /// The box as the platform channel carries it.
  Map<String, double> toMap() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  @override
  bool operator ==(Object other) =>
      other is TextBox &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'TextBox(l: ${left.toStringAsFixed(3)}, t: ${top.toStringAsFixed(3)}, '
      'w: ${width.toStringAsFixed(3)}, h: ${height.toStringAsFixed(3)})';
}

/// A single line of text produced by the platform OCR engine.
@immutable
class TextLine {
  /// A line reading [text], found at [box], with the engine's
  /// [confidence] in it.
  const TextLine({
    required this.text,
    this.box = TextBox.zero,
    this.confidence = 1.0,
  });

  /// Raw recognized text, as returned by the OCR engine.
  final String text;

  /// Location of the line within the analyzed image.
  final TextBox box;

  /// Engine confidence in `0..1`. Engines that do not report confidence
  /// use `1.0`.
  final double confidence;

  /// Reads a line from the platform channel's [map]. A line without
  /// geometry gets [TextBox.zero], and one without a score gets `1.0`.
  factory TextLine.fromMap(Map<Object?, Object?> map) => TextLine(
    text: map['text'] as String? ?? '',
    box: map['box'] is Map
        ? TextBox.fromMap(map['box'] as Map<Object?, Object?>)
        : TextBox.zero,
    confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
  );

  @override
  String toString() => 'TextLine("$text", $box, c=$confidence)';
}

/// All text recognized in one camera frame.
@immutable
class RecognizedFrame {
  /// A frame holding [lines], in whatever order the engine returned them.
  const RecognizedFrame({required this.lines});

  /// Every line the engine found, unordered: nothing reads them without
  /// grouping them into rows first.
  final List<TextLine> lines;

  /// A frame in which nothing was recognized.
  static const empty = RecognizedFrame(lines: []);

  /// Reads a frame from the platform channel's [map], skipping any entry
  /// that is not a line.
  factory RecognizedFrame.fromMap(Map<Object?, Object?> map) {
    final raw = map['lines'] as List<Object?>? ?? const [];
    return RecognizedFrame(
      lines: raw
          .whereType<Map<Object?, Object?>>()
          .map(TextLine.fromMap)
          .toList(growable: false),
    );
  }
}
