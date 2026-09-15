import AVFoundation
import Flutter
import UIKit

/// Method channel: `flutter_card_scanner_plus/methods`
///   start(regionOfInterest?: Box) -> {textureId, previewWidth, previewHeight}
///   stop()
///   setTorch(enabled: Bool)
///   setRegionOfInterest(Box)
///   recognizeImage(bytes: Uint8List, regionOfInterest?: Box) -> {lines}
/// Event channel: `flutter_card_scanner_plus/frames`
///   {lines: [{text, box: {left, top, width, height}, confidence}]}
///
/// All boxes are normalized (0..1) in portrait preview coordinates with a
/// top-left origin, regardless of the region of interest.
public class FlutterCardScannerPlusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let textures: FlutterTextureRegistry
  private var session: CameraSession?
  private var eventSink: FlutterEventSink?

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterCardScannerPlusPlugin(textures: registrar.textures())
    let methods = FlutterMethodChannel(
      name: "flutter_card_scanner_plus/methods", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "flutter_card_scanner_plus/frames", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      start(arguments: call.arguments as? [String: Any], result: result)
    case "stop":
      stop()
      result(nil)
    case "setTorch":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      session?.setTorch(enabled)
      result(nil)
    case "setRegionOfInterest":
      session?.regionOfInterest = Self.parseBox(call.arguments as? [String: Any])
      result(nil)
    case "recognizeImage":
      let args = call.arguments as? [String: Any]
      guard let bytes = args?["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "invalidArgument", message: "bytes missing", details: nil))
        return
      }
      let roi = Self.parseBox(args?["regionOfInterest"] as? [String: Any])
      TextRecognizer.recognizeImage(bytes.data, roi: roi) { frame in
        DispatchQueue.main.async {
          if let frame {
            result(frame)
          } else {
            result(FlutterError(code: "invalidImage", message: "Could not decode image", details: nil))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(arguments: [String: Any]?, result: @escaping FlutterResult) {
    if session != nil {
      result(FlutterError(code: "alreadyRunning", message: "Scanner is already running", details: nil))
      return
    }
    let roi = Self.parseBox(arguments?["regionOfInterest"] as? [String: Any])

    Self.requestCameraAccess { [weak self] granted in
      guard let self else { return }
      guard granted else {
        result(FlutterError(code: "permissionDenied", message: "Camera permission denied", details: nil))
        return
      }
      do {
        let session = try CameraSession(textures: self.textures) { [weak self] frame in
          self?.eventSink?(frame)
        }
        session.regionOfInterest = roi
        self.session = session
        session.start()
        result([
          "textureId": session.textureId,
          "previewWidth": session.previewSize.width,
          "previewHeight": session.previewSize.height,
        ])
      } catch let error as CameraSession.SetupError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
      } catch {
        result(FlutterError(code: "cameraError", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func stop() {
    session?.stop()
    session = nil
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Helpers

  private static func requestCameraAccess(_ completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { completion(granted) }
      }
    default:
      completion(false)
    }
  }

  private static func parseBox(_ map: [String: Any]?) -> CGRect? {
    guard let map,
      let left = map["left"] as? Double,
      let top = map["top"] as? Double,
      let width = map["width"] as? Double,
      let height = map["height"] as? Double
    else { return nil }
    return CGRect(x: left, y: top, width: width, height: height)
  }
}
