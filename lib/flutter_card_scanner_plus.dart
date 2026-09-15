/// On-device bank card scanner for Flutter.
///
/// Recognizes Visa, Mastercard and American Express cards using the
/// platform OCR engine (Vision on iOS, ML Kit on Android). Frames never
/// leave the device.
library;

export 'src/core/card_brand.dart';
export 'src/core/card_frame_parser.dart' show CardFrameParser, FrameParseResult;
export 'src/core/card_scan_result.dart';
export 'src/core/expiry_parser.dart' show ExpiryCandidate, ExpiryParser;
export 'src/core/frame_aggregator.dart';
export 'src/core/luhn.dart';
export 'src/core/name_parser.dart' show NameCandidate, NameParser;
export 'src/core/pan_parser.dart' show PanCandidate, PanParser;
export 'src/core/recognized_text.dart';
