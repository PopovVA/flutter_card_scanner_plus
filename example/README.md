# flutter_card_scanner_plus example

Demonstrates the package:

- `CardScannerPage` with the `standard`, `numberOnly` and `full` presets
- `CardScannerView` with a custom `overlayBuilder` that prints raw per frame candidates
- `CardScanner.scanImage` on a photo picked from the gallery

Run it on a real device; simulators and emulators do not have a usable camera.

```bash
flutter run --release
```

## Signing

The project carries no development team on purpose, so it does not drag
anyone else's account into the package. Open `ios/Runner.xcworkspace`, pick
your own team under Signing and Capabilities, and build.
