import 'dart:typed_data';

import 'channel/card_scanner_platform.dart';
import 'core/card_frame_parser.dart';
import 'core/card_scan_result.dart';
import 'core/frame_aggregator.dart';
import 'core/recognized_text.dart';
import 'web/ocr_engine.dart';

/// Static entry points that don't need a live camera.
abstract final class CardScanner {
  /// Recognizes a card in an encoded image (JPEG, PNG, HEIC…), e.g. a photo
  /// picked from the gallery.
  ///
  /// A single image gives a single frame, so no multi-frame voting is
  /// applied: [CardScanResult.isComplete] reflects whether the fields
  /// required by [requirements] were found in that one image.
  ///
  /// Throws [CardScannerException] (`invalidImage`) if decoding fails. In
  /// a browser it can also throw [CardScannerException.tooSlow], when
  /// WebAssembly runs too slowly there for the image to be read at all.
  static Future<CardScanResult> scanImage(
    Uint8List bytes, {
    ScanRequirements requirements = ScanRequirements.standard,
    TextBox? regionOfInterest,
  }) async {
    final frame = await CardScannerPlatform.instance.recognizeImage(
      bytes,
      regionOfInterest: regionOfInterest,
    );
    return resultFromFrame(CardFrameParser.parse(frame), requirements);
  }

  /// What the browser's OCR engine reports each time a scan loads it:
  /// which build is running, WebGPU or WebAssembly, how long the load
  /// took, and how fast WebAssembly is.
  ///
  /// For a host app that wants to see which path its users are on. A
  /// report carries no card data. Nothing is ever emitted on iOS or
  /// Android, where the system's own engine does the reading.
  ///
  /// ```dart
  /// CardScanner.engineReports.listen((report) {
  ///   analytics.log('card_scanner_engine', {
  ///     'backend': report.backend.name,
  ///     'benchmarkMs': report.benchmark?.inMilliseconds,
  ///     'tooSlow': report.tooSlow,
  ///   });
  /// });
  /// ```
  static Stream<OcrEngineReport> get engineReports => OcrEngineReports.stream;

  /// The most recent of [engineReports], or `null` when no scan has
  /// loaded the browser engine yet.
  static OcrEngineReport? get lastEngineReport => OcrEngineReports.last;

  /// Converts one parsed frame into a result without aggregation.
  static CardScanResult resultFromFrame(
    FrameParseResult frame,
    ScanRequirements requirements,
  ) {
    final found = {
      if (frame.pan != null) CardField.number,
      if (frame.expiry != null) CardField.expiry,
      if (frame.name != null) CardField.name,
    };
    return CardScanResult(
      number: frame.pan?.number,
      brand: frame.pan?.brand,
      expiryMonth: frame.expiry?.month,
      expiryYear: frame.expiry?.year,
      cardholderName: frame.name?.name,
      // A single image has no "later frames": only required fields matter.
      isComplete: requirements.requiredSatisfied(found),
    );
  }
}
