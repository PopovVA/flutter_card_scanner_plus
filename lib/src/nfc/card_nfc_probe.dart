import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'apdu.dart';
import 'nfc_platform.dart';
import 'tlv.dart';

/// One command and its reply, kept for diagnostics.
@immutable
class NfcExchange {
  const NfcExchange({
    required this.label,
    required this.command,
    required this.response,
  });

  final String label;
  final String command;
  final ResponseApdu response;

  String get statusWord =>
      response.statusWord.toRadixString(16).toUpperCase().padLeft(4, '0');

  @override
  String toString() => '$label: SW=$statusWord, ${response.data.length} bytes';
}

/// Result of [CardNfcProbe.run].
@immutable
class NfcProbeReport {
  const NfcProbeReport({
    required this.exchanges,
    required this.offeredAids,
    required this.selectedAid,
    this.error,
  });

  /// Every APDU sent, in order.
  final List<NfcExchange> exchanges;

  /// AIDs the card listed in its PPSE directory, as hex.
  final List<String> offeredAids;

  /// The AID that was selected successfully, as hex, or `null`.
  final String? selectedAid;

  final CardNfcException? error;

  /// The card answered PPSE and a payment application was selected.
  bool get isSuccess => selectedAid != null;

  /// Readable summary, safe to show or paste into an issue: this probe
  /// never reads records, so no cardholder data is collected.
  String get summary {
    final buffer = StringBuffer();
    for (final exchange in exchanges) {
      buffer.writeln(exchange.toString());
    }
    buffer.writeln(
      'AIDs offered: ${offeredAids.isEmpty ? 'none' : offeredAids.join(', ')}',
    );
    buffer.writeln('AID selected: ${selectedAid ?? 'none'}');
    if (error != null) buffer.writeln('Error: $error');
    return buffer.toString();
  }
}

/// Checks that a contactless card can be reached and that a payment
/// application can be selected.
///
/// This is a connectivity and entitlement check, not a card reader: it
/// stops right after SELECT and never issues READ RECORD, so it cannot
/// return a card number.
abstract final class CardNfcProbe {
  static CardNfcPlatform get _platform => CardNfcPlatform.instance;

  /// Whether the device can read contactless cards right now.
  static Future<bool> isAvailable() => _platform.isAvailable();

  /// Opens a session, selects the PPSE directory, then selects the first
  /// supported payment application it lists.
  static Future<NfcProbeReport> run({
    String prompt = 'Hold your card near the top of the phone',
  }) async {
    final exchanges = <NfcExchange>[];
    var offeredAids = <String>[];
    String? selectedAid;

    try {
      await _platform.connect(prompt: prompt);

      final ppse = await _send(
        exchanges,
        'SELECT PPSE',
        CommandApdu.select(EmvIds.ppse),
      );
      if (!ppse.isSuccess) {
        await _platform.close(errorMessage: 'This card did not answer');
        return NfcProbeReport(
          exchanges: exchanges,
          offeredAids: const [],
          selectedAid: null,
          error: const CardNfcException(
            CardNfcException.sessionError,
            'PPSE was rejected by the card',
          ),
        );
      }

      offeredAids = TlvParser.findAll(
        ppse.tlv,
        EmvIds.tagAid,
      ).map((tlv) => tlv.hex).toList(growable: false);

      for (final aid in EmvIds.supported) {
        final hex = TlvParser.toHex(aid);
        // Prefer what the card advertised, but try the known AIDs anyway:
        // some cards answer a direct SELECT without listing it in the PPSE.
        if (offeredAids.isNotEmpty &&
            !offeredAids.any((a) => a.startsWith(hex))) {
          continue;
        }
        final response = await _send(
          exchanges,
          'SELECT $hex',
          CommandApdu.select(aid),
        );
        if (response.isSuccess) {
          selectedAid = hex;
          break;
        }
      }

      await _platform.close(
        message: selectedAid == null ? null : 'Card read',
        errorMessage: selectedAid == null
            ? 'No payment application found'
            : null,
      );
      return NfcProbeReport(
        exchanges: exchanges,
        offeredAids: offeredAids,
        selectedAid: selectedAid,
      );
    } on CardNfcException catch (e) {
      await _platform.close(
        errorMessage: e.isCancelled ? null : 'Could not read the card',
      );
      return NfcProbeReport(
        exchanges: exchanges,
        offeredAids: offeredAids,
        selectedAid: selectedAid,
        error: e,
      );
    }
  }

  static Future<ResponseApdu> _send(
    List<NfcExchange> log,
    String label,
    CommandApdu command,
  ) async {
    final bytes = command.toBytes();
    final reply = await _platform.transceive(bytes);
    final response = ResponseApdu.fromBytes(reply);
    log.add(
      NfcExchange(
        label: label,
        command: TlvParser.toHex(bytes),
        response: response,
      ),
    );
    return response;
  }
}

/// Exposed for tests that feed recorded card replies.
@visibleForTesting
Uint8List hexToBytes(String hex) => TlvParser.fromHex(hex);
