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
    set {
      recognizer.regionOfInterest = newValue
      // The guide's width is what decides how close a card has to be held,
      // and therefore whether the lens can focus on it at all.
      guideWidthFraction = newValue?.width
      applyCloseUpZoom()
    }
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

  /// Share of the preview's width the guide takes, from the last region of
  /// interest. Drives the close-up zoom.
  private var guideWidthFraction: CGFloat?

  /// ISO 7810 ID-1: the width of every payment card, in millimetres.
  private static let cardWidthMillimetres: Float = 85.6

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
  ///
  /// The interface rather than the device, and so not
  /// AVCaptureDevice.RotationCoordinator, which reports the device's own
  /// rotation: an app locked to portrait keeps an upright guide however the
  /// phone is held, and turning the buffer there would leave the preview
  /// sideways inside it.
  ///
  /// Main thread only, because that is where the interface orientation can
  /// be read.
  private func applyOrientation(notify: Bool) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.applyOrientation(notify: notify) }
      return
    }
    let angle = Self.rotationAngle()
    // 90 and 270 turn the buffer on its side, so the delivered frame has
    // the sensor's dimensions swapped. Portrait is 90, not 0.
    let quarterTurn = angle == 90 || angle == 270

    if let connection = videoOutput?.connection(with: .video) {
      if #available(iOS 17.0, *) {
        if connection.isVideoRotationAngleSupported(angle) {
          connection.videoRotationAngle = angle
        }
      } else if connection.isVideoOrientationSupported {
        connection.videoOrientation = Self.legacyOrientation(angle)
      }
    }

    let size = quarterTurn
      ? CGSize(width: sensorSize.height, height: sensorSize.width)
      : CGSize(width: sensorSize.width, height: sensorSize.height)
    let changed = size != previewSize
    previewSize = size
    // Turning the device swaps which way the guide runs across the sensor,
    // so the distance a card has to be held at changes with it.
    applyCloseUpZoom()
    if notify && changed { onPreviewChanged?() }
  }

  /// Zooms in just enough that a card filling the guide sits beyond the
  /// closest distance the lens can focus at.
  ///
  /// The main camera of a recent iPhone cannot focus nearer than about
  /// 20 cm, while a card fills the guide at about 12 cm. Held where the
  /// guide asks for it, the card simply never sharpens, however patient
  /// the person is. Narrowing the field of view moves that framing
  /// further away, which is what Apple's own close-up scanning sample
  /// does.
  ///
  /// Cropping the sensor does not move the guide: the delivered frame
  /// still covers exactly what is captured, so a region of interest
  /// expressed as a fraction of it lines up as before.
  private func applyCloseUpZoom() {
    guard let fraction = guideWidthFraction, fraction > 0 else { return }
    // Reported as -1 by a device that does not know.
    let closest = Float(device.minimumFocusDistance)
    guard closest > 0 else { return }

    let fieldOfView = fieldOfViewAlongGuide()
    guard fieldOfView > 0, fieldOfView < 180 else { return }
    let span = 2 * tan(fieldOfView / 2 * .pi / 180)
    guard span > 0 else { return }

    // Where a card has to be held for it to fill that share of the frame.
    let distance = Self.cardWidthMillimetres / (Float(fraction) * span)
    guard distance > 0, distance < closest else { return }

    let wanted = min(
      CGFloat(closest / distance), device.activeFormat.videoMaxZoomFactor)
    guard wanted > 1.01, abs(wanted - device.videoZoomFactor) > 0.01 else { return }

    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = wanted
      device.unlockForConfiguration()
    } catch {
      // Zoom is best effort, like the torch.
    }
  }

  /// The field of view across the guide's long side, in degrees.
  ///
  /// `videoFieldOfView` is the horizontal one, across the sensor's width.
  /// In portrait the preview is turned a quarter, so the guide's long side
  /// runs along the sensor's height instead.
  private func fieldOfViewAlongGuide() -> Float {
    let horizontal = device.activeFormat.videoFieldOfView
    let landscape = previewSize.width > previewSize.height
    guard !landscape, sensorSize.width > 0 else { return horizontal }
    let radians = horizontal / 2 * .pi / 180
    let ratio = Float(sensorSize.height / sensorSize.width)
    return 2 * atan(tan(radians) * ratio) * 180 / .pi
  }

  /// Clockwise angle the buffer needs so its top matches the top of the UI.
  ///
  /// Call on the main thread only.
  private static func rotationAngle() -> CGFloat {
    // connectedScenes is a Set, so the active window scene is picked
    // explicitly rather than taken from an arbitrary position.
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    switch scene?.interfaceOrientation {
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
      self.resetZoom()
      self.bufferLock.lock()
      self.latestBuffer = nil
      self.bufferLock.unlock()
      DispatchQueue.main.async {
        self.textures.unregisterTexture(self.textureId)
        completion()
      }
    }
  }

  /// Puts the lens back where it was. The device outlives this session,
  /// and whatever opens the camera next should not inherit a crop.
  private func resetZoom() {
    guard device.videoZoomFactor != 1 else { return }
    do {
      try device.lockForConfiguration()
      device.videoZoomFactor = 1
      device.unlockForConfiguration()
    } catch {
      // Best effort.
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
