import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_nfc_platform.dart';

void main() {
  tearDown(() => CardNfcPlatform.instance = MethodChannelCardNfcPlatform());

  FakeNfcPlatform use(Map<String, String> replies) {
    final fake = FakeNfcPlatform(replies: replies);
    CardNfcPlatform.instance = fake;
    return fake;
  }

  group('CardNfcReader.read', () {
    test('reads number and expiry from Track 2', () async {
      final fake = use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1: recordWithTrack2,
      });

      final card = await CardNfcReader.read();

      expect(card.number, '4111111111111111');
      expect(card.brand, CardBrand.visa);
      expect(card.formattedExpiry, '12/28');
      expect(card.isComplete, isTrue);
      expect(fake.closeMessage, 'Card read');
    });

    test('follows the whole terminal flow in order', () async {
      final fake = use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1: recordWithTrack2,
      });

      await CardNfcReader.read();

      expect(fake.commands, [selectPpse, selectVisa, gpoWithPdol, readRecord1]);
    });

    test('fills the PDOL the card asked for', () async {
      final fake = use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1: recordWithTrack2,
      });

      await CardNfcReader.read();

      // 9F66 gets the transaction qualifiers, 9F1A the country code.
      expect(fake.commands[2], contains('36004000'));
      expect(fake.commands[2], endsWith('084000'));
    });

    test('reads the cardholder name when the chip carries one', () async {
      use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1: recordWithTrack2,
      });

      expect((await CardNfcReader.read()).cardholderName, 'JOHN A SMITH');
    });

    test('ignores a placeholder cardholder name', () async {
      use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        // Same record, but the name is a bare slash.
        readRecord1:
            '7016'
            '57104111111111111111D281220100000000'
            '5F20012F'
            '9000',
      });

      expect((await CardNfcReader.read()).cardholderName, isNull);
    });

    test('falls back to tags 5A and 5F24 when Track 2 is absent', () async {
      use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1:
            '7010'
            '5A084111111111111111'
            '5F2403281231'
            '9000',
      });

      final card = await CardNfcReader.read();
      expect(card.number, '4111111111111111');
      expect(card.formattedExpiry, '12/28');
    });

    test('reads a format 2 GPO reply', () async {
      use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        // Tag 77 with the profile in 82 and the locator in 94.
        gpoWithPdol:
            '770A'
            '82021980'
            '940408010100'
            '9000',
        readRecord1: recordWithTrack2,
      });

      expect((await CardNfcReader.read()).number, '4111111111111111');
    });

    test('scans the first files when the card gives no locator', () async {
      final fake = use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol:
            '80021980'
            '9000',
        readRecord1: recordWithTrack2,
      });

      expect((await CardNfcReader.read()).number, '4111111111111111');
      expect(fake.commands, contains(readRecord1));
    });

    test('skips an application that answers nothing usable', () async {
      final fake = use({
        // The directory offers Visa and Mastercard.
        selectPpse:
            '6F19BF0C16'
            '61094F07A0000000031010'
            '61094F07A0000000041010'
            '9000',
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        // Visa record holds nothing; Mastercard is never reached because
        // its SELECT is not stubbed, so the read must fail cleanly.
        readRecord1:
            '7000'
            '9000',
      });

      await expectLater(CardNfcReader.read(), throwsA(isA<CardNfcException>()));
      expect(fake.commands, contains(selectMastercard));
    });

    test('throws when no card number is on the chip', () async {
      final fake = use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1: '9000',
      });

      await expectLater(
        CardNfcReader.read(),
        throwsA(
          isA<CardNfcException>().having(
            (e) => e.code,
            'code',
            CardNfcException.sessionError,
          ),
        ),
      );
      expect(fake.closeErrorMessage, isNotNull);
    });

    test('propagates a cancelled session', () async {
      CardNfcPlatform.instance = FakeNfcPlatform(
        connectError: const CardNfcException(CardNfcException.cancelled),
      );

      await expectLater(
        CardNfcReader.read(),
        throwsA(
          isA<CardNfcException>().having(
            (e) => e.isCancelled,
            'cancelled',
            isTrue,
          ),
        ),
      );
    });

    test('rejects a number that fails the Luhn check', () async {
      use({
        selectPpse: visaDirectory,
        selectVisa: visaFci,
        gpoWithPdol: gpoFormat1,
        readRecord1:
            '7012'
            '57104111111111111112D281220100000000'
            '9000',
      });

      await expectLater(CardNfcReader.read(), throwsA(isA<CardNfcException>()));
    });

    test('isAvailable is delegated to the platform', () async {
      CardNfcPlatform.instance = FakeNfcPlatform(available: false);
      expect(await CardNfcReader.isAvailable(), isFalse);
    });
  });
}
