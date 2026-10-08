import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void expectSplit(String printed, String given, String family) {
    final name = CardholderName.split(printed);
    expect(name.given, given, reason: printed);
    expect(name.family, family, reason: printed);
  }

  test('two words', () => expectSplit('ADA LOVELACE', 'ADA', 'LOVELACE'));

  test('a middle initial stays with the given name', () {
    expectSplit('WREN A. NGUYEN', 'WREN A.', 'NGUYEN');
  });

  test('a middle name stays with the given name', () {
    expectSplit('WREN ADA NGUYEN', 'WREN ADA', 'NGUYEN');
  });

  test('particles belong to the surname', () {
    expectSplit('MARIA DE LA CRUZ', 'MARIA', 'DE LA CRUZ');
    expectSplit('LUIS VAN DER BERG', 'LUIS', 'VAN DER BERG');
    expectSplit('JOAO DOS SANTOS', 'JOAO', 'DOS SANTOS');
    expectSplit('ANNA VON TRAPP', 'ANNA', 'VON TRAPP');
    expectSplit('PAOLO DELLA ROVERE', 'PAOLO', 'DELLA ROVERE');
  });

  test('a surname that is only particles and a word', () {
    expectSplit('DE LA CRUZ', '', 'DE LA CRUZ');
  });

  test('a hyphenated surname is one word', () {
    expectSplit('AMARA OKOYE-BELL', 'AMARA', 'OKOYE-BELL');
  });

  test('a single word is taken as the surname', () {
    expectSplit('LOVELACE', '', 'LOVELACE');
  });

  test('extra spaces and padding', () {
    expectSplit('  ADA   LOVELACE  ', 'ADA', 'LOVELACE');
  });

  test('nothing usable', () {
    expect(CardholderName.split('').isEmpty, isTrue);
    expect(CardholderName.split('   ').isEmpty, isTrue);
  });

  test('a particle is matched whatever its punctuation', () {
    expectSplit("MARIA DE' MEDICI", 'MARIA', "DE' MEDICI");
  });

  test('the result compares by value', () {
    expect(
      CardholderName.split('ADA LOVELACE'),
      const CardholderName(given: 'ADA', family: 'LOVELACE'),
    );
  });

  test('a scan result splits its own name', () {
    const result = CardScanResult(cardholderName: 'MARIA DE LA CRUZ');
    expect(result.splitName?.family, 'DE LA CRUZ');
    expect(const CardScanResult().splitName, isNull);
  });
}
