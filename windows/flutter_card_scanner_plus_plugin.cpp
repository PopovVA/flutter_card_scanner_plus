#include "flutter_card_scanner_plus_plugin.h"

#include <mfapi.h>

#include <optional>
#include <thread>
#include <utility>

#include "camera_catalog.h"
#include "text_recognizer.h"

namespace card_scanner {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr wchar_t kDispatchWindowClass[] = L"FlutterCardScannerPlusDispatch";
constexpr UINT kRunWork = WM_APP + 1;

std::string ToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring ToWide(const std::string& text) {
  if (text.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), size);
  return result;
}

const EncodableValue* ValueAt(const EncodableMap* map, const char* key) {
  if (map == nullptr) return nullptr;
  auto entry = map->find(EncodableValue(std::string(key)));
  if (entry == map->end()) return nullptr;
  return &entry->second;
}

std::string StringAt(const EncodableMap* map, const char* key) {
  const EncodableValue* value = ValueAt(map, key);
  if (value == nullptr) return {};
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::string() : *text;
}

std::optional<double> DoubleAt(const EncodableMap* map, const char* key) {
  const EncodableValue* value = ValueAt(map, key);
  if (value == nullptr) return std::nullopt;
  if (const auto* number = std::get_if<double>(value)) return *number;
  if (const auto* integer = std::get_if<int32_t>(value)) return *integer;
  if (const auto* integer = std::get_if<int64_t>(value)) {
    return static_cast<double>(*integer);
  }
  return std::nullopt;
}

std::optional<NormalizedBox> BoxAt(const EncodableMap* map, const char* key) {
  const EncodableValue* value = ValueAt(map, key);
  if (value == nullptr) return std::nullopt;
  const auto* box = std::get_if<EncodableMap>(value);
  if (box == nullptr) return std::nullopt;

  std::optional<double> left = DoubleAt(box, "left");
  std::optional<double> top = DoubleAt(box, "top");
  std::optional<double> width = DoubleAt(box, "width");
  std::optional<double> height = DoubleAt(box, "height");
  if (!left || !top || !width || !height) return std::nullopt;
  return NormalizedBox{*left, *top, *width, *height};
}

EncodableValue Encode(const std::vector<RecognizedLine>& lines) {
  EncodableList encoded;
  encoded.reserve(lines.size());
  for (const RecognizedLine& line : lines) {
    encoded.push_back(EncodableValue(EncodableMap{
        {EncodableValue("text"), EncodableValue(line.text)},
        {EncodableValue("confidence"), EncodableValue(line.confidence)},
        {EncodableValue("box"),
         EncodableValue(EncodableMap{
             {EncodableValue("left"), EncodableValue(line.box.left)},
             {EncodableValue("top"), EncodableValue(line.box.top)},
             {EncodableValue("width"), EncodableValue(line.box.width)},
             {EncodableValue("height"), EncodableValue(line.box.height)},
         })},
    }));
  }
  return EncodableValue(EncodableMap{{EncodableValue("lines"),
                                      EncodableValue(std::move(encoded))}});
}

}  // namespace

void FlutterCardScannerPlusPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<FlutterCardScannerPlusPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

FlutterCardScannerPlusPlugin::FlutterCardScannerPlusPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  media_foundation_started_ = SUCCEEDED(MFStartup(MF_VERSION));

  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = DispatchProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kDispatchWindowClass;
  RegisterClassW(&window_class);
  // A message-only window: it draws nothing and exists so a worker thread
  // can hand work back to the thread that owns the channels.
  dispatch_window_ =
      CreateWindowExW(0, kDispatchWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE,
                      nullptr, GetModuleHandle(nullptr), nullptr);

  methods_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "flutter_card_scanner_plus/methods",
      &flutter::StandardMethodCodec::GetInstance());
  methods_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  events_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "flutter_card_scanner_plus/frames",
      &flutter::StandardMethodCodec::GetInstance());
  events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*, auto&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_ = std::move(sink);
            return nullptr;
          },
          [this](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_.reset();
            return nullptr;
          }));

  nfc_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "flutter_card_scanner_plus/nfc",
      &flutter::StandardMethodCodec::GetInstance());
  nfc_->SetMethodCallHandler([](const auto& call, auto result) {
    // No PC has the radio, and Windows has no contactless payment API to
    // reach it with. Saying so plainly lets an app offer the NFC path
    // where it exists and hide it here.
    if (call.method_name() == "isAvailable") {
      result->Success(EncodableValue(false));
    } else {
      result->Error("nfcUnavailable", "Windows cannot read contactless cards");
    }
  });
}

FlutterCardScannerPlusPlugin::~FlutterCardScannerPlusPlugin() {
  Stop();
  if (dispatch_window_ != nullptr) DestroyWindow(dispatch_window_);
  if (media_foundation_started_) MFShutdown();
}

