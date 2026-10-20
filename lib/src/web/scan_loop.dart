import 'dart:async';

import '../channel/card_scanner_platform.dart';
import '../core/recognized_text.dart';
import 'scan_crop.dart';

/// A camera a [ScanLoop] can take cropped frames from.
abstract interface class ScanFrameSource {
  /// Frame size in pixels, or `null` while the camera has not reported one.
  ({int width, int height})? get frameSize;

  /// Takes [crop] out of the current frame, or returns `null` when there is
  /// nothing to take.
  ///
  /// The object returned is whatever the recognizer understands; the loop
  /// only passes it along and hands it back to [release].
  Future<Object?> grab(ScanCrop crop);

  /// Releases a frame [grab] returned, whether it was recognized or not.
  void release(Object frame);
}

/// An OCR engine a [ScanLoop] can send frames to.
abstract interface class ScanRecognizer {
  /// Recognizes the text in [frame], which came from [crop].
  ///
  /// Boxes come back normalized to the crop, so the parser reads them
  /// without knowing anything about the camera.
  Future<RecognizedFrame> recognize(Object frame, ScanCrop crop);

  /// Throws the engine away. The next [recognize] loads a fresh one.
  ///
  /// A browser worker can wedge: a decode that never returns leaves every
  /// later frame queued behind it. Nothing short of replacing it recovers.
  void restart();

  /// Releases the engine for good.
  Future<void> dispose();
}

/// Drives recognition: one frame at a time, as fast as the engine manages,
/// and gives up on an engine that has stopped answering.
///
/// This is where a browser differs most from a phone. A native engine
/// returns in about a hundred milliseconds and cannot really fail; a
/// browser engine takes about a second, runs in a worker that can wedge,
/// and is loaded from files that may not be there at all. Without a limit
/// on failures a scan would simply never finish, which is what a scanner
/// looks like when it is broken.
class ScanLoop {
  /// A loop pulling frames from [source] into [recognizer], reporting each
  /// result to [onFrame] and giving up through [onError].
  ///
  /// [interval] is the shortest gap between two attempts, [frameTimeout]
  /// how long one frame may take before it counts as failed, and
  /// [maxFailures] how many failures in a row mean the engine is gone.
  ScanLoop({
    required this.source,
    required this.recognizer,
    required this.onFrame,
    required this.onError,
    this.interval = const Duration(milliseconds: 200),
    this.frameTimeout = const Duration(seconds: 20),
    this.maxFailures = 3,
  }) : assert(maxFailures > 0);

  /// Where frames come from.
  final ScanFrameSource source;

  /// What reads them.
  final ScanRecognizer recognizer;

  /// Called with every frame that was recognized, even an empty one.
  final void Function(RecognizedFrame frame) onFrame;

  /// Called once when the engine has failed [maxFailures] times in a row.
  /// The loop has stopped by then.
  final void Function(CardScannerException error) onError;

  /// Shortest gap between two attempts. Recognition itself is slower than
  /// this, so it sets the pace; this only keeps an idle loop from spinning.
  final Duration interval;

  /// How long one frame may take before it counts as a failure.
  final Duration frameTimeout;

  /// Consecutive failures that mean the engine is gone rather than unlucky.
  final int maxFailures;

  /// Area of the frame to read, normalized. `null` reads all of it.
  TextBox? region;

  Timer? _timer;
  bool _busy = false;
  int _failures = 0;
  bool _running = false;

  /// Whether the loop is scheduling frames.
  bool get isRunning => _running;

  /// Failures since the last frame that worked, for a test to read.
  int get consecutiveFailures => _failures;

  /// Starts pulling frames. Does nothing when already running.
  void start() {
    if (_running) return;
    _running = true;
    _failures = 0;
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  /// Stops pulling frames. The engine is left loaded, so a scan that stops
  /// and starts again does not pay for it twice.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Stops and releases the engine.
  Future<void> dispose() async {
    stop();
    await recognizer.dispose();
  }

  Future<void> _tick() async {
    if (_busy || !_running) return;
    final size = source.frameSize;
    if (size == null) return;
    final crop = ScanCrop.from(
      region: region,
      videoWidth: size.width,
      videoHeight: size.height,
    );
    // The guide and the frame do not overlap, which happens for one layout
    // while a rotation settles. Nothing to read, and nothing wrong.
    if (crop == null) return;

    _busy = true;
    Object? frame;
    try {
      frame = await source.grab(crop);
      if (frame == null || !_running) return;
      final result = await recognizer
          .recognize(frame, crop)
          .timeout(frameTimeout);
      if (!_running) return;
      _failures = 0;
      onFrame(result);
    } catch (_) {
      if (!_running) return;
      _failures++;
      if (_failures >= maxFailures) _giveUp();
    } finally {
      if (frame != null) source.release(frame);
      _busy = false;
    }
  }

  void _giveUp() {
    stop();
    // The engine is replaced rather than retried in place: whatever wedged
    // it is still in there.
    recognizer.restart();
    onError(
      const CardScannerException(
        'ocrUnavailable',
        'The recognizer stopped responding',
      ),
    );
  }
}
