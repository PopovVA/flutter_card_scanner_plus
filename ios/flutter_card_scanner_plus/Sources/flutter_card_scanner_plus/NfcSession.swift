import CoreNFC
import Flutter
import Foundation

/// Thin bridge to Core NFC: open a reader session, exchange APDUs, close.
///
/// No EMV logic lives here. The Dart side decides what to send and how to
/// read the reply, which keeps that logic testable without a device.
@available(iOS 13.0, *)
final class NfcSession: NSObject, NFCTagReaderSessionDelegate {
  private var session: NFCTagReaderSession?
  private var tag: NFCISO7816Tag?

  /// Completion of the pending `connect` call. Cleared once answered so it
  /// can never be called twice.
  private var connectResult: FlutterResult?
  private let lock = NSLock()

  static var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

  func connect(prompt: String, result: @escaping FlutterResult) {
    guard NFCTagReaderSession.readingAvailable else {
      result(
        FlutterError(
          code: "nfcUnavailable",
          message: "NFC tag reading is not available on this device",
          details: nil))
      return
    }
    close(message: nil, errorMessage: nil)

    guard
      let session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
    else {
      result(
        FlutterError(
          code: "nfcSessionError", message: "Could not start a reader session", details: nil))
      return
    }
    lock.lock()
    connectResult = result
    lock.unlock()

    session.alertMessage = prompt
    self.session = session
    session.begin()
  }

  func transceive(command: Data, result: @escaping FlutterResult) {
    guard let tag else {
      result(FlutterError(code: "nfcTagLost", message: "No card is connected", details: nil))
      return
    }
    guard let apdu = NFCISO7816APDU(data: command) else {
      result(FlutterError(code: "invalidArgument", message: "Malformed APDU", details: nil))
      return
    }
    tag.sendCommand(apdu: apdu) { payload, sw1, sw2, error in
      if let error {
        result(
          FlutterError(
            code: "nfcTagLost", message: error.localizedDescription, details: nil))
        return
      }
      var reply = payload
      reply.append(sw1)
      reply.append(sw2)
      result(FlutterStandardTypedData(bytes: reply))
    }
  }

  func close(message: String?, errorMessage: String?) {
    answerConnect(
      FlutterError(code: "nfcCancelled", message: "Session closed", details: nil))
    if let session {
      if let errorMessage {
        session.invalidate(errorMessage: errorMessage)
      } else {
        if let message { session.alertMessage = message }
        session.invalidate()
      }
    }
    session = nil
    tag = nil
  }

  /// Calls the pending connect completion exactly once.
  private func answerConnect(_ value: Any?) {
    lock.lock()
    let pending = connectResult
    connectResult = nil
    lock.unlock()
    pending?(value)
  }

  // MARK: - NFCTagReaderSessionDelegate

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    let code: String
    if let readerError = error as? NFCReaderError,
      readerError.code == .readerSessionInvalidationErrorUserCanceled
        || readerError.code == .readerSessionInvalidationErrorSessionTimeout
    {
      code = "nfcCancelled"
    } else {
      code = "nfcSessionError"
    }
    answerConnect(
      FlutterError(code: code, message: error.localizedDescription, details: nil))
    self.session = nil
    tag = nil
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let first = tags.first, case let .iso7816(isoTag) = first else {
      session.invalidate(errorMessage: "This is not a payment card")
      answerConnect(
        FlutterError(
          code: "nfcSessionError", message: "Tag is not ISO 7816", details: nil))
      return
    }

    session.connect(to: first) { [weak self] error in
      guard let self else { return }
      if let error {
        session.invalidate(errorMessage: "Could not connect to the card")
        self.answerConnect(
          FlutterError(
            code: "nfcTagLost", message: error.localizedDescription, details: nil))
        return
      }
      self.tag = isoTag
      self.answerConnect(nil)
    }
  }
}
