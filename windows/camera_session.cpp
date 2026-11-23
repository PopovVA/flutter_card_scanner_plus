#include "camera_session.h"

#include <mferror.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>

#include "camera_catalog.h"

namespace card_scanner {

namespace {

using Microsoft::WRL::ComPtr;

// How often a frame is read. The camera delivers 30 a second and the
// engine cannot keep up with that, nor does a card need it: eight reads a
// second is what the other platforms settled on.
constexpr auto kMinInterval = std::chrono::milliseconds(120);

}  // namespace

CameraSession::CameraSession(flutter::TextureRegistrar* textures,
                             std::wstring camera_id)
    : textures_(textures), camera_id_(std::move(camera_id)) {}

CameraSession::~CameraSession() {
  Stop();
  if (texture_id_ >= 0 && textures_ != nullptr) {
    textures_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
  if (source_) source_->Shutdown();
}

std::unique_ptr<CameraSession> CameraSession::Open(
    flutter::TextureRegistrar* textures, const std::wstring& cameraId,
    std::string* code, std::string* message) {
  std::optional<CameraInfo> camera = CameraCatalog::Camera(cameraId);
  if (!camera.has_value()) {
    *code = "noCamera";
    *message = "No camera available";
    return nullptr;
  }

  std::unique_ptr<CameraSession> session(
      new CameraSession(textures, camera->id));

  ComPtr<IMFAttributes> attributes;
  if (FAILED(MFCreateAttributes(&attributes, 2)) ||
      FAILED(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                 MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID)) ||
      FAILED(attributes->SetString(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
          camera->id.c_str()))) {
    *code = "cameraError";
    *message = "Could not describe the camera";
    return nullptr;
  }

  HRESULT opened = MFCreateDeviceSource(attributes.Get(), &session->source_);
  if (opened == E_ACCESSDENIED) {
    // Settings > Privacy > Camera, with "Let desktop apps access your
    // camera" off. There is no prompt to raise from a desktop app, so the
    // only way out is the settings page.
    *code = "permissionDenied";
    *message = "Camera access is turned off for desktop apps";
    return nullptr;
  }
  if (FAILED(opened)) {
    *code = "cameraError";
    *message = "Could not open the camera";
    return nullptr;
  }

  ComPtr<IMFAttributes> reader_attributes;
  if (FAILED(MFCreateAttributes(&reader_attributes, 1)) ||
      FAILED(reader_attributes->SetUINT32(
          MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE)) ||
      FAILED(MFCreateSourceReaderFromMediaSource(
          session->source_.Get(), reader_attributes.Get(), &session->reader_))) {
    *code = "cameraError";
    *message = "Could not read from the camera";
    return nullptr;
  }

  // Ask for plain 32-bit colour and let the reader's video processor do
  // whatever conversion the camera's own format needs. Every webcam can
  // be converted to this; not every one produces it.
  ComPtr<IMFMediaType> wanted;
  if (FAILED(MFCreateMediaType(&wanted)) ||
      FAILED(wanted->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)) ||
      FAILED(wanted->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32)) ||
      FAILED(session->reader_->SetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
          wanted.Get()))) {
    *code = "cameraError";
    *message = "The camera has no format this can read";
    return nullptr;
  }

  ComPtr<IMFMediaType> current;
  UINT32 width = 0;
  UINT32 height = 0;
  if (FAILED(session->reader_->GetCurrentMediaType(
          static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &current)) ||
      FAILED(MFGetAttributeSize(current.Get(), MF_MT_FRAME_SIZE, &width, &height)) ||
      width == 0 || height == 0) {
    *code = "cameraError";
    *message = "The camera did not say what size its frames are";
    return nullptr;
  }
  session->width_ = static_cast<int>(width);
  session->height_ = static_cast<int>(height);

  // RGB32 is usually bottom-up, which shows as a negative stride. The
  // sign is the only thing that matters here; the copy uses the width.
  INT32 stride = 0;
  if (FAILED(current->GetINT32(MF_MT_DEFAULT_STRIDE, &stride)) || stride == 0) {
    LONG computed = 0;
    if (SUCCEEDED(MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width,
                                                 &computed))) {
      stride = static_cast<INT32>(computed);
    } else {
      stride = static_cast<INT32>(width) * 4;
    }
  }
  session->stride_ = stride;

  session->rgba_.assign(static_cast<size_t>(width) * height * 4, 0);

  session->texture_ =
      std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
          [self = session.get()](size_t width, size_t height) {
            return self->CopyPixelBuffer(width, height);
          }));
  session->texture_id_ = textures->RegisterTexture(session->texture_.get());

  return session;
}

void CameraSession::SetHandlers(FrameHandler on_frame, ErrorHandler on_error) {
  on_frame_ = std::move(on_frame);
  on_error_ = std::move(on_error);
}

void CameraSession::SetRegionOfInterest(const std::optional<NormalizedBox>& roi) {
  std::lock_guard<std::mutex> lock(roi_mutex_);
  roi_ = roi;
}

