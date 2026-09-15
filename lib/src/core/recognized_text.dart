import 'package:meta/meta.dart';

/// Axis-aligned bounding box in normalized image coordinates (0..1),
/// origin at the top-left corner of the analyzed image.
@immutable
class TextBox {
  const TextBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// A box covering nothing, used when the platform reports no geometry.
  static const zero = TextBox(left: 0, top: 0, width: 0, height: 0);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  /// Smallest box containing both this and [other].
  TextBox union(TextBox other) {
    final l = left < other.left ? left : other.left;
    final t = top < other.top ? top : other.top;
    final r = right > other.right ? right : other.right;
    final b = bottom > other.bottom ? bottom : other.bottom;
    return TextBox(left: l, top: t, width: r - l, height: b - t);
  }

  factory TextBox.fromMap(Map<Object?, Object?> map) => TextBox(
    left: (map['left'] as num?)?.toDouble() ?? 0,
    top: (map['top'] as num?)?.toDouble() ?? 0,
    width: (map['width'] as num?)?.toDouble() ?? 0,
    height: (map['height'] as num?)?.toDouble() ?? 0,
  );

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
  const RecognizedFrame({required this.lines});

  final List<TextLine> lines;

  static const empty = RecognizedFrame(lines: []);

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
