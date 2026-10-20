## Unreleased

### Web

- The scanner runs in a browser. Camera through `getUserMedia`, preview as
  a `<video>` element behind a platform view, recognition by PaddleOCR
  PP-OCRv4 in a Web Worker. The Dart core, the frame, the voting and the
  parser are the same ones the phones use.
- `dart run flutter_card_scanner_plus:install_web` puts the engine in an
  app's `web/` folder: about 38 MB of OpenCV, ONNX runtime WebAssembly and
  models, fetched from npm at pinned versions and checked against pinned
  hashes. They are deliberately not package assets, which would add 38 MB
  to every iOS and Android build.
- `ScanRequirements.web` votes on fewer frames, because a browser manages
  about one a second rather than eight.
- `CameraHandle.torchAvailable` says whether the camera has a torch worth
  offering. Several browsers report one they cannot light, so the web
  implementation asks the track and says no when it is not sure, and
  `CardScannerPage` hides the button rather than disabling it.
- Three failed frames in a row report `ocrUnavailable` and replace the
  worker, instead of a scan that can never finish. A frame has 20 seconds
  and the engine has two minutes to load.
- An open camera that arrives after the scanner was closed closes itself.
  A browser permission prompt can sit on screen for minutes, and the camera
  stayed on when the answer came too late.
- `README.md` carries the Content-Security-Policy the worker needs and what
  it is for.

### Breaking

- `CardScannerPlatform` gained `buildPreview`. Anything implementing that
  interface, which is only needed to fake the platform in tests, has to
  provide it.

### Preview

- The preview widget comes from the platform rather than from the view, so
  a platform without a texture can supply its own. iOS and Android are
  unchanged: they still return a `RotatedBox` around a `Texture`.
- `CardScannerController.buildPreview` exposes it for an app drawing its own
  preview around the controller. The view keeps the geometry around it, the
  `ClipRect` and the `BoxFit.cover` scaling, because the region of interest
  is computed from that same geometry.

### Recognition

- A card word that is also a common name keeps its place in one. `BLACK`,
  `BLUE`, `CASH`, `CHASE`, `CHIP`, `GOLD`, `GOOD`, `GREEN`, `MASTER`,
  `SAPPHIRE`, `SILVER`, `WELLS` and `WISE` are in the new
  `NameParser.nameLikeStopWords`, and are read as part of a name when the
  same line carries a word that can only be a name. "ALICE GREEN" and
  "JOHN A BLACK" were being cut down to "ALICE" and "JOHN A"; "VISA GOLD"
  and "CHASE SAPPHIRE" are still card art.

### Splitting a name

- The first word of a printed name is always the given name.
  `CardholderName.split('DEL SMITH')` gave no given name and the surname
  "DEL SMITH", because DEL is also a particle. So were LE and DU, which are
  given names at least as often.
- A generational suffix stays with the surname.
  `split('JOHN SMITH JR')` gave the surname "JR". `CardholderName.suffixes`
  holds JR, SR, II, III and IV, and punctuation is ignored.
- `split('DE LA CRUZ')` now gives "DE" and "LA CRUZ" rather than no given
  name at all, which follows from the rule above.

### Frame

- `CardScannerView.maxFrameWidth` caps the frame at 440 logical pixels,
  whatever the fractions allow. On an 810 by 1080 tablet the frame was 713
  by 450, and in landscape 950 by 599, so a card had to be held against the
  lens to fill it. Phones are unaffected: 88% of a 390 point screen is
  already narrower than the limit.

### Documentation

- Every public declaration carries its own dartdoc, and
  `public_member_api_docs` is enabled so it stays that way.

## 0.2.0

### Breaking

- `CardBrand` gained `discover`, `jcb`, `diners` and `unionpay`. A `switch`
  over the enum without a `default` clause stops compiling until the new
  values are handled.
- `ScanRequirements.preferredTimeoutFrames` is gone. Use `preferredTimeout`,
  which takes a `Duration`.
- `CardScannerPlatform` gained an `errors` stream. Anything implementing that
  interface, which is only needed to fake the platform in tests, has to
  provide it.

### API

- `CardholderName.split` and `CardScanResult.splitName` divide a printed name
  into given and family parts, keeping middle names and initials with the
  given name and particles with the surname. A card prints one line and never
  says where the surname starts, so this is a convention; let people correct
  it.
- `CardFrameParser.groupIntoRows` is public, with `groupRowParts` beside it.
  See the recognition section.
- The default colour of the controls over the preview is unchanged: it still
  follows `AppBarTheme`, with `foregroundColor` to override it.

### The built-in UI

- The default overlay says what the scanner is still looking for rather than
  always showing the same line: the expiry date, or the other side of the
  card for the name. People read "number recognized" and assumed it had
  frozen while it was waiting for the date.
- A small spinner runs while any field is found and the scan is not finished.
- `CardFrameOverlay.enableHaptics` plays one light tap per change of prompt,
  so a card can be turned over without watching the screen. Off by default.
- `CardScannerStrings` holds every string the scanner shows, with English
  defaults, and `CardScannerPage` and `CardFrameOverlay` take one. No new
  dependency: build it from your own localizations.
- The error screen distinguishes a refusal from a failure and from a camera
  held by another app, offers a retry, and offers to open the system settings
  when the app supplies `onOpenSettings`. The close button is always
  reachable, and opening the camera shows progress instead of a black screen.
- Closing the page takes the preview down a frame before the route leaves, so
  the exit animation never draws a texture that is being released.

### Camera lifecycle

- `stop` completes only once the platform has finished tearing the session
  down. It used to be fire and forget: Android posted the teardown to the
  main handler and dropped its reference immediately, iOS stopped on its own
  queue, and a quick reopen could start a new session on top of a pending
  one. That is the "unable to start camera" black preview.
- Android unbinds only its own use cases. `unbindAll` on the process wide
  `ProcessCameraProvider` was reaching into any other session bound to it.
- Start and stop run one after another on a controller, so a reopen waits for
  the teardown before it rather than racing it. A start the app cancelled by
  stopping reports `cancelled`, which is not surfaced as an error.
- `CardScannerView` releases the camera when the app is backgrounded and
  takes it back on return. It deliberately ignores `inactive`, which iOS also
  reports for a permission dialog.
- A camera that fails after it started now reaches Dart instead of freezing
  the preview: an `AVCaptureSession` runtime error, an interruption by
  another app, a CameraX camera state error, or the Android Activity going
  away during a configuration change. `value.error` is set and `isRunning`
  becomes false. New codes: `cameraInterrupted`, `cameraDetached`,
  `cancelled`.
- Android keeps a recognized line only when at least 70% of it lies inside
  the guide. The test was on the line's centre, so a line half outside
  counted, which is how a keyboard beside the card offered its labels as a
  cardholder name. iOS already restricted recognition to the guide.

### Orientation

- Android follows the rotation of the display the activity is drawn on,
  through a `DisplayManager.DisplayListener`, rather than the physical
  orientation of the device. An app locked to portrait keeps an upright
  guide however the phone is held, and turning the buffer there left the
  preview sideways inside it.
- iOS reads the interface orientation on the main thread only, and picks the
  foreground window scene explicitly. `connectedScenes` is a set, so taking
  the first element could read the wrong window.
- A frame recognized before a rotation reached the camera is dropped instead
  of scored. Its boxes are in the previous orientation and were filtered by
  the previous region of interest, so it could move a field relative to the
  number or confirm text from off the card. Frames resume as soon as the new
  region is applied, or after 400 ms if nothing applies one.

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
