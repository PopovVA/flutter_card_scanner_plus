import 'dart:typed_data';

import 'channel/card_scanner_platform.dart';
import 'core/card_frame_parser.dart';
import 'core/card_scan_result.dart';
import 'core/frame_aggregator.dart';
import 'core/recognized_text.dart';

/// Static entry points that don't need a live camera.
abstract final class CardScanner {
  /// Recognizes a card in an encoded image (JPEG, PNG, HEIC…), e.g. a photo
  /// picked from the gallery.
  ///
  /// A single image gives a single frame, so no multi-frame voting is
  /// applied: [CardScanResult.isComplete] reflects whether the fields
  /// required by [requirements] were found in that one image.
  ///
  /// Throws [CardScannerException] (`invalidImage`) if decoding fails.
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
