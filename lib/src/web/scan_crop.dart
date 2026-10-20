import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/recognized_text.dart';

/// The piece of a camera frame to recognize, in whole video pixels, and the
/// size to hand the OCR engine.
///
/// The browser pipeline cuts the frame down twice before recognition. It
/// takes only what is inside the guide, because anything outside it is not
/// the card, and it shrinks what is left, because recognition cost grows
/// with area and a card fills a 960 pixel crop comfortably.
@immutable
class ScanCrop {
  /// A crop taking [width] by [height] pixels at [left] and [top], to be
  /// drawn at [outWidth] by [outHeight].
  const ScanCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.outWidth,
    required this.outHeight,
  });

  /// Longest side of the image handed to the engine, unless a caller asks
  /// for another. Measured: a 960 pixel crop of a card reads in about a
  /// second, and a larger one reads no better.
  static const defaultLongestSide = 960;

  /// Left edge of the source rectangle, in video pixels.
  final int left;

  /// Top edge of the source rectangle, in video pixels.
  final int top;

  /// Width of the source rectangle, in video pixels.
  final int width;

  /// Height of the source rectangle, in video pixels.
  final int height;

  /// Width to draw the crop at, never larger than [width].
  final int outWidth;

  /// Height to draw the crop at, never larger than [height].
  final int outHeight;

  /// Whether the crop is the whole frame drawn at its own size.
  bool get isFullSize => outWidth == width && outHeight == height;

  /// The crop for [region] of a [videoWidth] by [videoHeight] frame, or
  /// `null` when the region and the frame do not overlap.
  ///
  /// [region] is normalized to the frame, the same box the scanner sends to
  /// the platform, and `null` means the whole frame. [longestSide] caps the
  /// size handed to the engine; the crop is never enlarged to reach it.
  static ScanCrop? from({
    required TextBox? region,
    required int videoWidth,
    required int videoHeight,
    int longestSide = defaultLongestSide,
  }) {
    if (videoWidth <= 0 || videoHeight <= 0) return null;

    var left = 0;
    var top = 0;
    var width = videoWidth;
    var height = videoHeight;

    if (region != null) {
      // Round the edges rather than the size, so a region that starts just
      // inside a pixel does not lose a column off the far side.
      final l = (region.left * videoWidth).round().clamp(0, videoWidth);
      final t = (region.top * videoHeight).round().clamp(0, videoHeight);
      final r = (region.right * videoWidth).round().clamp(0, videoWidth);
      final b = (region.bottom * videoHeight).round().clamp(0, videoHeight);
      left = l;
      top = t;
      width = r - l;
      height = b - t;
      if (width <= 0 || height <= 0) return null;
    }

    final scale = math.min(1.0, longestSide / math.max(width, height));
    return ScanCrop(
      left: left,
      top: top,
      width: width,
      height: height,
      outWidth: math.max(1, (width * scale).round()),
      outHeight: math.max(1, (height * scale).round()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScanCrop &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height &&
      other.outWidth == outWidth &&
      other.outHeight == outHeight;

  @override
  int get hashCode =>
      Object.hash(left, top, width, height, outWidth, outHeight);

  @override
  String toString() =>
      'ScanCrop(${width}x$height at $left,$top -> ${outWidth}x$outHeight)';
}
