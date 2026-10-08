import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../channel/card_scanner_platform.dart';
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
    this.frameHeightFraction = 0.6,
    this.frameAlignment = const Alignment(0, -0.2),
    this.frameRegionPadding = 0,
    this.backgroundColor = Colors.black,
  }) : assert(frameWidthFraction > 0 && frameWidthFraction <= 1),
       assert(frameHeightFraction > 0 && frameHeightFraction <= 1),
       assert(frameRegionPadding >= 0);

  /// ID-1 card: 85.60 × 53.98 mm.
  static const double iso7810AspectRatio = 85.60 / 53.98;

  final CardScannerController controller;
  final CardScannerOverlayBuilder? overlayBuilder;

  /// Call [CardScannerController.start] when first laid out, and again if
  /// [controller] is later replaced.
  final bool autoStart;

  final double cardAspectRatio;

  /// Frame width relative to the view width. The frame never exceeds this,
  /// nor [frameHeightFraction] of the height, so it fits in any orientation.
  final double frameWidthFraction;

  /// Frame height relative to the view height. This is what keeps the frame
  /// on screen in landscape, where 88% of the width is taller than the view.
  final double frameHeightFraction;

  /// Where the frame sits within the view.
  final Alignment frameAlignment;

  /// Margin added around the frame before OCR runs, as a fraction of the
  /// frame height.
  ///
  /// Zero, the default, reads exactly what the user sees inside the frame.
  /// A larger value also reads the surroundings, which is how text near the
  /// card, a keyboard for instance, ends up supplying a cardholder name.
  final double frameRegionPadding;

  /// Shown before the first camera frame arrives.
  final Color backgroundColor;

  @override
  State<CardScannerView> createState() => _CardScannerViewState();
}

class _CardScannerViewState extends State<CardScannerView>
    with WidgetsBindingObserver {
  Size? _lastSize;
  CameraHandle? _lastCamera;
  bool _resumeOnReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.controller.start(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Releases the camera while the app is away and takes it back on return.
  ///
  /// Only from [AppLifecycleState.paused] and later: iOS also reports
  /// `inactive` for a permission dialog or a notification banner, and
  /// stopping the camera there would fight the very start that asked for
  /// permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_resumeOnReturn) return;
        _resumeOnReturn = false;
        widget.controller.start();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (!widget.controller.value.isRunning) return;
        _resumeOnReturn = state != AppLifecycleState.detached;
        widget.controller.stop();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void didUpdateWidget(CardScannerView old) {
    super.didUpdateWidget(old);
    // The cached region is only valid for the frame and the camera it was
    // computed from. Anything that reshapes either one invalidates it.
    if (old.controller != widget.controller ||
        old.cardAspectRatio != widget.cardAspectRatio ||
        old.frameWidthFraction != widget.frameWidthFraction ||
        old.frameHeightFraction != widget.frameHeightFraction ||
        old.frameAlignment != widget.frameAlignment ||
        old.frameRegionPadding != widget.frameRegionPadding) {
      _lastSize = null;
      _lastCamera = null;
    }
    // A swapped controller has no camera yet, and nothing else would open
    // one, so the preview would stay black.
    if (old.controller != widget.controller && widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.controller.start(),
      );
    }
  }

  /// The largest card shaped rect that fits both fractions, centred by
  /// [CardScannerView.frameAlignment].
  Rect _cardRect(Size size) {
    var width = size.width * widget.frameWidthFraction;
    var height = width / widget.cardAspectRatio;

    // Landscape: the width driven height would run off the screen, so the
    // height becomes the limit instead.
    final maxHeight = size.height * widget.frameHeightFraction;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * widget.cardAspectRatio;
    }

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
    // Rotation reshapes the preview, so the handle is compared whole.
    if (_lastSize == size && _lastCamera == camera) return;
    _lastSize = size;
    _lastCamera = camera;

    final preview = _previewRect(
      size,
      Size(camera.previewWidth.toDouble(), camera.previewHeight.toDouble()),
    );
    final frame = _cardRect(size);
    final card = widget.frameRegionPadding == 0
        ? frame
        : frame.inflate(frame.height * widget.frameRegionPadding);

    // Into the preview's own coordinates, then clipped to it: the preview
    // is drawn with BoxFit.cover, so it usually runs past the view.
    final left = ((card.left - preview.left) / preview.width).clamp(0.0, 1.0);
    final top = ((card.top - preview.top) / preview.height).clamp(0.0, 1.0);
    final right = ((card.right - preview.left) / preview.width).clamp(0.0, 1.0);
    final bottom = ((card.bottom - preview.top) / preview.height).clamp(
      0.0,
      1.0,
    );
    widget.controller.setRegionOfInterest(
      TextBox(left: left, top: top, width: right - left, height: bottom - top),
    );
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
                        child: RotatedBox(
                          quarterTurns: camera.quarterTurns,
                          child: Texture(textureId: camera.textureId),
                        ),
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
