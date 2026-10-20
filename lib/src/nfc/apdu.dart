import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'tlv.dart';

/// An ISO 7816-4 command APDU.
@immutable
class CommandApdu {
  /// A command built from its header bytes [cla], [ins], [p1] and [p2],
  /// an optional [data] body and the expected reply length [le].
  const CommandApdu({
    required this.cla,
    required this.ins,
    required this.p1,
    required this.p2,
    this.data = const [],
    this.le = 0x00,
  });

  /// Class byte: which command set this belongs to.
  final int cla;

  /// Instruction byte: which command it is.
  final int ins;

  /// First parameter, whose meaning depends on [ins].
  final int p1;

  /// Second parameter, likewise.
  final int p2;

  /// Command body, empty for a command that carries none.
  final List<int> data;

  /// Expected length. `0x00` means "up to 256 bytes".
  final int le;

  /// SELECT by name (DF name / AID).
  factory CommandApdu.select(List<int> name) =>
      CommandApdu(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: name);

  /// GET PROCESSING OPTIONS with an already built PDOL data object (tag 83).
  factory CommandApdu.getProcessingOptions(List<int> pdolData) => CommandApdu(
    cla: 0x80,
    ins: 0xA8,
    p1: 0x00,
    p2: 0x00,
    data: [0x83, pdolData.length, ...pdolData],
  );

  /// READ RECORD [record] of the short file identifier [sfi].
  factory CommandApdu.readRecord(int sfi, int record) =>
      CommandApdu(cla: 0x00, ins: 0xB2, p1: record, p2: (sfi << 3) | 0x04);

  /// The command as the card expects it on the wire.
  Uint8List toBytes() {
    final out = <int>[cla, ins, p1, p2];
    if (data.isNotEmpty) {
      out.add(data.length);
      out.addAll(data);
    }
    out.add(le);
    return Uint8List.fromList(out);
  }

  @override
  String toString() => 'CommandApdu(${TlvParser.toHex(toBytes())})';
}

/// A response APDU: payload plus the two status bytes.
@immutable
class ResponseApdu {
  /// A reply carrying [data] and the status bytes [sw1] and [sw2].
  const ResponseApdu({
    required this.data,
    required this.sw1,
    required this.sw2,
  });

  /// Payload, without the status bytes.
  final Uint8List data;

  /// First status byte.
  final int sw1;

  /// Second status byte.
  final int sw2;

  /// Status word as a single value, e.g. `0x9000`.
  int get statusWord => (sw1 << 8) | sw2;

  /// `true` when the card reported success (`9000`).
  bool get isSuccess => statusWord == 0x9000;

  /// `true` when the card asks for a GET RESPONSE of [sw2] bytes (`61xx`).
  bool get hasMoreData => sw1 == 0x61;

  /// Parses a raw reply where the last two bytes are the status word.
  factory ResponseApdu.fromBytes(Uint8List bytes) {
    if (bytes.length < 2) {
      return ResponseApdu(data: Uint8List(0), sw1: 0x6F, sw2: 0x00);
    }
    return ResponseApdu(
      data: Uint8List.sublistView(bytes, 0, bytes.length - 2),
      sw1: bytes[bytes.length - 2],
      sw2: bytes[bytes.length - 1],
    );
  }

  /// The payload parsed as BER-TLV.
  List<Tlv> get tlv => TlvParser.parse(data);

  @override
  String toString() =>
      'ResponseApdu(${data.length} bytes, SW=${statusWord.toRadixString(16).toUpperCase().padLeft(4, '0')})';
}

/// Well known EMV identifiers.
abstract final class EmvIds {
  /// Proximity Payment System Environment, the contactless directory.
  static const ppse = [
    0x32, 0x50, 0x41, 0x59, 0x2E, 0x53, 0x59, 0x53,
    0x2E, 0x44, 0x44, 0x46, 0x30, 0x31, // 2PAY.SYS.DDF01
  ];

  /// Application identifier for Visa.
  static const visa = [0xA0, 0x00, 0x00, 0x00, 0x03, 0x10, 0x10];

  /// Application identifier for Mastercard.
  static const mastercard = [0xA0, 0x00, 0x00, 0x00, 0x04, 0x10, 0x10];

  /// Application identifier for American Express.
  static const amex = [0xA0, 0x00, 0x00, 0x00, 0x25, 0x01];

  /// The applications this package will talk to, in the order it tries
  /// them when a card offers more than one.
  static const supported = [visa, mastercard, amex];

  /// Application identifier of an entry in the directory.
  static const tagAid = 0x4F;

  /// Human readable name of an application, such as "VISA CREDIT".
  static const tagApplicationLabel = 0x50;

  /// Track 2 equivalent data: the number and the expiry date in one field.
  static const tagTrack2Equivalent = 0x57;

  /// The card number on its own.
  static const tagPan = 0x5A;

  /// The cardholder name, which most cards no longer return.
  static const tagCardholderName = 0x5F20;

  /// The expiry date, as YYMMDD.
  static const tagExpiryDate = 0x5F24;

  /// One application's entry inside the directory.
  static const tagApplicationTemplate = 0x61;

  /// File Control Information, the envelope a SELECT answers with.
  static const tagFci = 0x6F;

  /// Processing Options Data Object List: what the card wants to be told
  /// before it will start a transaction.
  static const tagPdol = 0x9F38;

  /// Application File Locator: where the records worth reading live.
  static const tagAfl = 0x94;
}
