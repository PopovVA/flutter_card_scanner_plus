import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_card_scanner_plus/src/web/web_camera_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a refusal is a refusal, whichever name the browser uses', () {
    expect(
      WebCameraError.codeFor('NotAllowedError'),
      CardScannerException.permissionDenied,
    );
    expect(
      WebCameraError.codeFor('SecurityError'),
      CardScannerException.permissionDenied,
    );
  });

  test('no camera, or none that fits the constraints', () {
    expect(
      WebCameraError.codeFor('NotFoundError'),
      CardScannerException.noCamera,
    );
    expect(
      WebCameraError.codeFor('OverconstrainedError'),
      CardScannerException.noCamera,
    );
  });

  test('a camera held by something else', () {
    expect(
      WebCameraError.codeFor('NotReadableError'),
      CardScannerException.cameraInterrupted,
    );
  });

  test('anything else is a plain camera error', () {
    expect(
      WebCameraError.codeFor('AbortError'),
      CardScannerException.cameraError,
    );
    expect(
      WebCameraError.codeFor('TypeError'),
      CardScannerException.cameraError,
    );
    expect(WebCameraError.codeFor(''), CardScannerException.cameraError);
  });

  test('a page that cannot ask at all says so', () {
    expect(WebCameraError.unsupported.code, 'unsupported');
    expect(WebCameraError.unsupported.message, contains('HTTPS'));
  });
}
