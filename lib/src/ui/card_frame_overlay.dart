import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/card_scanner_controller.dart';
import '../core/card_scan_result.dart';
import '../core/frame_aggregator.dart';
import 'card_scanner_strings.dart';

/// Default overlay: dimmed background with a card-shaped cutout, corner
/// brackets that turn [successColor] as fields are recognized, a prompt
/// saying what the scanner is still looking for, and the fields found so
/// far.
///
/// Reusable inside a custom `overlayBuilder` as well.
class CardFrameOverlay extends StatefulWidget {
  const CardFrameOverlay({
    super.key,
    required this.state,
    required this.cardRect,
    this.requirements = ScanRequirements.standard,
    this.strings = CardScannerStrings.defaults,
    this.scrimColor = const Color(0x99000000),
    this.frameColor = Colors.white,
    this.successColor = const Color(0xFF4CD964),
    this.cornerRadius = 12,
    this.strokeWidth = 3,
    this.showFields = true,
    this.hint,
    this.enableHaptics = false,
  });

  final CardScannerState state;
  final Rect cardRect;

  /// What the scan is waiting for, which decides the prompt. A scanner that
  /// does not want the name must not ask for the card to be turned over.
  final ScanRequirements requirements;

  final CardScannerStrings strings;
  final Color scrimColor;
  final Color frameColor;
  final Color successColor;
  final double cornerRadius;
  final double strokeWidth;

  /// Print recognized number / expiry / name below the frame.
  final bool showFields;

  /// Replaces the prompt that would otherwise be chosen from [strings] by
  /// what has been recognized so far.
  final String? hint;

  /// Play one light haptic each time the prompt changes. Off by default:
  /// a scanner embedded in a larger flow may already have its own feedback.
  final bool enableHaptics;

  @override
  State<CardFrameOverlay> createState() => _CardFrameOverlayState();
}

class _CardFrameOverlayState extends State<CardFrameOverlay> {
  /// Room needed under the frame for the prompt and the fields.
  static const _fieldsMinHeight = 96.0;

  late String _prompt = _promptFor(widget);

  static String _promptFor(CardFrameOverlay widget) =>
      widget.hint ??
      widget.strings.hintFor(
        widget.state.result,
        wantsName:
            widget.requirements.isRequired(CardField.name) ||
            widget.requirements.isPreferred(CardField.name),
      );

  @override
  void didUpdateWidget(CardFrameOverlay old) {
    super.didUpdateWidget(old);
    final next = _promptFor(widget);
    if (next == _prompt) return;
    _prompt = next;
    // One tap per step forward, so the card can be turned over without
    // watching the screen.
    if (widget.enableHaptics) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.state.result;
    final color = result.isComplete
        ? widget.successColor
        : result.hasNumber
        ? Color.lerp(widget.frameColor, widget.successColor, 0.6)!
        : widget.frameColor;

    // LayoutBuilder sits outside the Stack so Positioned stays a direct
    // child of it, which Flutter requires.
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomBelow = constraints.maxHeight - widget.cardRect.bottom;
        final fitsBelow = roomBelow >= _fieldsMinHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _FramePainter(
                cardRect: widget.cardRect,
                scrimColor: widget.scrimColor,
                color: color,
                cornerRadius: widget.cornerRadius,
                strokeWidth: widget.strokeWidth,
              ),
            ),
            // Below the frame when there is room, otherwise pinned to the
            // bottom of the view: in landscape the frame nearly fills the
            // height and there is nothing underneath it.
            if (widget.showFields)
              Positioned(
                left: fitsBelow ? widget.cardRect.left : 16,
                width: fitsBelow
                    ? widget.cardRect.width
                    : constraints.maxWidth - 32,
                top: fitsBelow ? widget.cardRect.bottom + 20 : null,
                bottom: fitsBelow ? null : 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: fitsBelow ? null : const Color(0x99000000),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(fitsBelow ? 0 : 8),
                    child: _fields(result),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _fields(CardScanResult result) => DefaultTextStyle(
    style: const TextStyle(
      color: Colors.white,
      fontSize: 18,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    textAlign: TextAlign.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        Padding(
          padding: EdgeInsets.only(top: result.hasNumber ? 10 : 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Something is moving while the scanner waits, which is what
              // was missing when people thought it had frozen on the
              // number.
              if (_working(result))
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                ),
              Flexible(
                child: Text(
                  _prompt,
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Whether the scanner has something and is still working on the rest.
  bool _working(CardScanResult result) {
    if (result.isComplete) return false;
    return result.hasNumber ||
        result.hasExpiry ||
        result.hasName ||
        widget.state.confirming.isNotEmpty;
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
