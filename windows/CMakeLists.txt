# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

project(flutter_card_scanner_plus LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "flutter_card_scanner_plus_plugin")

list(APPEND PLUGIN_SOURCES
  "camera_catalog.cpp"
  "camera_catalog.h"
  "camera_session.cpp"
  "camera_session.h"
  "flutter_card_scanner_plus_plugin.cpp"
  "flutter_card_scanner_plus_plugin.h"
  "text_recognizer.cpp"
  "text_recognizer.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/flutter_card_scanner_plus/flutter_card_scanner_plus_plugin_c_api.h"
  "flutter_card_scanner_plus_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

# C++/WinRT, which is how Windows.Media.Ocr is reached, wants C++20 and
# the coroutine switch. This matches what the published Windows plugins
# that use WinRT do, down to the strict form of /await.
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_20)
target_compile_options(${PLUGIN_NAME} PRIVATE /await:strict)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

# Media Foundation reads the camera; WindowsApp.lib is what C++/WinRT needs
# to reach Windows.Media.Ocr, which is the OCR engine Windows ships with.
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  mf
  mfplat
  mfreadwrite
  mfuuid
  ole32
  windowsapp
)

set(flutter_card_scanner_plus_bundled_libraries
  ""
  PARENT_SCOPE
)
