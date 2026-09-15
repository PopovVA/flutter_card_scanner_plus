import 'package:flutter/material.dart';

import '../controller/card_scanner_controller.dart';

/// Default overlay: dimmed background with a card-shaped cutout, corner
/// brackets that turn [successColor] as fields are recognized, and the
/// fields found so far printed under the frame.
///
/// Reusable inside a custom `overlayBuilder` as well.
class CardFrameOverlay extends StatelessWidget {
  const CardFrameOverlay({
    super.key,
    required this.state,
    required this.cardRect,
    this.scrimColor = const Color(0x99000000),
    this.frameColor = Colors.white,
    this.successColor = const Color(0xFF4CD964),
    this.cornerRadius = 12,
    this.strokeWidth = 3,
    this.showFields = true,
    this.hint,
  });

  final CardScannerState state;
  final Rect cardRect;
  final Color scrimColor;
  final Color frameColor;
  final Color successColor;
  final double cornerRadius;
  final double strokeWidth;

  /// Print recognized number / expiry / name below the frame.
  final bool showFields;

  /// Text shown under the frame before anything is recognized.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    final color = result.isComplete
        ? successColor
        : result.hasNumber
        ? Color.lerp(frameColor, successColor, 0.6)!
        : frameColor;

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _FramePainter(
            cardRect: cardRect,
            scrimColor: scrimColor,
            color: color,
            cornerRadius: cornerRadius,
            strokeWidth: strokeWidth,
          ),
        ),
        if (showFields)
          Positioned(
            left: cardRect.left,
            width: cardRect.width,
            top: cardRect.bottom + 24,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!result.hasNumber && !result.hasExpiry)
                    Text(
                      hint ?? 'Align the card inside the frame',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),
                  if (result.hasNumber)
                    Text(
                      result.formattedNumber!,
                      style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
                    ),
                  if (result.hasExpiry || result.hasName)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        [
                          if (result.hasName) result.cardholderName!,
                          if (result.hasExpiry) result.formattedExpiry!,
                        ].join('   '),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.cardRect,
    required this.scrimColor,
    required this.color,
    required this.cornerRadius,
    required this.strokeWidth,
  });

  final Rect cardRect;
  final Color scrimColor;
  final Color color;
  final double cornerRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      cardRect,
      Radius.circular(cornerRadius),
    );

    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = scrimColor);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Corner brackets rather than a full border: reads as "viewfinder".
    final len = cardRect.width * 0.12;
    final r = cornerRadius;
    final l = cardRect.left,
        t = cardRect.top,
        rt = cardRect.right,
        b = cardRect.bottom;

    final path = Path()
      // top-left
      ..moveTo(l, t + len)
      ..lineTo(l, t + r)
      ..arcToPoint(Offset(l + r, t), radius: Radius.circular(r))
      ..lineTo(l + len, t)
      // top-right
      ..moveTo(rt - len, t)
      ..lineTo(rt - r, t)
      ..arcToPoint(Offset(rt, t + r), radius: Radius.circular(r))
      ..lineTo(rt, t + len)
      // bottom-right
      ..moveTo(rt, b - len)
      ..lineTo(rt, b - r)
      ..arcToPoint(Offset(rt - r, b), radius: Radius.circular(r))
      ..lineTo(rt - len, b)
      // bottom-left
      ..moveTo(l + len, b)
      ..lineTo(l + r, b)
      ..arcToPoint(Offset(l, b - r), radius: Radius.circular(r))
      ..lineTo(l, b - len);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.cardRect != cardRect ||
      old.color != color ||
      old.scrimColor != scrimColor ||
      old.cornerRadius != cornerRadius ||
      old.strokeWidth != strokeWidth;
}
