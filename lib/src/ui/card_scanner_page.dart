import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/card_scanner_controller.dart';
import '../core/card_scan_result.dart';
import '../core/frame_aggregator.dart';
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
  });

  final ScanRequirements requirements;
  final String? title;
  final CardScannerOverlayBuilder? overlayBuilder;

  /// Color of the close button, torch toggle and title.
  ///
  /// When `null` (default) it follows the app theme: `AppBarTheme.foregroundColor`,
  /// then `AppBarTheme.iconTheme.color`, then white. Pass a color to override.
  final Color? foregroundColor;

  static Future<CardScanResult?> show(
    BuildContext context, {
    ScanRequirements requirements = ScanRequirements.standard,
    String? title,
    CardScannerOverlayBuilder? overlayBuilder,
    Color? foregroundColor,
  }) => Navigator.of(context).push<CardScanResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CardScannerPage(
        requirements: requirements,
        title: title,
        overlayBuilder: overlayBuilder,
        foregroundColor: foregroundColor,
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final state = _controller.value;
    if (state.isComplete && mounted) {
      _controller.removeListener(_onChanged);
      Navigator.of(context).pop(state.result);
    }
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
        leading: CloseButton(color: fg),
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
      body: ValueListenableBuilder<CardScannerState>(
        valueListenable: _controller,
        builder: (context, state, child) {
          final error = state.error;
          if (error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.isPermissionDenied
                      ? 'Camera access is required to scan a card.'
                      : 'Camera error: ${error.message ?? error.code}',
                  style: TextStyle(color: fg),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return child!;
        },
        child: CardScannerView(
          controller: _controller,
          overlayBuilder: widget.overlayBuilder,
        ),
      ),
    );
  }
}
