# flutter_card_scanner_plus example

Demonstrates the package:

- `CardScannerPage` with the `standard`, `numberOnly` and `full` presets
- `CardScannerView` with a custom `overlayBuilder` that prints raw per frame candidates
- `CardScanner.scanImage` on a photo picked from the gallery
- a camera picker, which appears only on macOS, where a Mac has several
  cameras and no obviously right one

Run it on a real device; simulators and emulators do not have a usable camera.

```bash
flutter run --release
```

## macOS

```bash
flutter run -d macos --release
```

The camera picker at the top lists what the Mac has, best first. An
unlocked iPhone nearby shows up as a `continuity` camera and reads a card
about as well as the phone itself; the built-in `builtIn` camera focuses
at roughly arm's length and is noticeably slower. There is no torch button
and the NFC buttons report that macOS cannot read contactless cards.

## Signing

The project carries no development team on purpose, so it does not drag
anyone else's account into the package. Open `ios/Runner.xcworkspace`, pick
your own team under Signing and Capabilities, and build.

## Trying the NFC buttons

NFC needs an entitlement, which only an app can carry, so the example does
not enable it by default. To try it:

1. In Signing and Capabilities, add **Near Field Communication Tag Reading**.
   This wires `Runner/Runner.entitlements`, which is already in the project
   as a reference.
2. `Info.plist` already lists `NFCReaderUsageDescription` and the payment
   identifiers the app may select.

Without that, `CardNfcReader.isAvailable()` returns `false` and the NFC
buttons say so instead of failing. Everything else keeps working.
