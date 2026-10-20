import '../channel/card_scanner_platform.dart';

/// Translates a browser camera failure into a [CardScannerException] code.
///
/// `getUserMedia` reports everything through one `DOMException`, and only
/// its `name` says what went wrong. The names are stable across browsers;
/// the messages are not, so nothing reads them.
abstract final class WebCameraError {
  /// The code for a `DOMException` called [name].
  ///
  /// Anything unrecognized, including an empty name, is
  /// [CardScannerException.cameraError].
  static String codeFor(String name) => switch (name) {
    // The user refused, or a permissions policy blocked the page.
    'NotAllowedError' ||
    'SecurityError' => CardScannerException.permissionDenied,
    // No camera at all, or none that can satisfy the constraints.
    'NotFoundError' || 'OverconstrainedError' => CardScannerException.noCamera,
    // The camera exists but something else holds it, or the OS refused it.
    'NotReadableError' => CardScannerException.cameraInterrupted,
    _ => CardScannerException.cameraError,
  };

  /// The error to raise when the page cannot ask for a camera at all.
  ///
  /// A browser only exposes `getUserMedia` in a secure context, so a page
  /// served over plain HTTP, or an embedded browser without the API, can
  /// never scan. That is worth saying before anything is tried.
  static const unsupported = CardScannerException(
    'unsupported',
    'This browser cannot open a camera. A secure context, that is HTTPS or '
        'localhost, is required.',
  );
}
