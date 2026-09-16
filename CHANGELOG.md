## 0.1.2

- `CardScannerPage` controls follow the app theme by default: `AppBarTheme.foregroundColor`, then `AppBarTheme.iconTheme.color`, then white. `foregroundColor` overrides the theme when set.

## 0.1.1

- `CardScannerPage`: close button, torch toggle and title are now always drawn in `foregroundColor` (white by default), regardless of the app's `AppBarTheme`. Previously a dark `AppBarTheme.iconTheme` made them invisible on the camera preview.
- New `foregroundColor` parameter on `CardScannerPage` and `CardScannerPage.show`.

## 0.1.0

Initial release.

- Camera scanning on iOS (AVFoundation + Vision) and Android (CameraX + ML Kit)
- Visa, Mastercard and American Express: number, expiry date, cardholder name
- `CardScannerPage` with a default overlay, `CardScannerView` with `overlayBuilder`
- `ScanRequirements` with required and preferred fields
- `CardScanner.scanImage` for static images
