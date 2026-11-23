#ifndef FLUTTER_PLUGIN_CARD_SCANNER_TEXT_RECOGNIZER_H_
#define FLUTTER_PLUGIN_CARD_SCANNER_TEXT_RECOGNIZER_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace card_scanner {

// A rectangle in normalized (0..1) image coordinates with a top-left
// origin, which is what the method channel carries in both directions.
struct NormalizedBox {
  double left = 0;
  double top = 0;
  double width = 0;
  double height = 0;
};

struct RecognizedLine {
  std::string text;
  NormalizedBox box;
  // Windows OCR does not score a line, so this is always 1. The Dart side
  // treats a missing score as certain anyway, and inventing one would put
  // a number in front of people that means nothing.
  double confidence = 1.0;
};

// Reads text with the OCR engine Windows ships with (Windows.Media.Ocr).
// Nothing is downloaded and nothing is sent anywhere.
class TextRecognizer {
 public:
  // Whether this machine has an OCR engine for any installed language.
  // A Windows install with no OCR language pack has none, and a scanner
  // that says so beats one that returns empty frames forever.
  static bool Available();

  // `bgra` is tightly packed, 4 bytes per pixel. `roi` limits reading to
  // part of the frame; boxes come back in whole-frame coordinates either
  // way, so the caller never has to undo the crop.
  static std::vector<RecognizedLine> Recognize(
      const uint8_t* bgra, int width, int height,
      const std::optional<NormalizedBox>& roi);

  // One-shot recognition of an encoded image (JPEG, PNG, and whatever
  // else the system imaging codecs read).
  static std::optional<std::vector<RecognizedLine>> RecognizeEncoded(
      const std::vector<uint8_t>& bytes,
      const std::optional<NormalizedBox>& roi);
};

}  // namespace card_scanner

#endif  // FLUTTER_PLUGIN_CARD_SCANNER_TEXT_RECOGNIZER_H_
