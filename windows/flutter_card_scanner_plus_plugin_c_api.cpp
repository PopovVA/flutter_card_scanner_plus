#include "include/flutter_card_scanner_plus/flutter_card_scanner_plus_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_card_scanner_plus_plugin.h"

void FlutterCardScannerPlusPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  card_scanner::FlutterCardScannerPlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
