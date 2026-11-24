import 'dart:typed_data';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';

/// Replays recorded card replies, keyed by the command that triggers them.
///
/// Anything not in [replies] answers `6A82`, "file not found", which is what
/// a real card says when asked for a record it does not have.
class FakeNfcPlatform implements CardNfcPlatform {
  FakeNfcPlatform({
    this.replies = const {},
    this.connectError,
    this.available = true,
  });

  final Map<String, String> replies;
  final CardNfcException? connectError;
  final bool available;

  final commands = <String>[];
  bool closed = false;
  String? closeMessage;
  String? closeErrorMessage;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> connect({required String prompt}) async {
    if (connectError != null) throw connectError!;
  }

  @override
  Future<Uint8List> transceive(Uint8List command) async {
    final hex = TlvParser.toHex(command);
    commands.add(hex);
    return TlvParser.fromHex(replies[hex] ?? '6A82');
  }

  @override
  Future<void> close({String? message, String? errorMessage}) async {
    closed = true;
    closeMessage = message;
    closeErrorMessage = errorMessage;
  }
}

/// Commands the reader sends, as hex.
const selectPpse = '00A404000E325041592E5359532E444446303100';
const selectVisa = '00A4040007A000000003101000';
const selectMastercard = '00A4040007A000000004101000';
const readRecord1 = '00B2010C00';

/// GET PROCESSING OPTIONS for a PDOL asking for 9F66 (4) and 9F1A (2).
const gpoWithPdol = '80A8000008830636004000084000';

/// GET PROCESSING OPTIONS when the card asks for nothing.
const gpoEmpty = '80A8000002830000';

/// PPSE reply advertising one Visa application.
const visaDirectory =
    '6F2F'
    '840E325041592E5359532E4444463031'
    'A51DBF0C1A6118'
    '4F07A0000000031010'
    '500A56495341204445424954'
    '870101'
    '9000';

/// SELECT AID reply whose PDOL asks for 9F66 and 9F1A.
const visaFci =
    '6F20'
    '8407A0000000031010'
    'A515'
    '500A56495341204445424954'
    '9F38069F66049F1A02'
    '9000';

/// GPO reply in format 1: tag 80 with the interchange profile then a
/// locator pointing at SFI 1, record 1.
const gpoFormat1 =
    '8006198008010100'
    '9000';

/// A record holding Track 2 for 4111 1111 1111 1111 expiring 12/28, plus a
/// cardholder name, which real cards rarely carry.
const recordWithTrack2 =
    '7021'
    '57104111111111111111D281220100000000'
    '5F200C4A4F484E204120534D495448'
    '9000';
