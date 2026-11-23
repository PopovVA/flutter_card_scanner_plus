#ifndef FLUTTER_PLUGIN_FLUTTER_CARD_SCANNER_PLUS_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_CARD_SCANNER_PLUS_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "camera_session.h"

namespace card_scanner {

class FlutterCardScannerPlusPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FlutterCardScannerPlusPlugin(flutter::PluginRegistrarWindows* registrar);
  ~FlutterCardScannerPlusPlugin() override;

  FlutterCardScannerPlusPlugin(const FlutterCardScannerPlusPlugin&) = delete;
  FlutterCardScannerPlusPlugin& operator=(const FlutterCardScannerPlusPlugin&) =
      delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Start(const flutter::EncodableMap* arguments,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Stop();

  // Runs `work` on the thread that owns the channels. Frames are
  // recognized on a worker thread, and an event sink may only be touched
  // from the platform thread, so everything crosses here.
  void RunOnPlatformThread(std::function<void()> work);
  static LRESULT CALLBACK DispatchProc(HWND window, UINT message, WPARAM wparam,
                                       LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> methods_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> nfc_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;

  std::unique_ptr<CameraSession> session_;
  HWND dispatch_window_ = nullptr;
  bool media_foundation_started_ = false;
};

}  // namespace card_scanner

#endif  // FLUTTER_PLUGIN_FLUTTER_CARD_SCANNER_PLUS_PLUGIN_H_
