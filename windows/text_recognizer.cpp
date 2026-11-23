#include "text_recognizer.h"

#include <windows.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace card_scanner {

namespace {

namespace imaging = winrt::Windows::Graphics::Imaging;
namespace ocr = winrt::Windows::Media::Ocr;
namespace streams = winrt::Windows::Storage::Streams;

// WinRT needs an apartment on every thread that touches it, and the
// threads here are ours: the capture thread and whatever thread answers a
// one-shot call. Initializing twice on one thread is an error, so this
// remembers, and a thread the host already made an STA keeps that.
void EnsureApartment() {
  static thread_local bool initialized = false;
  if (initialized) return;
  initialized = true;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
  } catch (const winrt::hresult_error&) {
    // Already initialized, in either mode. Both work for what follows.
  }
}

ocr::OcrEngine Engine() {
  ocr::OcrEngine engine = ocr::OcrEngine::TryCreateFromUserProfileLanguages();
  if (engine) return engine;
  try {
    return ocr::OcrEngine::TryCreateFromLanguage(
        winrt::Windows::Globalization::Language(L"en-US"));
  } catch (const winrt::hresult_error&) {
    return nullptr;
  }
}

struct Crop {
  std::vector<uint8_t> pixels;
  int width = 0;
  int height = 0;
  int left = 0;
  int top = 0;
};

// Copies the region of interest into its own tightly packed buffer. The
// whole frame is copied when there is no region, because the engine wants
// a buffer it owns either way.
Crop CropFrame(const uint8_t* bgra, int width, int height,
               const std::optional<NormalizedBox>& roi) {
  Crop crop;
  crop.left = 0;
  crop.top = 0;
  crop.width = width;
  crop.height = height;

  if (roi.has_value()) {
    int left = static_cast<int>(std::lround(roi->left * width));
    int top = static_cast<int>(std::lround(roi->top * height));
    int right = static_cast<int>(std::lround((roi->left + roi->width) * width));
    int bottom = static_cast<int>(std::lround((roi->top + roi->height) * height));
    left = std::clamp(left, 0, width - 1);
    top = std::clamp(top, 0, height - 1);
    right = std::clamp(right, left + 1, width);
    bottom = std::clamp(bottom, top + 1, height);
    crop.left = left;
    crop.top = top;
    crop.width = right - left;
    crop.height = bottom - top;
  }

  crop.pixels.resize(static_cast<size_t>(crop.width) * crop.height * 4);
  for (int y = 0; y < crop.height; y++) {
    const uint8_t* source =
        bgra + (static_cast<size_t>(crop.top + y) * width + crop.left) * 4;
    uint8_t* target = crop.pixels.data() + static_cast<size_t>(y) * crop.width * 4;
    memcpy(target, source, static_cast<size_t>(crop.width) * 4);
  }
  return crop;
}

streams::IBuffer BufferFrom(const std::vector<uint8_t>& bytes) {
  return winrt::Windows::Security::Cryptography::CryptographicBuffer::
      CreateFromByteArray(
          winrt::array_view<const uint8_t>(bytes.data(), bytes.data() + bytes.size()));
}

// Turns one OCR result into lines in whole-image normalized coordinates.
// `origin` and `scale` undo the crop: a box is reported where it sits on
// the frame, not where it sat in the piece that was read.
std::vector<RecognizedLine> LinesFrom(const ocr::OcrResult& result, double originX,
                                      double originY, double imageWidth,
                                      double imageHeight) {
  std::vector<RecognizedLine> lines;
  if (imageWidth <= 0 || imageHeight <= 0) return lines;

  for (const ocr::OcrLine& line : result.Lines()) {
    double left = 0, top = 0, right = 0, bottom = 0;
    bool first = true;
    for (const ocr::OcrWord& word : line.Words()) {
      auto rect = word.BoundingRect();
      if (first) {
        left = rect.X;
        top = rect.Y;
        right = rect.X + rect.Width;
        bottom = rect.Y + rect.Height;
        first = false;
        continue;
      }
      left = (std::min)(left, static_cast<double>(rect.X));
      top = (std::min)(top, static_cast<double>(rect.Y));
      right = (std::max)(right, static_cast<double>(rect.X + rect.Width));
      bottom = (std::max)(bottom, static_cast<double>(rect.Y + rect.Height));
    }
    if (first) continue;

    RecognizedLine recognized;
    recognized.text = winrt::to_string(line.Text());
    recognized.box.left = (originX + left) / imageWidth;
    recognized.box.top = (originY + top) / imageHeight;
    recognized.box.width = (right - left) / imageWidth;
    recognized.box.height = (bottom - top) / imageHeight;
    lines.push_back(std::move(recognized));
  }
  return lines;
}

}  // namespace

