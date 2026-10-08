import AVFoundation
import CoreMedia
import Flutter

/// Owns the capture session, exposes frames to Flutter as a texture and
/// feeds the same frames to the OCR engine. Frames never leave the device
/// and are never written to disk.
final class CameraSession: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
  struct SetupError: Error {
    let code: String
    let message: String
  }

  typealias FrameHandler = ([String: Any]) -> Void

  private(set) var textureId: Int64 = 0
  private(set) var previewSize: CGSize

  /// Called when a device rotation changes the shape of the preview.
  var onPreviewChanged: (() -> Void)?

  /// Called when the session fails after it started.
  var onError: ((String, String) -> Void)?

  /// Normalized (top-left origin) area of the preview to run OCR on.
  var regionOfInterest: CGRect? {
    get { recognizer.regionOfInterest }
    set { recognizer.regionOfInterest = newValue }
  }

  private let textures: FlutterTextureRegistry
  private let onFrame: FrameHandler
  private let session = AVCaptureSession()
  private let device: AVCaptureDevice
  private let recognizer = TextRecognizer()
  private let sessionQueue = DispatchQueue(label: "dev.apissystems.card_scanner.session")
  private let videoQueue = DispatchQueue(label: "dev.apissystems.card_scanner.video", qos: .userInitiated)

  private let bufferLock = NSLock()
  private var latestBuffer: CVPixelBuffer?
  private var videoOutput: AVCaptureVideoDataOutput?

  /// Sensor dimensions, before any rotation is applied.
  private let sensorSize: CGSize

  init(textures: FlutterTextureRegistry, onFrame: @escaping FrameHandler) throws {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
      throw SetupError(code: "noCamera", message: "No back camera available")
    }
    self.device = device
    self.textures = textures
    self.onFrame = onFrame

    session.beginConfiguration()
    session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      throw SetupError(code: "cameraError", message: "Cannot add camera input")
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    guard session.canAddOutput(output) else {
      throw SetupError(code: "cameraError", message: "Cannot add video output")
    }
    session.addOutput(output)

    session.commitConfiguration()
    videoOutput = output

    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    sensorSize = CGSize(width: Int(dims.width), height: Int(dims.height))
    // Portrait until the first orientation read below.
    previewSize = CGSize(width: sensorSize.height, height: sensorSize.width)

    super.init()

    output.setSampleBufferDelegate(self, queue: videoQueue)
    textureId = textures.register(self)
    Self.configureFocus(device)

    // Rotate the delivered buffers to match the interface. Doing it here
    // rather than in Dart keeps Vision reading upright text, which is what
    // recognition depends on, and lets the texture render without a turn.
    applyOrientation(notify: false)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(orientationChanged),
      name: UIDevice.orientationDidChangeNotification,
      object: nil)

    // A session that fails after it started used to leave the preview
    // frozen with nothing said about it.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(runtimeError),
      name: .AVCaptureSessionRuntimeError,
      object: session)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(interrupted),
      name: .AVCaptureSessionWasInterrupted,
      object: session)
  }

  @objc private func runtimeError(_ note: Notification) {
    let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
    onError?("cameraError", error?.localizedDescription ?? "The capture session failed")
  }

  /// Only an interruption that will not end on its own is reported. A call
  /// or Slide Over resumes the session by itself, and the app lifecycle
  /// already covers going to the background.
  @objc private func interrupted(_ note: Notification) {
    guard
      let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
      let reason = AVCaptureSession.InterruptionReason(rawValue: raw),
      reason == .videoDeviceInUseByAnotherClient
    else { return }
    onError?("cameraInterrupted", "Another app is using the camera")
  }

  @objc private func orientationChanged() {
    applyOrientation(notify: true)
  }

  /// Points the video connection at the current interface orientation and
  /// updates the preview shape to match.
  private func applyOrientation(notify: Bool) {
    let angle = Self.rotationAngle()
    let landscape = angle == 90 || angle == 270

    if let connection = videoOutput?.connection(with: .video) {
      if #available(iOS 17.0, *) {
        if connection.isVideoRotationAngleSupported(angle) {
          connection.videoRotationAngle = angle
        }
      } else if connection.isVideoOrientationSupported {
        connection.videoOrientation = Self.legacyOrientation(angle)
      }
    }

    let size = landscape
      ? CGSize(width: sensorSize.width, height: sensorSize.height)
      : CGSize(width: sensorSize.height, height: sensorSize.width)
    let changed = size != previewSize
    previewSize = size
    if notify && changed { onPreviewChanged?() }
  }

  /// Clockwise angle the buffer needs so its top matches the top of the UI.
  private static func rotationAngle() -> CGFloat {
    let interface: UIInterfaceOrientation?
    if Thread.isMainThread {
      interface = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
        .interfaceOrientation
    } else {
      interface = DispatchQueue.main.sync {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
      }
    }
    switch interface {
    case .landscapeLeft: return 180
    case .landscapeRight: return 0
    case .portraitUpsideDown: return 270
    default: return 90
    }
  }

  private static func legacyOrientation(_ angle: CGFloat) -> AVCaptureVideoOrientation {
    switch angle {
    case 0: return .landscapeRight
    case 180: return .landscapeLeft
    case 270: return .portraitUpsideDown
    default: return .portrait
    }
  }

  func start() {
    sessionQueue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
  }

  /// Stops capturing, releases the texture and then calls [completion] on
  /// the main thread.
  ///
  /// The completion is what lets the Dart side await a stop. Starting a new
  /// session while the previous one was still being torn down on this queue
  /// was leaving the preview black on reopen.
  func stop(completion: @escaping () -> Void) {
    NotificationCenter.default.removeObserver(self)
    onPreviewChanged = nil
    onError = nil

    sessionQueue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async(execute: completion)
        return
      }
      if self.session.isRunning { self.session.stopRunning() }
      self.setTorch(false)
      self.bufferLock.lock()
      self.latestBuffer = nil
      self.bufferLock.unlock()
      DispatchQueue.main.async {
        self.textures.unregisterTexture(self.textureId)
        completion()
      }
    }
  }

  func setTorch(_ enabled: Bool) {
    guard device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      device.torchMode = enabled && device.isTorchAvailable ? .on : .off
      device.unlockForConfiguration()
    } catch {
      // Torch is best-effort.
    }
  }

  // MARK: - FlutterTexture

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    bufferLock.lock()
    defer { bufferLock.unlock() }
    guard let buffer = latestBuffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    bufferLock.lock()
    latestBuffer = pixelBuffer
    bufferLock.unlock()
    textures.textureFrameAvailable(textureId)

    recognizer.process(pixelBuffer) { [weak self] frame in
      DispatchQueue.main.async { self?.onFrame(frame) }
    }
  }

  // MARK: - Helpers

  /// Cards are held close to the lens: bias autofocus to the near range.
  private static func configureFocus(_ device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isAutoFocusRangeRestrictionSupported {
        device.autoFocusRangeRestriction = .near
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      device.unlockForConfiguration()
    } catch {
      // Focus tuning is best-effort.
    }
  }
}
