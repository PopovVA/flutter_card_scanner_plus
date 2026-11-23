#include "camera_catalog.h"

#include <windows.h>

#include <mfapi.h>
#include <mfidl.h>
#include <objbase.h>
#include <wrl/client.h>

namespace card_scanner {

namespace {

using Microsoft::WRL::ComPtr;

// Reads one string attribute, or an empty string when it is missing: a
// camera with no friendly name is still a camera.
std::wstring AttributeString(IMFActivate* device, const GUID& key) {
  WCHAR* value = nullptr;
  UINT32 length = 0;
  if (FAILED(device->GetAllocatedString(key, &value, &length))) return {};
  std::wstring result(value, length);
  CoTaskMemFree(value);
  return result;
}

}  // namespace

std::vector<CameraInfo> CameraCatalog::Cameras() {
  std::vector<CameraInfo> cameras;

  ComPtr<IMFAttributes> attributes;
  if (FAILED(MFCreateAttributes(&attributes, 1))) return cameras;
  if (FAILED(attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                                 MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID))) {
    return cameras;
  }

  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  if (FAILED(MFEnumDeviceSources(attributes.Get(), &devices, &count))) {
    return cameras;
  }

  for (UINT32 i = 0; i < count; i++) {
    std::wstring id = AttributeString(
        devices[i], MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK);
    if (!id.empty()) {
      cameras.push_back(
          {id, AttributeString(devices[i], MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME)});
    }
    devices[i]->Release();
  }
  CoTaskMemFree(devices);

  return cameras;
}

std::optional<CameraInfo> CameraCatalog::Camera(const std::wstring& id) {
  std::vector<CameraInfo> cameras = Cameras();
  if (cameras.empty()) return std::nullopt;
  if (!id.empty()) {
    for (const CameraInfo& camera : cameras) {
      if (camera.id == id) return camera;
    }
  }
  return cameras.front();
}

}  // namespace card_scanner