bool TextRecognizer::Available() {
  EnsureApartment();
  try {
    return Engine() != nullptr;
  } catch (const winrt::hresult_error&) {
    return false;
  }
}

std::vector<RecognizedLine> TextRecognizer::Recognize(
    const uint8_t* bgra, int width, int height,
    const std::optional<NormalizedBox>& roi) {
  EnsureApartment();
  if (bgra == nullptr || width <= 0 || height <= 0) return {};

  try {
    ocr::OcrEngine engine = Engine();
    if (!engine) return {};

    Crop crop = CropFrame(bgra, width, height, roi);
    const uint32_t limit = ocr::OcrEngine::MaxImageDimension();
    if (crop.width <= 0 || crop.height <= 0 ||
        static_cast<uint32_t>(crop.width) > limit ||
        static_cast<uint32_t>(crop.height) > limit) {
      return {};
    }

    imaging::SoftwareBitmap bitmap = imaging::SoftwareBitmap::CreateCopyFromBuffer(
        BufferFrom(crop.pixels), imaging::BitmapPixelFormat::Bgra8, crop.width,
        crop.height);
    ocr::OcrResult result = engine.RecognizeAsync(bitmap).get();
    return LinesFrom(result, crop.left, crop.top, width, height);
  } catch (const winrt::hresult_error&) {
    return {};
  }
}

std::optional<std::vector<RecognizedLine>> TextRecognizer::RecognizeEncoded(
    const std::vector<uint8_t>& bytes, const std::optional<NormalizedBox>& roi) {
  EnsureApartment();
  try {
    ocr::OcrEngine engine = Engine();
    if (!engine) return std::vector<RecognizedLine>{};

    streams::InMemoryRandomAccessStream stream;
    streams::DataWriter writer(stream);
    writer.WriteBuffer(BufferFrom(bytes));
    writer.StoreAsync().get();
    writer.FlushAsync().get();
    writer.DetachStream();
    stream.Seek(0);

    imaging::BitmapDecoder decoder = imaging::BitmapDecoder::CreateAsync(stream).get();
    imaging::SoftwareBitmap bitmap =
        decoder
            .GetSoftwareBitmapAsync(imaging::BitmapPixelFormat::Bgra8,
                                    imaging::BitmapAlphaMode::Premultiplied)
            .get();

    const int width = bitmap.PixelWidth();
    const int height = bitmap.PixelHeight();
    if (width <= 0 || height <= 0) return std::nullopt;

    // The region of interest is cropped by reading the decoded pixels
    // rather than the stream, so an image that arrives rotated by its
    // EXIF tag is cropped the way it is seen.
    if (roi.has_value()) {
      const uint32_t size = static_cast<uint32_t>(width) * height * 4;
      streams::Buffer buffer(size);
      buffer.Length(size);
      bitmap.CopyToBuffer(buffer);
      std::vector<uint8_t> pixels(size);
      streams::DataReader::FromBuffer(buffer).ReadBytes(
          winrt::array_view<uint8_t>(pixels.data(), pixels.data() + size));
      return Recognize(pixels.data(), width, height, roi);
    }

    ocr::OcrResult result = engine.RecognizeAsync(bitmap).get();
    return LinesFrom(result, 0, 0, width, height);
  } catch (const winrt::hresult_error&) {
    return std::nullopt;
  }
}

}  // namespace card_scanner
