import AVFoundation
import CoreMedia
import FlutterMacOS

/// Owns the capture session, exposes frames to Flutter as a texture and
/// feeds the same frames to the OCR engine. Frames never leave the device
/// and are never written to disk.
///
/// Shorter than its iOS twin, and on purpose. A Mac does not rotate, so
/// there is no orientation to track and the preview keeps the sensor's own
/// shape. None of the lens controls the phone uses — zoom, near-field
/// autofocus, the torch — exist on this platform, so a camera is opened,
/// read and closed, and nothing else is asked of it.
final class CameraSession: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
  struct SetupError: Error {
    let code: String
    let message: String
  }

  typealias FrameHandler = ([String: Any]) -> Void

  private(set) var textureId: Int64 = 0
  private(set) var previewSize: CGSize

  /// The camera this session opened, for the handle Dart gets back.
  let device: AVCaptureDevice

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
  private let recognizer = TextRecognizer()
  private let sessionQueue = DispatchQueue(label: "dev.apissystems.card_scanner.session")
  private let videoQueue = DispatchQueue(label: "dev.apissystems.card_scanner.video", qos: .userInitiated)

  private let bufferLock = NSLock()
  private var latestBuffer: CVPixelBuffer?

  init(textures: FlutterTextureRegistry, cameraId: String?, onFrame: @escaping FrameHandler) throws {
    guard let device = CameraCatalog.camera(id: cameraId) else {
      throw SetupError(code: "noCamera", message: "No camera available")
    }
    self.device = device
    self.textures = textures
    self.onFrame = onFrame

    session.beginConfiguration()
    session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      // A camera another app holds, or one the user has not allowed, fails
      // here rather than at `canAddInput`.
      session.commitConfiguration()
      throw SetupError(code: "cameraError", message: error.localizedDescription)
    }
    guard session.canAddInput(input) else {
      session.commitConfiguration()
      throw SetupError(code: "cameraError", message: "Cannot add camera input")
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      throw SetupError(code: "cameraError", message: "Cannot add video output")
    }
    session.addOutput(output)
    session.commitConfiguration()

    // The buffers arrive the way the sensor reads them, and the Mac never
    // turns. Whatever the dimensions are is what the preview is.
    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    previewSize = CGSize(width: Int(dims.width), height: Int(dims.height))

    super.init()

    // A webcam shows the person themselves, so macOS mirrors previews by
    // habit. Vision cannot read mirrored text, and the guide would sit on
    // the wrong half of the card, so this one is left as captured.
    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = false
    }

    output.setSampleBufferDelegate(self, queue: videoQueue)
    textureId = textures.register(self)

    // A session that fails after it started would otherwise leave the
    // preview frozen with nothing said about it.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(runtimeError),
      name: .AVCaptureSessionRuntimeError,
      object: session)
    // Unplugging a webcam, or an iPhone walking out of range, is the Mac's
    // version of the camera being taken away.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(deviceDisconnected),
      name: .AVCaptureDeviceWasDisconnected,
      object: nil)
  }

  @objc private func runtimeError(_ note: Notification) {
    let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
    onError?("cameraError", error?.localizedDescription ?? "The capture session failed")
  }

  @objc private func deviceDisconnected(_ note: Notification) {
    guard (note.object as? AVCaptureDevice)?.uniqueID == device.uniqueID else { return }
    onError?("cameraDetached", "The camera was disconnected")
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
  /// leaves the preview black on reopen.
  func stop(completion: @escaping () -> Void) {
    NotificationCenter.default.removeObserver(self)
    onError = nil

    sessionQueue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async(execute: completion)
        return
      }
      if self.session.isRunning { self.session.stopRunning() }
      self.bufferLock.lock()
      self.latestBuffer = nil
      self.bufferLock.unlock()
      DispatchQueue.main.async {
        self.textures.unregisterTexture(self.textureId)
        completion()
      }
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
}
