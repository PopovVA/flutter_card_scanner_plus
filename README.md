<p align="center">
  <img src="https://raw.githubusercontent.com/PopovVA/flutter_card_scanner_plus/main/doc/banner.svg" alt="flutter_card_scanner_plus" width="100%">
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_card_scanner_plus"><img src="https://img.shields.io/pub/v/flutter_card_scanner_plus.svg?label=pub&color=blue" alt="pub version"></a>
  <a href="https://github.com/PopovVA/flutter_card_scanner_plus/actions/workflows/ci.yml"><img src="https://github.com/PopovVA/flutter_card_scanner_plus/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/PopovVA/flutter_card_scanner_plus/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT"></a>
  <img src="https://img.shields.io/badge/platforms-iOS%20%7C%20Android-lightgrey.svg" alt="platforms">
</p>

Scan a payment card with the camera and get its number, expiry date and cardholder name back as a typed result. Recognition runs fully on the device using the platform OCR engines: Vision on iOS and ML Kit on Android. There is no third party camera plugin, no cloud service and no network access.

Supported networks: **Visa**, **Mastercard**, **American Express**.

## Highlights

- **One line integration.** `CardScannerPage.show(context)` opens a ready screen and returns a `CardScanResult`.
- **Bring your own UI.** `CardScannerView` renders the camera preview and lets you draw anything on top with `overlayBuilder`.
- **Robust recognition.** Luhn check, BIN detection, repair of common OCR confusions (`O` vs `0`, `I` vs `1`, `S` vs `5`), and multi frame voting so a single misread never leaks into the result.
- **Configurable fields.** Decide which fields are required, which are nice to have, and how long to wait for them.
- **Static images too.** `CardScanner.scanImage(bytes)` recognizes a card in a photo from the gallery.
- **Optional NFC.** Read the number and expiry straight off the chip. Apps that do not use it inherit no permission and no framework.
- **Privacy by design.** Frames never leave the native layer. Only recognized strings and bounding boxes cross the platform channel. `toString()` on results masks the number.

<p align="center">
  <img src="https://raw.githubusercontent.com/PopovVA/flutter_card_scanner_plus/main/doc/overlays.svg" alt="Default overlay and custom overlay" width="100%">
</p>

## Install

```bash
flutter pub add flutter_card_scanner_plus
```

### iOS

Add a camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to scan your payment card.</string>
```

Minimum deployment target is iOS 15.

### Android

Nothing to configure. The plugin declares the `CAMERA` permission and requests it at runtime. Minimum SDK is 24 (Android 7.0). The ML Kit text recognition model is bundled with the app, so scanning works offline and does not depend on Google Play Services being up to date.

## Quick start

```dart
import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';

