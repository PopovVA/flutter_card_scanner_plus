import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Error raised by the native NFC layer.
@immutable
class CardNfcException implements Exception {
  const CardNfcException(this.code, [this.message]);

  /// One of [unavailable], [cancelled], [tagLost], [sessionError], or a
  /// platform specific code.
  final String code;
  final String? message;

  /// The device has no NFC, it is switched off, or the app lacks the
  /// entitlement (iOS) or the `android.permission.NFC` permission.
  static const unavailable = 'nfcUnavailable';

  /// The user dismissed the system sheet or the app closed the session.
  static const cancelled = 'nfcCancelled';

  /// The card was moved away mid conversation.
  static const tagLost = 'nfcTagLost';

  static const sessionError = 'nfcSessionError';

  bool get isCancelled => code == cancelled;
  bool get isUnavailable => code == unavailable;

  @override
  String toString() =>
      'CardNfcException($code${message == null ? '' : ': $message'})';
}

/// Thin transport to the native NFC session. One APDU in, one reply out.
///
/// Everything above this (EMV flow, TLV, parsing) is plain Dart, so it can
/// be tested without a device by swapping [instance].
abstract class CardNfcPlatform {
  static CardNfcPlatform instance = MethodChannelCardNfcPlatform();

  /// Whether this device can read contactless cards right now.
  Future<bool> isAvailable();

  /// Opens a reader session and completes once a card is connected.
  ///
  /// [prompt] is shown in the system sheet on iOS and ignored on Android,
  /// where the app draws its own UI.
  Future<void> connect({required String prompt});

  /// Sends one command APDU and returns the raw reply including the two
  /// status bytes.
  Future<Uint8List> transceive(Uint8List command);

  /// Closes the session. [message] is shown on the iOS sheet when the read
  /// succeeded; pass [errorMessage] instead to show a failure.
  Future<void> close({String? message, String? errorMessage});
}

/// Default implementation talking to the plugin over a method channel.
class MethodChannelCardNfcPlatform implements CardNfcPlatform {
  MethodChannelCardNfcPlatform({@visibleForTesting MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('flutter_card_scanner_plus/nfc');

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> connect({required String prompt}) async {
    try {
      await _channel.invokeMethod<void>('connect', {'prompt': prompt});
    } on PlatformException catch (e) {
      throw CardNfcException(e.code, e.message);
    }
  }

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    try {
      final reply = await _channel.invokeMethod<Uint8List>('transceive', {
        'command': command,
      });
      return reply ?? Uint8List(0);
    } on PlatformException catch (e) {
      throw CardNfcException(e.code, e.message);
    }
  }

  @override
  Future<void> close({String? message, String? errorMessage}) async {
    try {
      await _channel.invokeMethod<void>('close', {
        'message': message,
        'errorMessage': errorMessage,
      });
    } on PlatformException {
      // Closing is best effort.
    }
  }
}
