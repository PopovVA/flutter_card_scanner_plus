## 0.2.0 (unreleased)

### Breaking

- `CardBrand` gained `discover`, `jcb`, `diners` and `unionpay`. A `switch`
  over the enum without a `default` clause stops compiling until the new
  values are handled.
- `ScanRequirements.preferredTimeoutFrames` is gone. Use `preferredTimeout`,
  which takes a `Duration`.

### Completing a scan

- A confirmed field is kept. Frames that recognize nothing no longer take it
  away, which is what broke cards printed on both sides: with the card turned
  over, the votes behind the number and the date were evicted and the result
  went backwards.
- A cardholder name, once confirmed, is not replaced. Background text used to
  collect votes while the card was turned and win.
- A different number overwrites nothing until it is confirmed in its own
  right, with more votes than the number already held. Two cards in view no
  longer swap the result back and forth.
- Votes carry the number visible in the same frame, so one card's expiry date
  and name can never be attributed to another.
- `ScanRequirements.preferredTimeout` and `preferredGrace` are `Duration`s and
  replace `preferredTimeoutFrames`. Time is measured from the frames
  themselves, so a scan in the background does not time out while nothing is
  being recognized, and a preferred field that is mid-confirmation when the
  timeout expires is granted the grace period rather than discarded.
- `ScanRequirements.twoSided` waits 15 seconds for a name on the other side.
- `CardScannerState.confirming` lists the fields that have a candidate but not
  yet enough agreement, for a UI that wants to show progress.
- `ScanSession` is the interface the controller drives, and
  `CardScannerController(session: ...)` takes an implementation of it. An app
  can change the scan rules without forking the camera pipeline.

### Recognition

- Discover, JCB, Diners Club and UnionPay cards are read. Diners Club means
  the shortest accepted number is now 14 digits. UnionPay ranges issued
  outside the Luhn checksum are still rejected.
- `CardBrand.groupingFor(length)` formats a number by its length, which is
  what Diners Club needs: 4-6-4 on a 14 digit card, the usual blocks on 16.
- A cardholder name split across several OCR boxes is read. Engines return
  a printed name as one box per word, so "ADA" and "LOVELACE" only became a
  name once the row was assembled.
- A logo, a tier label or a stray number sharing the name's row no longer
  hides the name: words that cannot belong to a name are dropped from both
  ends of the row before what is left is tested. A row of nothing else,
  "VISA PLATINUM", still yields nothing.
- The name is ranked by where it sits relative to the number: flush with
  its left edge, close above or below it. Text starting past the middle of
  the number is penalised, which is what let "RECYCLED PLASTIC", printed
  beside the name block, win on one card. Material claims are stop words
  now as well.
- `CardFrameParser.groupIntoRows` is public, and `groupRowParts` returns the
  same rows with their original lines, so a caller can drop some of them and
  still know where the rest sat.
- `NameParser.parseRows` takes those rows. `NameParser.parse` still takes
  plain lines and treats each as its own row.
- `CardScannerView.frameRegionPadding` replaces a fixed margin of 15% of the
  frame height that was added around the frame before OCR. It defaults to 0,
  so OCR reads exactly what the user sees inside the frame. That margin is
  how text next to the card, a keyboard for instance, supplied a cardholder
  name.
- The region of interest is recalculated when the frame geometry or the
  controller changes, not only when the view is resized. A replaced
  controller is also started, so the preview is not left black.

## 0.1.3

Housekeeping only; the public API is unchanged.

- The example project no longer carries a development team, so it does not
  drag anyone else's Apple account into the package and builds once you pick
  your own team.
- The podspec credits the publisher rather than a personal address.
- CI refuses a build that carries a signing team, a home directory path, a
  personal address or a credential.
- README states that the CVV is intentionally never read.

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