LRESULT CALLBACK FlutterCardScannerPlusPlugin::DispatchProc(HWND window,
                                                            UINT message,
                                                            WPARAM wparam,
                                                            LPARAM lparam) {
  if (message == kRunWork) {
    auto* work = reinterpret_cast<std::function<void()>*>(lparam);
    (*work)();
    delete work;
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void FlutterCardScannerPlusPlugin::RunOnPlatformThread(
    std::function<void()> work) {
  if (dispatch_window_ == nullptr) return;
  auto* owned = new std::function<void()>(std::move(work));
  if (!PostMessageW(dispatch_window_, kRunWork, 0,
                    reinterpret_cast<LPARAM>(owned))) {
    delete owned;
  }
}

void FlutterCardScannerPlusPlugin::Stop() {
  if (!session_) return;
  std::unique_ptr<CameraSession> closing = std::move(session_);
  closing->Stop();
  closing.reset();
}

void FlutterCardScannerPlusPlugin::Start(
    const EncodableMap* arguments,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (session_) {
    result->Error("alreadyRunning", "Scanner is already running");
    return;
  }

  std::string code;
  std::string message;
  std::unique_ptr<CameraSession> session = CameraSession::Open(
      registrar_->texture_registrar(), ToWide(StringAt(arguments, "cameraId")),
      &code, &message);
  if (!session) {
    result->Error(code, message);
    return;
  }

  session->SetRegionOfInterest(BoxAt(arguments, "regionOfInterest"));
  session->SetHandlers(
      [this](std::vector<RecognizedLine> lines) {
        RunOnPlatformThread([this, frame = std::move(lines)]() {
          if (sink_) sink_->Success(Encode(frame));
        });
      },
      [this](std::string code, std::string message) {
        RunOnPlatformThread([this, failure = std::move(code),
                             reason = std::move(message)]() {
          if (!sink_) return;
          sink_->Success(EncodableValue(EncodableMap{
              {EncodableValue("error"),
               EncodableValue(EncodableMap{
                   {EncodableValue("code"), EncodableValue(failure)},
                   {EncodableValue("message"), EncodableValue(reason)},
               })},
          }));
        });
      });

  session->Start();
  session_ = std::move(session);

  result->Success(EncodableValue(EncodableMap{
      {EncodableValue("textureId"), EncodableValue(session_->texture_id())},
      {EncodableValue("previewWidth"), EncodableValue(session_->width())},
      {EncodableValue("previewHeight"), EncodableValue(session_->height())},
      // No PC camera has a torch, and nothing here can turn one on.
      {EncodableValue("torchAvailable"), EncodableValue(false)},
      {EncodableValue("cameraId"),
       EncodableValue(ToUtf8(session_->camera_id()))},
  }));
}

void FlutterCardScannerPlusPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* arguments = std::get_if<EncodableMap>(call.arguments());

  if (method == "listCameras") {
    EncodableList cameras;
    for (const CameraInfo& camera : CameraCatalog::Cameras()) {
      cameras.push_back(EncodableValue(EncodableMap{
          {EncodableValue("id"), EncodableValue(ToUtf8(camera.id))},
          {EncodableValue("name"), EncodableValue(ToUtf8(camera.name))},
          // Windows does not say which camera is built in, so none of
          // them claims to be anything in particular.
          {EncodableValue("kind"), EncodableValue("external")},
      }));
    }
    result->Success(EncodableValue(std::move(cameras)));
    return;
  }

  if (method == "start") {
    Start(arguments, std::move(result));
    return;
  }

  if (method == "stop") {
    Stop();
    result->Success();
    return;
  }

  if (method == "setTorch") {
    // Answered rather than refused, so shared Dart code does not have to
    // branch on the platform. `start` already said there is no torch.
    result->Success();
    return;
  }

  if (method == "setRegionOfInterest") {
    if (session_) {
      session_->SetRegionOfInterest(
          arguments == nullptr
              ? std::nullopt
              : std::optional<NormalizedBox>(NormalizedBox{
                    DoubleAt(arguments, "left").value_or(0),
                    DoubleAt(arguments, "top").value_or(0),
                    DoubleAt(arguments, "width").value_or(1),
                    DoubleAt(arguments, "height").value_or(1)}));
    }
    result->Success();
    return;
  }

  if (method == "recognizeImage") {
    const EncodableValue* bytes = ValueAt(arguments, "bytes");
    const auto* data = bytes == nullptr
                           ? nullptr
                           : std::get_if<std::vector<uint8_t>>(bytes);
    if (data == nullptr) {
      result->Error("invalidArgument", "bytes missing");
      return;
    }
    std::optional<NormalizedBox> roi = BoxAt(arguments, "regionOfInterest");
    std::shared_ptr<flutter::MethodResult<EncodableValue>> shared(
        result.release());
    // Decoding and reading an image takes long enough to be felt, and the
    // platform thread is the one drawing the app.
    std::thread([this, image = *data, roi, shared]() {
      std::optional<std::vector<RecognizedLine>> read =
          TextRecognizer::RecognizeEncoded(image, roi);
      RunOnPlatformThread([shared, lines = std::move(read)]() {
        if (lines.has_value()) {
          shared->Success(Encode(*lines));
        } else {
          shared->Error("invalidImage", "Could not decode image");
        }
      });
    }).detach();
    return;
  }

  result->NotImplemented();
}

}  // namespace card_scanner
