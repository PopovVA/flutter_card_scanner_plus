import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/card_scanner_controller.dart';
import '../core/recognized_text.dart';
import 'card_frame_overlay.dart';

/// Builds the UI drawn on top of the camera preview.
///
/// [cardRect] is where the card frame sits, in this widget's coordinates.
typedef CardScannerOverlayBuilder = Widget Function(
  BuildContext context,
  CardScannerState state,
  Rect cardRect,
);

/// Camera preview with a card-shaped scanning frame.
///
/// Supply [overlayBuilder] to draw your own UI; otherwise a default
/// [CardFrameOverlay] is shown. The OCR region of interest is kept in sync
/// with the frame automatically.
class CardScannerView extends StatefulWidget {
  const CardScannerView({
    super.key,
    required this.controller,
    this.overlayBuilder,
    this.autoStart = true,
    this.cardAspectRatio = CardScannerView.iso7810AspectRatio,
    this.frameWidthFraction = 0.88,
    this.frameAlignment = const Alignment(0, -0.2),
    this.backgroundColor = Colors.black,
  }) : assert(frameWidthFraction > 0 && frameWidthFraction <= 1);

  /// ID-1 card: 85.60 × 53.98 mm.
  static const double iso7810AspectRatio = 85.60 / 53.98;

  final CardScannerController controller;
  final CardScannerOverlayBuilder? overlayBuilder;

  /// Call [CardScannerController.start] when first laid out.
  final bool autoStart;

  final double cardAspectRatio;

  /// Frame width relative to the view width.
  final double frameWidthFraction;

  /// Where the frame sits within the view.
  final Alignment frameAlignment;

  /// Shown before the first camera frame arrives.
  final Color backgroundColor;

  @override
  State<CardScannerView> createState() => _CardScannerViewState();
}

class _CardScannerViewState extends State<CardScannerView> {
  Size? _lastSize;
  int? _lastTextureId;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.controller.start(),
      );
    }
  }

  Rect _cardRect(Size size) {
    final width = size.width * widget.frameWidthFraction;
    final height = width / widget.cardAspectRatio;
    final free = Size(size.width - width, size.height - height);
    final origin = widget.frameAlignment.alongSize(free);
    return Rect.fromLTWH(origin.dx, origin.dy, width, height);
  }

  /// Rect of the preview texture as it is drawn (BoxFit.cover), in view
  /// coordinates — may exceed the view bounds.
  Rect _previewRect(Size view, Size preview) {
    final scale = math.max(
      view.width / preview.width,
      view.height / preview.height,
    );
    final w = preview.width * scale;
    final h = preview.height * scale;
    return Rect.fromLTWH((view.width - w) / 2, (view.height - h) / 2, w, h);
  }

  void _syncRegionOfInterest(Size size, CardScannerState state) {
    final camera = state.camera;
    if (camera == null) return;
    if (_lastSize == size && _lastTextureId == camera.textureId) return;
    _lastSize = size;
    _lastTextureId = camera.textureId;

    final preview = _previewRect(
      size,
      Size(camera.previewWidth.toDouble(), camera.previewHeight.toDouble()),
    );
    // Pad the frame a little: users rarely align the card perfectly.
    final card = _cardRect(size).inflate(_cardRect(size).height * 0.15);
    final roi = TextBox(
      left: ((card.left - preview.left) / preview.width).clamp(0.0, 1.0),
      top: ((card.top - preview.top) / preview.height).clamp(0.0, 1.0),
      width: (card.width / preview.width).clamp(0.0, 1.0),
      height: (card.height / preview.height).clamp(0.0, 1.0),
    );
    widget.controller.setRegionOfInterest(roi);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final cardRect = _cardRect(size);
        return ValueListenableBuilder<CardScannerState>(
          valueListenable: widget.controller,
          builder: (context, state, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncRegionOfInterest(size, state);
            });
            final camera = state.camera;
            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: widget.backgroundColor),
                if (camera != null)
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: camera.previewWidth.toDouble(),
                        height: camera.previewHeight.toDouble(),
                        child: Texture(textureId: camera.textureId),
                      ),
                    ),
                  ),
                widget.overlayBuilder?.call(context, state, cardRect) ??
                    CardFrameOverlay(state: state, cardRect: cardRect),
              ],
            );
          },
        );
      },
    );
  }
}
