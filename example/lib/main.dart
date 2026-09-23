import 'package:flutter/material.dart';
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Card Scanner Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CardScanResult? _result;

  Future<void> _scan({required ScanRequirements requirements}) async {
    final result = await CardScannerPage.show(
      context,
      requirements: requirements,
      title: 'Scan card',
    );
    if (!mounted) return;
    setState(() => _result = result);
  }

  Future<void> _scanPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final result = await CardScanner.scanImage(
        bytes,
        requirements: ScanRequirements.full,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on CardScannerException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _readNfc() async {
    if (!await CardNfcReader.isAvailable()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NFC is off or not supported here')),
      );
      return;
    }
    try {
      final card = await CardNfcReader.read();
      if (!mounted) return;
      setState(() => _result = card);
    } on CardNfcException catch (e) {
      if (!mounted || e.isCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _probeNfc() async {
    if (!await CardNfcProbe.isAvailable()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NFC is off or not supported here')),
      );
      return;
    }
    final report = await CardNfcProbe.run();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(report.isSuccess ? 'Card answered' : 'No card data'),
        content: SingleChildScrollView(
          child: SelectableText(
            report.summary,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_card_scanner_plus')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => _scan(requirements: ScanRequirements.standard),
              icon: const Icon(Icons.credit_card),
              label: const Text('Scan (number + expiry, name if quick)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _scan(requirements: ScanRequirements.numberOnly),
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Scan number only'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _scan(requirements: ScanRequirements.full),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Scan all three (wait for name)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomOverlayPage(),
                ),
              ),
              icon: const Icon(Icons.brush_outlined),
              label: const Text('Custom overlay'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _scanPhoto,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Scan from photo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _readNfc,
              icon: const Icon(Icons.nfc),
              label: const Text('Tap card (NFC)'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _probeNfc,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('NFC probe (diagnostics)'),
            ),
            const SizedBox(height: 32),
            if (r == null)
              const Text('No card scanned yet', textAlign: TextAlign.center)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.brand?.displayName ?? 'Unknown brand',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        r.formattedNumber ?? '—',
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expiry: ${r.formattedExpiry ?? '—'}'
                        '${r.isExpired() ? '  (expired)' : ''}',
                      ),
                      Text('Name: ${r.cardholderName ?? '—'}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows how to draw your own UI over the preview with `overlayBuilder`.
class CustomOverlayPage extends StatefulWidget {
  const CustomOverlayPage({super.key});

  @override
  State<CustomOverlayPage> createState() => _CustomOverlayPageState();
}

class _CustomOverlayPageState extends State<CustomOverlayPage> {
  final _controller = CardScannerController(stopWhenComplete: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CardScannerView(
        controller: _controller,
        frameAlignment: Alignment.center,
        overlayBuilder: (context, state, cardRect) {
          final frame = state.lastFrame;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: cardRect,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: state.isComplete
                          ? Colors.greenAccent
                          : Colors.amber,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 48,
                child: Column(
                  children: [
                    _Chip('PAN', frame.pan?.number, state.result.number),
                    _Chip(
                      'EXP',
                      frame.expiry?.formatted,
                      state.result.formattedExpiry,
                    ),
                    _Chip(
                      'NAME',
                      frame.name?.name,
                      state.result.cardholderName,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton(
                          onPressed: _controller.reset,
                          child: const Text('Reset'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.live, this.stable);

  final String label;
  final String? live;
  final String? stable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Text(
              stable ?? live ?? '…',
              style: TextStyle(
                color: stable != null ? Colors.greenAccent : Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
