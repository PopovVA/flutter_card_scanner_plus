import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';

/// A camera that never opens, but lets a test push rotations.
class FakeScannerPlatform implements CardScannerPlatform {
  FakeScannerPlatform(this.handle);

  final CameraHandle handle;
  final _frames = StreamController<RecognizedFrame>.broadcast();
  final _previews = StreamController<CameraHandle>.broadcast();
  final _errors = StreamController<CardScannerException>.broadcast();
  final regions = <TextBox>[];
  bool started = false;
  int starts = 0;
  int stops = 0;

  /// Completes a stop only when a test says so, which is how a reopen that
  /// races the teardown is reproduced.
  Completer<void>? holdStop;

  /// Makes the next start fail, for the error screen.
  CardScannerException? failStartWith;

  /// Completes a start only when a test says so, for the opening state.
  Completer<void>? holdStart;

  void rotate(CameraHandle next) => _previews.add(next);

  /// Pushes one recognized frame, as the platform would.
  void recognize(List<TextLine> lines) =>
      _frames.add(RecognizedFrame(lines: lines));

  /// Reports a camera that failed after it started.
  void fail(CardScannerException error) => _errors.add(error);

  @override
  Future<CameraHandle> start({TextBox? regionOfInterest}) async {
    starts++;
    final hold = holdStart;
    if (hold != null) await hold.future;
    final failure = failStartWith;
    if (failure != null) throw failure;
    if (started) {
      throw const CardScannerException(CardScannerException.alreadyRunning);
    }
    started = true;
    return handle;
  }

  @override
  Future<void> stop() async {
    stops++;
    final hold = holdStop;
    if (hold != null) await hold.future;
    started = false;
  }

  @override
  Future<void> setTorch(bool enabled) async {}

  @override
  Future<void> setRegionOfInterest(TextBox box) async => regions.add(box);

  @override
  Stream<RecognizedFrame> get frames => _frames.stream;

  @override
  Stream<CameraHandle> get previewUpdates => _previews.stream;

  @override
  Stream<CardScannerException> get errors => _errors.stream;

  @override
  Future<RecognizedFrame> recognizeImage(
    Uint8List bytes, {
    TextBox? regionOfInterest,
  }) async => RecognizedFrame.empty;
}
