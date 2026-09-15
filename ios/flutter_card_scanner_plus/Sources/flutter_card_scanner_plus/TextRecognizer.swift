import CoreVideo
import Foundation
import Vision

/// Runs `VNRecognizeTextRequest` on camera frames, one at a time, and
/// converts observations to the channel's line format.
final class TextRecognizer {
  /// Normalized, top-left origin. `nil` means the whole frame.
  var regionOfInterest: CGRect? {
    get { lock.sync { _regionOfInterest } }
    set { lock.sync { _regionOfInterest = newValue } }
  }

  /// Minimum time between two OCR passes. Vision's accurate mode takes
  /// ~60–150 ms on recent devices; ~8 fps is plenty for the aggregator.
  private let minInterval: TimeInterval = 0.12

  private let queue = DispatchQueue(label: "dev.apissystems.card_scanner.ocr", qos: .userInitiated)
  private let lock = NSLock()
  private var _regionOfInterest: CGRect?
  private var busy = false
  private var lastRun = Date.distantPast

  func process(_ pixelBuffer: CVPixelBuffer, completion: @escaping ([String: Any]) -> Void) {
    let shouldRun: Bool = lock.sync {
      guard !busy, Date().timeIntervalSince(lastRun) >= minInterval else { return false }
      busy = true
      lastRun = Date()
      return true
    }
    guard shouldRun else { return }

    let roi = regionOfInterest
    queue.async { [weak self] in
      defer { self?.lock.sync { self?.busy = false } }
      guard let self else { return }
      let lines = self.recognize(pixelBuffer, roi: roi)
      completion(["lines": lines])
    }
  }

  private func recognize(_ pixelBuffer: CVPixelBuffer, roi: CGRect?) -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    if #available(iOS 16.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
    }

    // Vision uses a bottom-left origin; the channel uses top-left.
    let visionROI: CGRect
    if let roi {
      visionROI = CGRect(x: roi.minX, y: 1 - roi.maxY, width: roi.width, height: roi.height)
      request.regionOfInterest = visionROI
    } else {
      visionROI = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }

    return (request.results ?? []).compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      // Bounding boxes are relative to the region of interest.
      let bb = observation.boundingBox
      let left = visionROI.minX + bb.minX * visionROI.width
      let bottom = visionROI.minY + bb.minY * visionROI.height
      let width = bb.width * visionROI.width
      let height = bb.height * visionROI.height
      return [
        "text": candidate.string,
        "confidence": Double(candidate.confidence),
        "box": [
          "left": Double(left),
          "top": Double(1 - (bottom + height)),
          "width": Double(width),
          "height": Double(height),
        ],
      ]
    }
  }
}

extension NSLock {
  fileprivate func sync<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
