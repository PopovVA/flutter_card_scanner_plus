import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/card_scan_result.dart';
import 'apdu.dart';
import 'nfc_platform.dart';
import 'pdol.dart';
import 'tlv.dart';
import 'track2.dart';

/// One entry of the Application File Locator: which records to read.
@immutable
class AflEntry {
  const AflEntry({
    required this.sfi,
    required this.firstRecord,
    required this.lastRecord,
  });

  /// Short file identifier.
  final int sfi;
  final int firstRecord;
  final int lastRecord;

  @override
  String toString() => 'AflEntry(sfi $sfi, records $firstRecord..$lastRecord)';
}

/// Reads a contactless payment card over NFC.
///
/// The flow is the one a contactless terminal performs, minus everything to
/// do with paying: select the directory, select a payment application, ask
/// for its file locator, read those records, and pull the card number and
/// expiry date out of them. No cryptogram is requested and no transaction is
/// started, so tapping a card here cannot move money.
abstract final class CardNfcReader {
  static CardNfcPlatform get _platform => CardNfcPlatform.instance;

  /// Whether this device can read contactless cards right now.
  ///
  /// `false` when the hardware is missing or off, when the app has no NFC
  /// entitlement on iOS, or when it did not declare `android.permission.NFC`.
  static Future<bool> isAvailable() => _platform.isAvailable();

  /// Reads the card the user taps.
  ///
  /// [prompt] is shown in the iOS system sheet and ignored on Android, where
  /// the app draws its own UI. Throws [CardNfcException] when the session
  /// fails or the user cancels.
  ///
  /// The cardholder name is almost always absent from the chip, so expect
  /// [CardScanResult.cardholderName] to be `null` even on a good read.
  static Future<CardScanResult> read({
    String prompt = 'Hold your card near the top of the phone',
    TerminalProfile profile = TerminalProfile.standard,
  }) async {
    await _platform.connect(prompt: prompt);
    try {
      final result = await _readCard(profile);
      if (result == null) {
        await _platform.close(errorMessage: 'Could not read this card');
        throw const CardNfcException(
          CardNfcException.sessionError,
          'No card number found on the chip',
        );
      }
      await _platform.close(message: 'Card read');
      return result;
    } on CardNfcException {
      rethrow;
    } catch (e) {
      await _platform.close(errorMessage: 'Could not read this card');
      throw CardNfcException(CardNfcException.sessionError, '$e');
    }
  }

  static Future<CardScanResult?> _readCard(TerminalProfile profile) async {
    final ppse = await _send(CommandApdu.select(EmvIds.ppse));
    final offered = ppse.isSuccess
        ? TlvParser.findAll(ppse.tlv, EmvIds.tagAid).map((t) => t.hex).toList()
        : const <String>[];

    for (final aid in EmvIds.supported) {
      final hex = TlvParser.toHex(aid);
      if (offered.isNotEmpty && !offered.any((a) => a.startsWith(hex))) {
        continue;
      }

      final selected = await _send(CommandApdu.select(aid));
      if (!selected.isSuccess) continue;

      final records = await _readRecords(selected, profile);
      final result = _extract(records);
      if (result != null) return result;
    }
    return null;
  }

  /// Runs GET PROCESSING OPTIONS and reads every record the card lists.
  static Future<List<Tlv>> _readRecords(
    ResponseApdu selected,
    TerminalProfile profile,
  ) async {
    final pdol = TlvParser.find(selected.tlv, EmvIds.tagPdol);
    final pdolData = pdol == null
        ? <int>[]
        : Dol.buildValues(Dol.parse(pdol.value), profile: profile);

    final gpo = await _send(CommandApdu.getProcessingOptions(pdolData));
    final collected = <Tlv>[...selected.tlv, ...gpo.tlv];

    for (final entry in _locateFiles(gpo)) {
      for (
        var record = entry.firstRecord;
        record <= entry.lastRecord;
        record++
      ) {
        final response = await _send(CommandApdu.readRecord(entry.sfi, record));
        if (response.isSuccess) collected.addAll(response.tlv);
      }
    }
    return collected;
  }

  /// Reads the Application File Locator, falling back to a short scan when
  /// the card does not provide one.
  static List<AflEntry> _locateFiles(ResponseApdu gpo) {
    Uint8List? afl;

    // Format 2: a template with the locator in its own tag.
    final tagged = TlvParser.find(gpo.tlv, EmvIds.tagAfl);
    if (tagged != null) {
      afl = tagged.value;
    } else {
      // Format 1: tag 80 holds the interchange profile then the locator.
      final format1 = TlvParser.find(gpo.tlv, 0x80);
      if (format1 != null && format1.value.length > 2) {
        afl = Uint8List.sublistView(format1.value, 2);
      }
    }

    if (afl == null || afl.length < 4) {
      // Some cards answer a blind read of the first files instead.
      return const [
        AflEntry(sfi: 1, firstRecord: 1, lastRecord: 4),
        AflEntry(sfi: 2, firstRecord: 1, lastRecord: 4),
        AflEntry(sfi: 3, firstRecord: 1, lastRecord: 4),
      ];
    }

    final entries = <AflEntry>[];
    for (var i = 0; i + 3 < afl.length; i += 4) {
      final sfi = afl[i] >> 3;
      final first = afl[i + 1];
      final last = afl[i + 2];
      if (sfi == 0 || first == 0 || last < first) continue;
      entries.add(AflEntry(sfi: sfi, firstRecord: first, lastRecord: last));
    }
    return entries;
  }

  /// Pulls the card fields out of everything the card returned.
  static CardScanResult? _extract(List<Tlv> records) {
    Track2Data? card;

    // Track 2 carries the number and the date together, so prefer it.
    for (final tlv in TlvParser.findAll(records, EmvIds.tagTrack2Equivalent)) {
      card = Track2Parser.parse(tlv.hex);
      if (card != null) break;
    }

    // Otherwise fall back to the separate number and date tags.
    if (card == null) {
      for (final tlv in TlvParser.findAll(records, EmvIds.tagPan)) {
        card = Track2Parser.fromPan(tlv.hex);
        if (card != null) break;
      }
    }
    if (card == null) return null;

    var month = card.expiryMonth;
    var year = card.expiryYear;
    if (month == null) {
      final date = TlvParser.find(records, EmvIds.tagExpiryDate);
      final parsed = date == null
          ? null
          : Track2Parser.parseExpiryDate(date.hex);
      if (parsed != null) {
        month = parsed.$1;
        year = parsed.$2;
      }
    }

    return CardScanResult(
      number: card.pan,
      brand: card.brand,
      expiryMonth: month,
      expiryYear: year,
      cardholderName: _cardholderName(records),
      isComplete: true,
    );
  }

  /// Tag `5F20` is ASCII, and is usually absent or a single `/`.
  static String? _cardholderName(List<Tlv> records) {
    final tlv = TlvParser.find(records, EmvIds.tagCardholderName);
    if (tlv == null) return null;
    final name = String.fromCharCodes(
      tlv.value.where((b) => b >= 0x20 && b < 0x7F),
    ).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name == '/') return null;
    return name.toUpperCase();
  }

  static Future<ResponseApdu> _send(CommandApdu command) async =>
      ResponseApdu.fromBytes(await _platform.transceive(command.toBytes()));
}