final card = await CardScannerPage.show(context);
if (card != null) {
  print(card.formattedNumber);   // 4242 4242 4242 4242
  print(card.brand);             // CardBrand.visa
  print(card.formattedExpiry);   // 12/28
  print(card.cardholderName);    // JOHN A SMITH (may be null)
}
```

`CardScannerPage` shows a full screen scanner with a card shaped frame, a torch toggle and a close button. It pops with the result as soon as the scan is complete, or with `null` if the user dismisses it.

## Custom UI

Use `CardScannerController` and `CardScannerView` when the default page does not fit your design. The controller is a `ValueNotifier<CardScannerState>`, so it works with `ValueListenableBuilder` or any state management you already use.

```dart
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = CardScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CardScannerView(
      controller: _controller,
      overlayBuilder: (context, state, cardRect) {
        // cardRect is where the card frame sits, in this widget's coordinates.
        return Stack(
          children: [
            Positioned.fromRect(
              rect: cardRect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: state.isComplete ? Colors.green : Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (state.result.hasNumber)
              Positioned(
                left: 0,
                right: 0,
                top: cardRect.bottom + 24,
                child: Text(
                  state.result.formattedNumber!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                ),
              ),
          ],
        );
      },
    );
  }
}
```

`CardScannerState` gives you everything needed for live feedback:

| Field | What it is |
|---|---|
| `result` | Aggregated `CardScanResult`, updated as fields get confirmed |
| `lastFrame` | Raw candidates from the most recent OCR frame, useful for "live" highlighting |
| `isRunning`, `torchEnabled`, `error` | Camera state |

The view keeps the OCR region of interest in sync with the card frame automatically, so text outside the frame is ignored.

### One shot scanning

```dart
final controller = CardScannerController();
final card = await controller.scanOnce(); // starts the camera, completes when done
```

### Reusing the default overlay

`CardFrameOverlay` is exported, so you can place it inside your own builder and add controls around it:

```dart
overlayBuilder: (context, state, cardRect) => Stack(
  children: [
    CardFrameOverlay(state: state, cardRect: cardRect, hint: 'Hold steady'),
    Positioned(bottom: 40, left: 0, right: 0, child: MyCancelButton()),
  ],
),
```

## Choosing which fields you need

`ScanRequirements` controls when a scan is considered complete.

```dart
CardScannerPage.show(
  context,
  requirements: const ScanRequirements(
    required: {CardField.number, CardField.expiry}, // wait for these
    preferred: {CardField.name},                     // wait briefly, then skip
    preferredTimeoutFrames: 12,                      // about 1.5 s
  ),
);
```

| Preset | Required | Preferred | Use when |
|---|---|---|---|
| `standard` | number, expiry | name | Default. Fast, and the name is included when it is legible. |
| `numberOnly` | number | none | You only need the PAN. |
| `full` | number, expiry, name | none | The name is mandatory. Waits until it is recognized. |
| `fast` | number, expiry | none | Demos and tests. Accepts the first Luhn valid frame. |

The number is always required. A field that is neither required nor preferred is still filled in when it happens to be recognized, but never delays completion.

## NFC (optional)

The package can also talk to the chip over NFC. This is **opt in at the
source level**: an app that never calls the NFC API ships without the
Android permission and without touching CoreNFC, so nothing new shows up in
its manifest and nothing changes about its store listing.

That is the whole point of how it is wired:

- The plugin's Android manifest does **not** declare `android.permission.NFC`.
  Apps that want NFC add the one line themselves. Apps that do not, inherit
  nothing.
- On iOS `CoreNFC` is weak linked and the API is only reachable with the NFC
  entitlement, which only the app can add.

### Android setup

Add the permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.NFC" />
```

Without it the NFC API reports `nfcUnavailable` and everything else keeps
working.

### iOS setup

1. In Xcode, Runner target, Signing and Capabilities, add **Near Field
   Communication Tag Reading**. This creates `Runner.entitlements` with
   `com.apple.developer.nfc.readersession.formats` set to `TAG`, and enables
   the capability for your App ID.
2. Add to `ios/Runner/Info.plist` the purpose string and the identifiers the
   app is allowed to select:

```xml
<key>NFCReaderUsageDescription</key>
<string>NFC is used to read the card you hold against the phone.</string>
<key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
<array>
  <string>2PAY.SYS.DDF01</string>
  <string>A0000000031010</string>
  <string>A0000000041010</string>
  <string>A00000002501</string>
</array>
```

Requires iOS 13 and an iPhone 7 or newer.

### What the chip gives you

| Field | Over NFC |
|---|---|
| Card number | yes, exactly, no OCR guesswork |
| Expiry date | yes |
| Cardholder name | rarely, most cards leave it empty |
| CVV | never, it is not on the chip |

So NFC is the precise path for the number and the date, and the camera stays
the better path for the name.

### Reading a card

```dart
if (await CardNfcReader.isAvailable()) {
  final card = await CardNfcReader.read(
    prompt: 'Hold your card near the top of the phone',
  );
  print(card.formattedNumber); // 4111 1111 1111 1111
  print(card.formattedExpiry); // 12/28
}
```

It returns the same `CardScanResult` as the camera, so the rest of your code
does not care which way the card was read. `CardNfcException` is thrown when
the session fails; check `isCancelled` to stay quiet when the user simply
closed the sheet.

