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
    this.confirming = const {},
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

  /// Fields that have a candidate but not yet enough agreement between
  /// frames. Shown as progress rather than as a result.
  final Set<CardField> confirming;

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
    Set<CardField>? confirming,
    CardScannerException? error,
    bool clearError = false,
  }) => CardScannerState(
    camera: clearCamera ? null : (camera ?? this.camera),
    isRunning: isRunning ?? this.isRunning,
    torchEnabled: torchEnabled ?? this.torchEnabled,
    result: result ?? this.result,
    lastFrame: lastFrame ?? this.lastFrame,
    confirming: confirming ?? this.confirming,
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
    ScanSession? session,
    @visibleForTesting CardScannerPlatform? platform,
  }) : _platform = platform ?? CardScannerPlatform.instance,
       _session = session ?? FrameAggregator(requirements: requirements),
       super(CardScannerState.initial);

  /// Rules the default session applies. Ignored when a [ScanSession] was
  /// passed to the constructor, since that session carries its own.
  final ScanRequirements requirements;

  /// Stop the camera automatically once the result is complete.
  final bool stopWhenComplete;

  final CardScannerPlatform _platform;
  final ScanSession _session;
  final _results = StreamController<CardScanResult>.broadcast();
  StreamSubscription<RecognizedFrame>? _frames;
  StreamSubscription<CameraHandle>? _preview;
  Completer<CardScanResult>? _once;
  TextBox? _regionOfInterest;
  DateTime? _reshapedAt;
  bool _disposed = false;

  /// How long frames are dropped after a rotation if the new region of
  /// interest is never acknowledged. Without a ceiling a controller driven
  /// without a view, which is what sets the region, would stall for good.
  static const _settleTimeout = Duration(milliseconds: 400);

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
      // A device rotation reshapes the preview; the view watches this to
      // redraw the texture and move the region of interest with it.
      _preview = _platform.previewUpdates.listen((handle) {
        if (!value.isRunning) return;
        _reshapedAt = DateTime.now();
        value = value.copyWith(camera: handle);
      });
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
    await _preview?.cancel();
    _preview = null;
    await _platform.stop();
    _reshapedAt = null;
    // dispose() stops the camera too, and the platform call above gives the
    // notifier time to be torn down before this returns.
    if (_disposed) return;
    value = value.copyWith(
      isRunning: false,
      torchEnabled: false,
      clearCamera: true,
    );
  }

  /// Clears the accumulated result so a new card can be scanned.
  void reset() {
    _session.reset();
    value = value.copyWith(
      result: CardScanResult.empty,
      lastFrame: FrameParseResult.empty,
      confirming: const {},
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
    if (!value.isRunning) return;
    await _platform.setRegionOfInterest(box);
    // The region now matches the preview again, so frames can be trusted.
    _reshapedAt = null;
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

    // A frame recognized before a rotation reached the camera describes the
    // previous geometry: its boxes are in the old orientation and were
    // filtered by the old region of interest. Scoring it would move a field
    // relative to the number and could confirm text from off the card.
    final reshaped = _reshapedAt;
    if (reshaped != null) {
      if (DateTime.now().difference(reshaped) < _settleTimeout) return;
      _reshapedAt = null;
    }

    final parsed = CardFrameParser.parse(frame);
    final result = _session.add(parsed);
    final changed = result != value.result;
    value = value.copyWith(
      result: result,
      lastFrame: parsed,
      confirming: _session.confirming,
    );

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
