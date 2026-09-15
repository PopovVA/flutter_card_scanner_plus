import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channel/card_scanner_platform.dart';
import '../core/card_frame_parser.dart';
import '../core/card_scan_result.dart';
import '../core/frame_aggregator.dart';
import '../core/recognized_text.dart';

/// Snapshot of the scanner, exposed through [CardScannerController.value].
@immutable
class CardScannerState {
  const CardScannerState({
    this.camera,
    this.isRunning = false,
    this.torchEnabled = false,
    this.result = CardScanResult.empty,
    this.lastFrame = FrameParseResult.empty,
    this.error,
  });

  static const initial = CardScannerState();

  /// Preview texture, available while [isRunning].
  final CameraHandle? camera;
  final bool isRunning;
  final bool torchEnabled;

  /// Aggregated result so far. Check [CardScanResult.isComplete].
  final CardScanResult result;

  /// Raw fields from the most recent frame — useful for live highlighting.
  final FrameParseResult lastFrame;

  /// Set when the camera could not be started.
  final CardScannerException? error;

  bool get isComplete => result.isComplete;

  CardScannerState copyWith({
    CameraHandle? camera,
    bool clearCamera = false,
    bool? isRunning,
    bool? torchEnabled,
    CardScanResult? result,
    FrameParseResult? lastFrame,
    CardScannerException? error,
    bool clearError = false,
  }) => CardScannerState(
    camera: clearCamera ? null : (camera ?? this.camera),
    isRunning: isRunning ?? this.isRunning,
    torchEnabled: torchEnabled ?? this.torchEnabled,
    result: result ?? this.result,
    lastFrame: lastFrame ?? this.lastFrame,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Drives the camera and OCR pipeline and exposes results.
///
/// Listen to [value] (it's a [ValueNotifier]) or to [results]. For a
/// one-shot flow use [scanOnce].
class CardScannerController extends ValueNotifier<CardScannerState> {
  CardScannerController({
    this.requirements = ScanRequirements.standard,
    this.stopWhenComplete = true,
    @visibleForTesting CardScannerPlatform? platform,
  }) : _platform = platform ?? CardScannerPlatform.instance,
       _aggregator = FrameAggregator(requirements: requirements),
       super(CardScannerState.initial);

  final ScanRequirements requirements;

  /// Stop the camera automatically once the result is complete.
  final bool stopWhenComplete;

  final CardScannerPlatform _platform;
  final FrameAggregator _aggregator;
  final _results = StreamController<CardScanResult>.broadcast();
  StreamSubscription<RecognizedFrame>? _frames;
  Completer<CardScanResult>? _once;
  TextBox? _regionOfInterest;
  bool _disposed = false;

  /// Emits every time the aggregated result changes.
  Stream<CardScanResult> get results => _results.stream;

  /// Starts the camera. Safe to call when already running.
  Future<void> start() async {
    if (value.isRunning || _disposed) return;
    value = value.copyWith(clearError: true);
    try {
      final camera = await _platform.start(regionOfInterest: _regionOfInterest);
      if (_disposed) {
        await _platform.stop();
        return;
      }
      _frames = _platform.frames.listen(
        _onFrame,
        onError: (Object e) {
          value = value.copyWith(
            error: CardScannerException('frameError', '$e'),
          );
        },
      );
      value = value.copyWith(camera: camera, isRunning: true);
    } on CardScannerException catch (e) {
      value = value.copyWith(error: e);
      _once?.completeError(e);
      _once = null;
    }
  }

  /// Stops the camera and releases the texture. Keeps the current result.
  Future<void> stop() async {
    if (!value.isRunning) return;
    await _frames?.cancel();
    _frames = null;
    await _platform.stop();
    value = value.copyWith(
      isRunning: false,
      torchEnabled: false,
      clearCamera: true,
    );
  }

  /// Clears the accumulated result so a new card can be scanned.
  void reset() {
    _aggregator.reset();
    value = value.copyWith(
      result: CardScanResult.empty,
      lastFrame: FrameParseResult.empty,
    );
  }

  Future<void> setTorch(bool enabled) async {
    if (!value.isRunning) return;
    await _platform.setTorch(enabled);
    value = value.copyWith(torchEnabled: enabled);
  }

  Future<void> toggleTorch() => setTorch(!value.torchEnabled);

  /// Limits OCR to [box] (normalized preview coordinates). The view sets
  /// this automatically to match the card frame.
  Future<void> setRegionOfInterest(TextBox box) async {
    _regionOfInterest = box;
    if (value.isRunning) await _platform.setRegionOfInterest(box);
  }

  /// Starts scanning (if needed) and completes with the first complete
  /// result. Throws [CardScannerException] if the camera fails.
  Future<CardScanResult> scanOnce() {
    if (value.isComplete) return Future.value(value.result);
    final completer = _once ??= Completer<CardScanResult>();
    if (!value.isRunning) unawaited(start());
    return completer.future;
  }

  void _onFrame(RecognizedFrame frame) {
    if (value.isComplete) return;

    final parsed = CardFrameParser.parse(frame);
    final result = _aggregator.add(parsed);
    final changed = result != value.result;
    value = value.copyWith(result: result, lastFrame: parsed);

    if (changed) _results.add(result);
    if (result.isComplete) {
      _once?.complete(result);
      _once = null;
      if (stopWhenComplete) unawaited(stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    _results.close();
    _once?.completeError(const CardScannerException('disposed'));
    super.dispose();
  }
}
