import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';

/// A camera that never opens, but lets a test push rotations.
class FakeScannerPlatform implements CardScannerPlatform {
  FakeScannerPlatform(this.handle);

  final CameraHandle handle;
  final _frames = StreamController<RecognizedFrame>.broadcast();
  final _previews = StreamController<CameraHandle>.broadcast();
  final regions = <TextBox>[];
  bool started = false;

  void rotate(CameraHandle next) => _previews.add(next);

  @override
  Future<CameraHandle> start({TextBox? regionOfInterest}) async {
    started = true;
    return handle;
  }

  @override
  Future<void> stop() async => started = false;

  @override
  Future<void> setTorch(bool enabled) async {}

  @override
  Future<void> setRegionOfInterest(TextBox box) async => regions.add(box);

  @override
  Stream<RecognizedFrame> get frames => _frames.stream;

  @override
  Stream<CameraHandle> get previewUpdates => _previews.stream;

  @override
  Future<RecognizedFrame> recognizeImage(
    Uint8List bytes, {
    TextBox? regionOfInterest,
  }) async => RecognizedFrame.empty;
}