The read performs the same steps a contactless terminal does, minus
everything to do with paying: select the directory, select a payment
application, ask for its file locator, read those records. No cryptogram is
requested and no transaction is started, so tapping a card cannot move money.

Cards outside the US may want a different country and currency in the data
the terminal presents. Pass a profile if a card refuses to answer:

```dart
await CardNfcReader.read(
  profile: const TerminalProfile(countryCode: 0x0643, currencyCode: 0x0978),
);
```

### When a card will not read

`CardNfcProbe` stops right after SELECT and reports what the card said. It
never issues READ RECORD, so it cannot return card data and its output is
safe to paste into a bug report.

```dart
print((await CardNfcProbe.run()).summary);
```

## Scanning a photo

```dart
final bytes = await pickedFile.readAsBytes();
final card = await CardScanner.scanImage(bytes);
```

A single image is a single frame, so no voting is applied. `isComplete` tells you whether the required fields were found.

## The result

```dart
class CardScanResult {
  String? number;          // 4242424242424242
  CardBrand? brand;        // visa, mastercard, amex
  int? expiryMonth;        // 1..12
  int? expiryYear;         // 2028
  String? cardholderName;  // JOHN A SMITH
  bool isComplete;

  String? formattedNumber; // 4242 4242 4242 4242 (4-6-5 for Amex)
  String? maskedNumber;    // •••• 4242
  String? last4;
  String? formattedExpiry; // 12/28
  bool isExpired({DateTime? now});
}
```

`toString()` prints the masked number only, so results are safe to log.

## How it works

<p align="center">
  <img src="https://raw.githubusercontent.com/PopovVA/flutter_card_scanner_plus/main/doc/pipeline.svg" alt="Recognition pipeline" width="100%">
</p>

1. The native camera session renders into a Flutter texture and hands the same frame buffer to the OCR engine. There is no copy into Dart.
2. OCR runs only inside the region under the card frame, about eight times per second.
3. Recognized lines cross the platform channel as strings with normalized bounding boxes.
4. Dart merges fragments that sit on one visual row, then runs three parsers:
   - **Number**: candidate digit runs are repaired for OCR confusions, validated with Luhn, matched against Visa, Mastercard and Amex BIN ranges and length rules.
   - **Expiry**: `MM/YY` and `MM/YYYY`. When a card prints several dates (valid from, member since, valid thru) the latest one wins.
   - **Name**: upper case Latin lines without digits, filtered by a stop list of labels, tiers, networks and issuers, ranked by position relative to the number.
5. A sliding window vote confirms each field across frames. The scan completes when the required fields are confirmed and the preferred ones either arrived or timed out.

Everything in step 4 and 5 is plain Dart with no platform dependencies, and it is covered by unit tests with realistic OCR output, including misreads.

## Security notes

- Camera frames are processed in memory and never written to disk, logged or transmitted.
- The package does not store the result anywhere. What you do with it is up to your app.
- This package is not a PCI DSS certified component. If your app is in scope for PCI, treat the scanned PAN as cardholder data from the moment it reaches your code.
- Consider hiding the scanner screen from screenshots and the app switcher in sensitive apps. That is intentionally left to the app, since the right behaviour differs per product.

## Limitations

- The CVV / CVC is never read, by design. It is the proof that the cardholder is entering it knowingly, and capturing it from the camera would put every app using this package deeper into PCI DSS scope. Ask for it in a text field after the scan.
- Visa, Mastercard and American Express only. Other networks are rejected even when the number is Luhn valid.
- Cardholder name detection is heuristic. Embossed names on busy backgrounds, names with non Latin characters, and cards without a printed name will come back as `null`.
- Portrait orientation only.

## Example

The [example app](example) shows the default page, the presets, a custom overlay with live per frame fields, and scanning from the gallery.

```bash
cd example
flutter run
```

## Contributing

Issues and pull requests are welcome. If a card is not recognized, the most helpful report includes the raw OCR lines: run the example's custom overlay, which prints the candidates from each frame, and paste what you see (with the number partially masked).

Run the checks locally before opening a PR:

```bash
flutter analyze
flutter test
```

## License

MIT. See [LICENSE](LICENSE).
