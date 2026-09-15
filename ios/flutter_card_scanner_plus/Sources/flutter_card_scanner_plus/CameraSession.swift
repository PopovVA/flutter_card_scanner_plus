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
  let previewSize: CGSize

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

    if let connection = output.connection(with: .video) {
      if #available(iOS 17.0, *) {
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
      } else {
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
      }
    }
    session.commitConfiguration()

    // Buffers are delivered rotated to portrait, so swap the sensor dimensions.
    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    previewSize = CGSize(width: Int(dims.height), height: Int(dims.width))

    super.init()

    output.setSampleBufferDelegate(self, queue: videoQueue)
    textureId = textures.register(self)
    Self.configureFocus(device)
  }

  func start() {
    sessionQueue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
  }

  func stop() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning { self.session.stopRunning() }
      self.setTorch(false)
      DispatchQueue.main.async {
        self.textures.unregisterTexture(self.textureId)
      }
      self.bufferLock.lock()
      self.latestBuffer = nil
      self.bufferLock.unlock()
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
