#ifndef FLUTTER_PLUGIN_CARD_SCANNER_CAMERA_SESSION_H_
#define FLUTTER_PLUGIN_CARD_SCANNER_CAMERA_SESSION_H_

#include <flutter/texture_registrar.h>
#include <windows.h>
// mfidl.h declares IMFMediaSource, which mfreadwrite.h uses without
// declaring, so the order here is load-bearing. And the SDK's own
// mfreadwrite.h trips C4229, which this plugin builds with as an error.
#include <mfapi.h>
#include <mfidl.h>
#pragma warning(push)
#pragma warning(disable : 4229)
#include <mfreadwrite.h>
#pragma warning(pop)
#include <wrl/client.h>

#include <atomic>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include "text_recognizer.h"

namespace card_scanner {

// One open camera: Media Foundation reads it, the frames go to Flutter as
// a texture, and a copy of each one goes to the OCR engine.
class CameraSession {
 public:
  using FrameHandler = std::function<void(std::vector<RecognizedLine>)>;
  using ErrorHandler = std::function<void(std::string, std::string)>;

  // Opens `cameraId`, or the first camera when it is empty. Returns null
  // and fills `code` and `message` when the camera cannot be opened, so
  // the caller can answer the channel with the same codes the other
  // platforms use.
  static std::unique_ptr<CameraSession> Open(flutter::TextureRegistrar* textures,
                                             const std::wstring& cameraId,
                                             std::string* code,
                                             std::string* message);

  ~CameraSession();

  CameraSession(const CameraSession&) = delete;
  CameraSession& operator=(const CameraSession&) = delete;

  void Start();
  void Stop();

  int64_t texture_id() const { return texture_id_; }
  int width() const { return width_; }
  int height() const { return height_; }
  const std::wstring& camera_id() const { return camera_id_; }

  void SetRegionOfInterest(const std::optional<NormalizedBox>& roi);
  void SetHandlers(FrameHandler on_frame, ErrorHandler on_error);

 private:
  CameraSession(flutter::TextureRegistrar* textures, std::wstring camera_id);

  void CaptureLoop();
  void RecognizeLoop();
  bool ReadFrame();
  const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width, size_t height);
  void Fail(std::string code, std::string message);

  flutter::TextureRegistrar* textures_ = nullptr;
  std::unique_ptr<flutter::TextureVariant> texture_;
  FlutterDesktopPixelBuffer pixel_buffer_ = {};
  int64_t texture_id_ = -1;

  Microsoft::WRL::ComPtr<IMFMediaSource> source_;
  Microsoft::WRL::ComPtr<IMFSourceReader> reader_;

  std::wstring camera_id_;
  int width_ = 0;
  int height_ = 0;
  LONG stride_ = 0;

  // The frame Flutter draws, as RGBA, guarded while the raster thread
  // holds it.
  std::mutex frame_mutex_;
  std::vector<uint8_t> rgba_;

  // The most recent frame waiting to be read, as BGRA. One slot: a frame
  // that arrives while the engine is busy replaces the one waiting rather
  // than queueing behind it, because a stale frame of a moving card is
  // worth nothing.
  std::mutex pending_mutex_;
  std::condition_variable pending_ready_;
  std::vector<uint8_t> pending_;
  bool has_pending_ = false;

  std::mutex roi_mutex_;
  std::optional<NormalizedBox> roi_;

  FrameHandler on_frame_;
  ErrorHandler on_error_;

  std::atomic<bool> running_ = false;
  std::atomic<bool> failed_ = false;
  std::thread capture_thread_;
  std::thread recognize_thread_;
};

}  // namespace card_scanner

#endif  // FLUTTER_PLUGIN_CARD_SCANNER_CAMERA_SESSION_H_
