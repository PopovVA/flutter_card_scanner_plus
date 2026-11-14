#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_card_scanner_plus.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_card_scanner_plus'
  s.version          = '0.4.0'
  s.summary          = 'On-device bank card scanner (Visa, Mastercard, Amex).'
  s.description      = <<-DESC
Scans payment cards with the camera using the Vision framework. Frames never leave the device.
                       DESC
  s.homepage         = 'https://github.com/PopovVA/flutter_card_scanner_plus'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Apis Systems LLC' => 'support@apissystems.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_card_scanner_plus/Sources/flutter_card_scanner_plus/**/*'
  s.dependency 'FlutterMacOS'
  s.frameworks = 'AVFoundation', 'Vision'
  # VNRecognizeTextRequest and AVCaptureDevice.DiscoverySession are both
  # 10.15. CoreNFC does not exist on the Mac at all, so the NFC channel
  # answers `isAvailable: false` and refuses the rest.
  s.platform = :osx, '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_card_scanner_plus_privacy' => ['flutter_card_scanner_plus/Sources/flutter_card_scanner_plus/PrivacyInfo.xcprivacy']}
end
