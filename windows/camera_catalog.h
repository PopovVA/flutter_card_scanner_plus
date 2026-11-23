#ifndef FLUTTER_PLUGIN_CARD_SCANNER_CAMERA_CATALOG_H_
#define FLUTTER_PLUGIN_CARD_SCANNER_CAMERA_CATALOG_H_

#include <optional>
#include <string>
#include <vector>

namespace card_scanner {

// One video capture device as Media Foundation reports it.
struct CameraInfo {
  // The device's symbolic link, which is stable across replugs and is what
  // `start` is given back as `cameraId`.
  std::wstring id;
  std::wstring name;
};

// Windows does not say which camera suits a card, so nothing here ranks
// them: they come back in the order the system enumerates, which puts the
// built-in one first on most laptops. An app that wants a different one
// shows the list and asks.
class CameraCatalog {
 public:
  static std::vector<CameraInfo> Cameras();

  // The camera with `id`, the first camera when `id` is empty or unknown,
  // and nothing at all when the machine has no camera. Falling back rather
  // than failing is what lets a scan survive a webcam unplugged between
  // the pick and the start.
  static std::optional<CameraInfo> Camera(const std::wstring& id);
};

}  // namespace card_scanner

#endif  // FLUTTER_PLUGIN_CARD_SCANNER_CAMERA_CATALOG_H_
