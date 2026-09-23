import 'dart:typed_data';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays recorded card replies, keyed by the command that triggers them.
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

const selectPpse = '00A404000E325041592E5359532E444446303100';
const selectVisa = '00A4040007A000000003101000';
const selectMastercard = '00A4040007A000000004101000';

/// PPSE reply advertising one Visa application.
const visaDirectory =
    '6F2F'
    '840E325041592E5359532E4444463031'
    'A51DBF0C1A6118'
    '4F07A0000000031010'
    '500A56495341204445424954'
    '870101'
    '9000';

void main() {
  tearDown(() => CardNfcPlatform.instance = MethodChannelCardNfcPlatform());

  test('selects PPSE then the advertised application', () async {
    final fake = FakeNfcPlatform(
      replies: {
        selectPpse: visaDirectory,
        selectVisa: '6F1A840EA0000000031010A5088801015F2D02656E9000',
      },
    );
    CardNfcPlatform.instance = fake;

    final report = await CardNfcProbe.run();

    expect(fake.commands, [selectPpse, selectVisa]);
    expect(report.offeredAids, ['A0000000031010']);
    expect(report.selectedAid, 'A0000000031010');
    expect(report.isSuccess, isTrue);
    expect(report.error, isNull);
    expect(fake.closed, isTrue);
    expect(fake.closeMessage, 'Card read');
  });

  test('does not try applications the card did not advertise', () async {
    final fake = FakeNfcPlatform(
      replies: {
        selectPpse: visaDirectory,
        selectVisa: '6F0A840EA00000000310109000',
      },
    );
    CardNfcPlatform.instance = fake;

    await CardNfcProbe.run();
    expect(fake.commands, isNot(contains(selectMastercard)));
  });

  test('reports a card that rejects PPSE', () async {
    final fake = FakeNfcPlatform(replies: {selectPpse: '6A82'});
    CardNfcPlatform.instance = fake;

    final report = await CardNfcProbe.run();

    expect(report.isSuccess, isFalse);
    expect(report.selectedAid, isNull);
    expect(report.error?.code, CardNfcException.sessionError);
    expect(fake.closeErrorMessage, isNotNull);
  });

  test('reports an application that answers PPSE but rejects SELECT', () async {
    final fake = FakeNfcPlatform(
      replies: {selectPpse: visaDirectory, selectVisa: '6985'},
    );
    CardNfcPlatform.instance = fake;

    final report = await CardNfcProbe.run();

    expect(report.offeredAids, ['A0000000031010']);
    expect(report.selectedAid, isNull);
    expect(report.isSuccess, isFalse);
  });

  test('surfaces a cancelled session without an error banner', () async {
    final fake = FakeNfcPlatform(
      connectError: const CardNfcException(CardNfcException.cancelled),
    );
    CardNfcPlatform.instance = fake;

    final report = await CardNfcProbe.run();

    expect(report.error?.isCancelled, isTrue);
    expect(fake.commands, isEmpty);
    expect(fake.closeErrorMessage, isNull);
  });

  test('summary carries no card data and lists what happened', () async {
    final fake = FakeNfcPlatform(
      replies: {
        selectPpse: visaDirectory,
        selectVisa: '6F0A840EA00000000310109000',
      },
    );
    CardNfcPlatform.instance = fake;

    final summary = (await CardNfcProbe.run()).summary;

    expect(summary, contains('SELECT PPSE'));
    expect(summary, contains('SW=9000'));
    expect(summary, contains('A0000000031010'));
  });

  test('isAvailable is delegated to the platform', () async {
    CardNfcPlatform.instance = FakeNfcPlatform(available: false);
    expect(await CardNfcProbe.isAvailable(), isFalse);
  });
}
