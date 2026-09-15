import 'package:flutter/material.dart';

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
  });

  final ScanRequirements requirements;
  final String? title;
  final CardScannerOverlayBuilder? overlayBuilder;

  static Future<CardScanResult?> show(
    BuildContext context, {
    ScanRequirements requirements = ScanRequirements.standard,
    String? title,
    CardScannerOverlayBuilder? overlayBuilder,
  }) => Navigator.of(context).push<CardScanResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CardScannerPage(
        requirements: requirements,
        title: title,
        overlayBuilder: overlayBuilder,
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
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.title == null ? null : Text(widget.title!),
        leading: const CloseButton(),
        actions: [
          ValueListenableBuilder<CardScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
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
                  style: const TextStyle(color: Colors.white),
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