void CameraSession::Start() {
  if (running_.exchange(true)) return;
  capture_thread_ = std::thread([this] { CaptureLoop(); });
  recognize_thread_ = std::thread([this] { RecognizeLoop(); });
}

void CameraSession::Stop() {
  if (!running_.exchange(false)) return;
  pending_ready_.notify_all();
  if (capture_thread_.joinable()) capture_thread_.join();
  if (recognize_thread_.joinable()) recognize_thread_.join();
}

const FlutterDesktopPixelBuffer* CameraSession::CopyPixelBuffer(size_t, size_t) {
  // Locked here and released by the callback below: Flutter reads the
  // bytes after this returns, and the capture thread must not be writing
  // into them while it does.
  frame_mutex_.lock();
  if (rgba_.empty() || width_ <= 0 || height_ <= 0) {
    frame_mutex_.unlock();
    return nullptr;
  }
  pixel_buffer_.buffer = rgba_.data();
  pixel_buffer_.width = static_cast<size_t>(width_);
  pixel_buffer_.height = static_cast<size_t>(height_);
  pixel_buffer_.release_context = this;
  pixel_buffer_.release_callback = [](void* context) {
    static_cast<CameraSession*>(context)->frame_mutex_.unlock();
  };
  return &pixel_buffer_;
}

void CameraSession::Fail(std::string code, std::string message) {
  if (failed_.exchange(true)) return;
  if (on_error_) on_error_(std::move(code), std::move(message));
}

bool CameraSession::ReadFrame() {
  DWORD flags = 0;
  ComPtr<IMFSample> sample;
  HRESULT read = reader_->ReadSample(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, nullptr, &flags,
      nullptr, &sample);
  if (FAILED(read)) {
    Fail("cameraError", "The camera stopped delivering frames");
    return false;
  }
  if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
    // A webcam pulled out of the socket ends the stream rather than
    // erroring, and says nothing else about it.
    Fail("cameraDetached", "The camera was disconnected");
    return false;
  }
  if (!sample) return true;

  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) return true;

  BYTE* data = nullptr;
  DWORD length = 0;
  if (FAILED(buffer->Lock(&data, nullptr, &length))) return true;

  const size_t row_bytes = static_cast<size_t>(width_) * 4;
  const size_t needed = row_bytes * static_cast<size_t>(height_);
  const size_t source_stride = static_cast<size_t>(std::abs(stride_));
  const bool bottom_up = stride_ < 0;

  if (static_cast<size_t>(length) >= source_stride * static_cast<size_t>(height_) &&
      source_stride >= row_bytes) {
    std::vector<uint8_t> bgra(needed);
    {
      std::lock_guard<std::mutex> lock(frame_mutex_);
      for (int y = 0; y < height_; y++) {
        const size_t source_row = static_cast<size_t>(bottom_up ? (height_ - 1 - y) : y);
        const uint8_t* source = data + source_row * source_stride;
        uint8_t* rgba = rgba_.data() + static_cast<size_t>(y) * row_bytes;
        uint8_t* copy = bgra.data() + static_cast<size_t>(y) * row_bytes;
        memcpy(copy, source, row_bytes);
        // Media Foundation's RGB32 is B, G, R, X in memory; Flutter wants
        // R, G, B, A, and the camera has nothing to say about alpha.
        for (int x = 0; x < width_; x++) {
          const uint8_t* pixel = source + static_cast<size_t>(x) * 4;
          uint8_t* target = rgba + static_cast<size_t>(x) * 4;
          target[0] = pixel[2];
          target[1] = pixel[1];
          target[2] = pixel[0];
          target[3] = 255;
        }
      }
    }
    {
      std::lock_guard<std::mutex> lock(pending_mutex_);
      pending_ = std::move(bgra);
      has_pending_ = true;
    }
    pending_ready_.notify_one();
    if (textures_ != nullptr && texture_id_ >= 0) {
      textures_->MarkTextureFrameAvailable(texture_id_);
    }
  }

  buffer->Unlock();
  return true;
}

void CameraSession::CaptureLoop() {
  while (running_.load()) {
    if (!ReadFrame()) break;
  }
}

void CameraSession::RecognizeLoop() {
  auto last_run = std::chrono::steady_clock::now() - kMinInterval;

  while (true) {
    std::vector<uint8_t> frame;
    {
      std::unique_lock<std::mutex> lock(pending_mutex_);
      pending_ready_.wait(lock, [this] { return has_pending_ || !running_.load(); });
      if (!running_.load()) return;
      frame = std::move(pending_);
      has_pending_ = false;
    }

    const auto now = std::chrono::steady_clock::now();
    if (now - last_run < kMinInterval) continue;
    last_run = now;

    std::optional<NormalizedBox> roi;
    {
      std::lock_guard<std::mutex> lock(roi_mutex_);
      roi = roi_;
    }

    std::vector<RecognizedLine> lines =
        TextRecognizer::Recognize(frame.data(), width_, height_, roi);
    if (!running_.load()) return;
    if (on_frame_) on_frame_(std::move(lines));
  }
}

}  // namespace card_scanner
