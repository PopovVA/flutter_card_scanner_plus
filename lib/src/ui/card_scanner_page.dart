import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channel/card_scanner_platform.dart';
import '../controller/card_scanner_controller.dart';
import '../core/card_scan_result.dart';
import '../core/frame_aggregator.dart';
import 'card_frame_overlay.dart';
import 'card_scanner_strings.dart';
import 'card_scanner_view.dart';

/// Ready-made full-screen scanner. Pops with the [CardScanResult] once
/// complete, or `null` if dismissed.
///
/// ```dart
/// final card = await CardScannerPage.show(context);
/// ```
class CardScannerPage extends StatefulWidget {
  const CardScannerPage({
    super.key,
    this.requirements = ScanRequirements.standard,
    this.title,
    this.overlayBuilder,
    this.foregroundColor,
    this.strings = CardScannerStrings.defaults,
    this.onOpenSettings,
    this.enableHaptics = false,
  });

  final ScanRequirements requirements;
  final String? title;
  final CardScannerOverlayBuilder? overlayBuilder;

  /// Color of the close button, torch toggle and title.
  ///
  /// When `null` (default) it follows the app theme: `AppBarTheme.foregroundColor`,
  /// then `AppBarTheme.iconTheme.color`, then white. Pass a color to override.
  final Color? foregroundColor;

  /// Text for the prompts and the error screen. Supply your own to
  /// translate the scanner.
  final CardScannerStrings strings;

  /// Called when the user asks to open the system settings after refusing
  /// camera access. Leave it `null` and no such button is offered.
  ///
  /// It is a callback rather than a dependency so that this package does
  /// not pull in a permissions plugin; `permission_handler`'s
  /// `openAppSettings` is the usual implementation.
  final VoidCallback? onOpenSettings;

  /// Play one light haptic each time the prompt changes.
  final bool enableHaptics;

  static Future<CardScanResult?> show(
    BuildContext context, {
    ScanRequirements requirements = ScanRequirements.standard,
    String? title,
    CardScannerOverlayBuilder? overlayBuilder,
    Color? foregroundColor,
    CardScannerStrings strings = CardScannerStrings.defaults,
    VoidCallback? onOpenSettings,
    bool enableHaptics = false,
  }) => Navigator.of(context).push<CardScanResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CardScannerPage(
        requirements: requirements,
        title: title,
        overlayBuilder: overlayBuilder,
        foregroundColor: foregroundColor,
        strings: strings,
        onOpenSettings: onOpenSettings,
        enableHaptics: enableHaptics,
      ),
    ),
  );

  @override
  State<CardScannerPage> createState() => _CardScannerPageState();
}

class _CardScannerPageState extends State<CardScannerPage> {
  late final CardScannerController _controller = CardScannerController(
    requirements: widget.requirements,
  );

  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (_controller.value.isComplete) _close(_controller.value.result);
  }

  /// Takes the preview off screen, then leaves.
  ///
  /// The texture is released as the controller is disposed, and the route's
  /// exit animation would otherwise keep drawing it while that happens.
  void _close([CardScanResult? result]) {
    if (_closing || !mounted) return;
    _controller.removeListener(_onChanged);
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBarTheme = Theme.of(context).appBarTheme;
    final fg =
        widget.foregroundColor ??
        appBarTheme.foregroundColor ??
        appBarTheme.iconTheme?.color ??
        Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        // Explicit icon and title colors: AppBarTheme.iconTheme and
        // titleTextStyle would otherwise override foregroundColor.
        iconTheme: IconThemeData(color: fg),
        actionsIconTheme: IconThemeData(color: fg),
        titleTextStyle: TextStyle(
          color: fg,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        systemOverlayStyle: fg.computeLuminance() > 0.5
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: widget.title == null ? null : Text(widget.title!),
        // Always reachable, whatever the camera is doing.
        leading: CloseButton(color: fg, onPressed: _close),
        actions: [
          ValueListenableBuilder<CardScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              color: fg,
              disabledColor: fg.withValues(alpha: 0.4),
              icon: Icon(state.torchEnabled ? Icons.flash_on : Icons.flash_off),
              onPressed: state.isRunning ? _controller.toggleTorch : null,
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.black),
          if (!_closing)
            CardScannerView(
              controller: _controller,
              overlayBuilder:
                  widget.overlayBuilder ??
                  (context, state, cardRect) => CardFrameOverlay(
                    state: state,
                    cardRect: cardRect,
                    requirements: widget.requirements,
                    strings: widget.strings,
                    enableHaptics: widget.enableHaptics,
                  ),
            ),
          ValueListenableBuilder<CardScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final error = state.error;
              if (error != null) return _error(error, fg);
              // Opening the camera takes a moment; an empty black screen
              // reads as a hang.
              if (!state.isRunning && state.camera == null && !_closing) {
                return Center(
                  child: CircularProgressIndicator(color: fg, strokeWidth: 2),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _error(CardScannerException error, Color fg) {
    final strings = widget.strings;
    final denied = error.isPermissionDenied;
    final message = switch (error.code) {
      CardScannerException.permissionDenied => strings.permissionDenied,
      CardScannerException.cameraInterrupted => strings.cameraBusy,
      _ => strings.cameraFailed,
    };

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied ? Icons.no_photography_outlined : Icons.error_outline,
                color: fg,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(color: fg, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(
                    onPressed: _controller.start,
                    style: TextButton.styleFrom(foregroundColor: fg),
                    child: Text(strings.retry),
                  ),
                  if (denied && widget.onOpenSettings != null)
                    FilledButton(
                      onPressed: widget.onOpenSettings,
                      child: Text(strings.openSettings),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
