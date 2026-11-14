import AVFoundation
import Foundation

/// Finds the cameras a Mac can scan a card with, and ranks them.
///
/// A phone has one obvious answer — the back camera — and the iOS side
/// simply asks for it. A Mac has none. The built-in FaceTime camera sits
/// above the screen, fixed at roughly arm's length, and a card held there
/// lands in the frame small, dim and at an angle; it reads, but barely.
/// Continuity Camera is the same hardware the iOS implementation uses, so
/// when an iPhone is nearby it is the better camera by a wide margin, and
/// it is picked first.
enum CameraCatalog {
  /// How good a camera is for reading a card held in the hand, highest
  /// first.
  private enum Rank: Int {
    /// An iPhone acting as a webcam: a back camera with macro focus.
    case continuity = 3
    /// A USB webcam, which can at least be moved and pointed at a desk.
    case external = 2
    /// The one above the screen. Works, but it is the last resort.
    case builtIn = 1
  }

  /// Every video camera attached to this Mac, best for card scanning
  /// first.
  static func cameras() -> [AVCaptureDevice] {
    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes(), mediaType: .video, position: .unspecified)
    // `enumerated` keeps discovery's own order as the tie-break, so two
    // cameras of the same kind stay in the order the system lists them
    // and a scan reopens on the same one.
    return session.devices
      .enumerated()
      .sorted { lhs, rhs in
        let left = rank(lhs.element)
        let right = rank(rhs.element)
        if left != right { return left.rawValue > right.rawValue }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  /// The camera [id] names, or the best one when [id] is nil or gone.
  ///
  /// An unplugged webcam falling back to the built-in one is deliberate:
  /// a scanner that opens on a lesser camera is better than one that
  /// refuses to open.
  static func camera(id: String?) -> AVCaptureDevice? {
    let all = cameras()
    if let id, let match = all.first(where: { $0.uniqueID == id }) {
      return match
    }
    return all.first
  }

  /// The channel's description of [device].
  static func describe(_ device: AVCaptureDevice) -> [String: Any] {
    [
      "id": device.uniqueID,
      "name": device.localizedName,
      "kind": kind(device),
    ]
  }

  private static func kind(_ device: AVCaptureDevice) -> String {
    switch rank(device) {
    case .continuity: return "continuity"
    case .external: return "external"
    case .builtIn: return "builtIn"
    }
  }

  private static func rank(_ device: AVCaptureDevice) -> Rank {
    if #available(macOS 13.0, *), device.isContinuityCamera { return .continuity }
    if #available(macOS 14.0, *) {
      if device.deviceType == .continuityCamera { return .continuity }
      if device.deviceType == .external { return .external }
    }
    if device.deviceType == .builtInWideAngleCamera { return .builtIn }
    // Anything discovery returned that is neither built-in nor a known
    // Continuity type is some other box plugged in.
    return .external
  }

  /// `.external` replaced `.externalUnknown` in macOS 14. Both have to be
  /// asked for, or the Mac they are not current on lists no webcams at
  /// all.
  private static func deviceTypes() -> [AVCaptureDevice.DeviceType] {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
    if #available(macOS 14.0, *) {
      types.append(.external)
      types.append(.continuityCamera)
    } else {
      types.append(.externalUnknown)
    }
    return types
  }
}
