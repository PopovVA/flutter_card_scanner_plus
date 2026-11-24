import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_nfc_platform.dart';

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
