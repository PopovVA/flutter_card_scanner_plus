## 0.4.0

Field feedback from a production web app, again. In iOS 27 Safari some
sessions run WebAssembly about fifteen times slower than normal. Nothing
fails: the camera opens, the engine loads, and a frame takes 7 to 20
seconds instead of under one, so a scan neither reads the card nor gives
up. The same models on WebGPU read cards on those phones at about a
second a frame. This release is that, and the way out for a browser that
has no WebGPU to fall back on.

Nothing changes on iOS or Android.

### Upgrading


- Run `dart run flutter_card_scanner_plus:install_web` again. There are
  two workers now and one more runtime file, and the scanner asks the
  worker for things a 0.3 worker does not answer. An engine folder left
  over from 0.3 is noticed and reported as `ocrUnavailable` at once, with
  a message saying to run the installer, rather than after a two minute
  wait.
- Serve the second worker, `card_ocr_worker_webgpu.js`, with the same
  Content-Security-Policy as the first. A glob over `card_ocr_worker*.js`
  covers both.
- Serve the engine folder with `Cache-Control: no-cache`. See below.

### Web, two engines


- A second worker, `card_ocr_worker_webgpu.js`, runs the two models on the
  GPU through ONNX Runtime's WebGPU provider. It is built from the same
  sources as `card_ocr_worker.js`, with one import pointed elsewhere and
  one constant changed, so the pipeline and the lines it returns are the
  same. Only the model graphs are on the GPU: OpenCV and the pixel work
  stay in WebAssembly.
- The scanner starts the WebGPU worker where the page has `navigator.gpu`
  and the WebAssembly worker otherwise. A WebGPU engine that fails to load
  is terminated and replaced by the WebAssembly one, and the page stays
  with that choice. There is nothing to configure.
- Loading is a step of its own, apart from reading frames. A failed load
  used to be indistinguishable from a failed frame; now the first means
  try the other build and the second means try the next frame.
- That also fixes the load timeout, which had never applied. The worker
  said it was ready before it had loaded anything, and the engine loaded
  inside the first frame, so tens of megabytes of download ran under that
  frame's 20 seconds rather than the engine's two minutes. On a slow
  connection three such frames ran out, the scanner reported
  `ocrUnavailable`, and the restart threw away what had arrived.
- ONNX Runtime stays on 1.18.0, and the WebGPU worker loads its
  single-threaded `ort-wasm-simd.jsep.wasm`, so the 4 GB shared memory
  that 1.19 asks iOS for does not come back. 1.18 calls
  `GPUAdapter.requestAdapterInfo()`, which browsers have removed, and its
  WebGPU provider does not start without it. The worker puts it back.

### Web, a browser too slow to scan in


- `CardScannerException.tooSlow`. Before it sends a frame, the WebAssembly
  worker times a 66 byte WebAssembly loop: five million steps, fastest of
  three runs. An iPhone takes 4 to 15 ms normally and 55 to 87 ms in the
  slow state. Above 40 ms the scanner frees the engine and reports
  `tooSlow` instead of scanning, so the person is sent to a form at once
  and not after a minute of frames timing out.
- It is asked twice. Before the engine is fetched, so a browser in that
  state does not download 33 MB to throw away; and again after the load,
  because after the load is where the state was measured in the field and
  nobody has shown it is always there before.
- It is not asked on WebGPU. The phones that fail it read cards there.
- `CardScannerStrings.tooSlow` is what `CardScannerPage` shows for it. The
  default tells the person to enter the card by hand.

### Web, knowing which engine ran


- `CardScanner.engineReports` emits an `OcrEngineReport` each time a scan
  loads the browser engine: which `OcrBackend` it was, how long the load
  took, what the benchmark measured, whether it was too slow, and why
  WebGPU was passed over when it was. `CardScanner.lastEngineReport` keeps
  the latest. No card data is in it, and nothing is emitted on a phone.
- The example shows it under the scan buttons.

### Found by running it


- A WebGPU adapter can be software. Headless Chromium on SwiftShader
  loaded the WebGPU engine, read every card correctly, and took forty
  seconds a frame where WebAssembly takes one: every frame past its
  timeout, `ocrUnavailable` after a minute, on a machine that scanned
  fine in 0.3. The WebGPU worker asks for the adapter itself and refuses a
  fallback one, which hands over to WebAssembly in a few milliseconds.
- The fallback from WebGPU to WebAssembly had only been covered by unit
  tests in the app this came from, because no browser it tried failed the
  WebGPU load. Headless Chromium has WebGPU on the page and no adapter
  behind it, so it does. Driven through the example with the fake camera:
  the WebGPU worker fails before it fetches anything, the WebAssembly one
  reads the card, and four more scans on the same page never ask for the
  WebGPU worker again. A missing WebGPU worker file and a software adapter
  go the same way.
- `tooSlow` was run the same way, with the worker's benchmark answer
  replaced by 70 ms. The message is on screen in under a second, and only
  the two worker scripts were fetched.
- `fake_camera.js` handed every open the same stream. The scanner stops
  the tracks it was given when it closes, so every scan after the first on
  a page was looking at a camera already turned off. Each open gets a
  stream of its own now.
- The two builds agree. `ocr_compare.html` takes `?old=` and `?new=` and
  was run both ways over its six cards at two sizes: the 0.3 worker
  against the new WebAssembly one, and the WebAssembly build against the
  WebGPU one on a software adapter. Twelve the same and none different
  each time, text, confidence to the third decimal and boxes. A real GPU
  may round the confidences differently, which is what `&text=1` is for.

### Installer


- `install_web` writes both workers and `ort-wasm-simd.jsep.wasm` from
  `onnxruntime-web` 1.18.0, hash pinned like the rest. The folder is 51 MB
  rather than 33. A browser fetches one runtime or the other, never both:
  41 MB on WebGPU, 33 MB as before in WebAssembly.
- It prints the Content-Security-Policy for both workers.
- It asks for `Cache-Control: no-cache` on the folder. After a deploy,
  phones kept running the previous worker: Firebase Hosting's default
  `max-age=3600`, together with Flutter's service worker, kept the old
  script through a reload and through unregistering the service worker.
  A new page with an old worker is a pair nobody tested. `no-cache` still
  lets the browser keep the files; it revalidates and gets a 304.

### README


- The two engines and how one is chosen; the iOS 27 slow state, what it
  looks like and that WebGPU avoids it; frame times for both engines; the
  policy for both workers; `no-cache` and why.

### Not verified


Everything above was run in desktop Chromium, headless, on a machine with
no GPU. The iPhone numbers are the reporting app's, which runs the same
models on the same runtime, not this package's.

- This package on a real iPhone, on either engine. `doc/device-checklist.md`
  has the steps.
- WebGPU on iOS 26 and on Android Chrome.
- Memory on the WebGPU engine in iOS WebKit. Its runtime is 8 MB bigger,
  and the reporting app once lost a tab right after a WebGPU scan, in a
  tab that had already loaded three engines.
- What causes the slow state.

### Housekeeping


- Flutter 3.50 deprecates `package:flutter/material.dart` in favour of
  `package:material_ui`, which is a second implementation rather than a
  new name: its `Theme` is another class. A scanner built on it would not
  see the theme of an app still built on the old one, so the package stays
  where the apps are for now and says so at each import.

## 0.3.1

No code changed. The package had stopped describing itself correctly.

- The platform badge still read "iOS | Android", and the opening sentence
  still named only Vision and ML Kit, a release after the browser scanner
  shipped. pub.dev itself had the web platform right, which is what made
  the badge worth believing and therefore worth fixing.
- The package description, which is what a search result shows, now says
  the web is supported rather than leaving a reader to find out from the
  platform list further down.

## 0.3.0

### Breaking


- `CardScannerPlatform` gained `buildPreview`. Anything implementing that
  interface, which is only needed to fake the platform in tests, has to
  provide it.

### Found by running it


The browser scanner had never been opened with a camera, only fed frames
through a test page. Driving the example in a browser with a fake camera
turned up two things a unit test could not.

- The preview was invisible. `CardScannerView` scaled it with a
  `FittedBox`, which works for a texture and does nothing for a DOM
  element: Flutter left the platform view host as a 17 pixel strip at the
  foot of the page. Filling is the platform's own business now. The view
  hands over the whole area and each platform covers it in its own way, a
  `FittedBox` on iOS and Android, `object-fit: cover` in a browser. The
  region of interest already worked out that geometry, so it is unchanged.
- The bank's name was being read as the cardholder's. Where the holder
  name is not recognized, which happens to a small or faint one, the only
  name-shaped line left is the issuer at the top of the card, and it was
  returned. A name more than two number heights above the number is
  refused outright now rather than merely scored down: a scan with no name
  asks the person to type one, a scan with the bank's name asks them to
  notice. A name printed just above the number still counts.
- `example/web/fake_camera.js` replaces the camera with a drawing of a
  card when the example is opened with `?fakeCamera=1`. It is how both of
  these were found and is the quickest way to exercise the scanner without
  a device.

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

### Preview

- The preview widget comes from the platform rather than from the view, so
  a platform without a texture can supply its own. The view hands over the
  whole area and each platform fills it the way `BoxFit.cover` would.
- `CardScannerController.buildPreview` exposes it for an app drawing its
  own camera UI around the controller.

### Web, memory on iPhone


Field feedback from a production web app: on an iPhone, in a page that
already holds a lot of memory, iOS killed the Safari tab while the engine
loaded. Measured in the iOS Simulator.

- `onnxruntime-web` is pinned to 1.18.0 and imported through `wasm-core`.
  1.19 and later ship only a threaded build, whose loader asks for a 4 GB
  shared `WebAssembly.Memory` even at one thread; iOS Safari refuses it
  once the page holds other WebAssembly, and the engine failed to load at
  all with "no available backend found". `install_web` installs the single
  `ort-wasm-simd.wasm` and no module glue, and the worker bundle is 173 KB
  rather than 190.
- OpenCV's WebAssembly is installed as its own `opencv.wasm` instead of a
  10 MB base64 `data:` URI inside a 10 MB script. Parsing and decoding
  that string cost tens of megabytes of heap; the engine folder is also
  33 MB rather than 38. `install_web` refuses to install an OpenCV whose
  script no longer carries one inlined binary, rather than writing
  something that will not load.
- README: the memory budget, why CanvasKit makes it tight, and why the
  runtime is pinned.

### Web, memory per frame


- The browser engine owns its PaddleOCR pipeline instead of borrowing
  `@gutenye/ocr-common`. The borrowed one turned every frame into
  JavaScript arrays a pixel at a time and then spread them into one array
  of 1.75 million numbers, about 100 MB of garbage a frame. Both
  conversions now write into a typed array of the final size, and the
  detection mask is built as one byte per pixel rather than four plus a
  colour conversion.
- Every OpenCV matrix is released. The borrowed pipeline leaked four per
  line of text, so a long scan grew an OpenCV heap that only a terminated
  worker gave back.
- Verified rather than assumed: `example/web/ocr_compare.html` runs the old
  and the new worker over six synthetic cards at two sizes and reports
  every line where they differ. All twelve match, text, confidences and
  boxes. `example/web/ocr_soak.html` reads one card twenty-four times and
  shows no drift, which is what the released matrices buy.
- The worker bundle is 157 KB, down from 190, and `@gutenye/ocr-common` is
  no longer a dependency. `js-clipper` is, directly.

### Prompts


- The scanner no longer sends people to the back of a card as soon as it
  has a name. A name regularly confirms a second or two before a number
  printed beside it, so a card whose number was on the front was being
  turned over for nothing. The prompt waits for a name to be held without
  a number for `CardFrameOverlay.numberOverdueAfter`, four seconds by
  default, and `CardScannerStrings.hintFor` takes a `numberOverdue` flag so
  it stays a pure function.
- The wording hedges to match: "Name recognized. If the number is on the
  back, turn the card over".
- Every change of prompt is also announced to a screen reader, not only
  tapped out as a haptic.

### Focus


- iOS zooms in just enough that a card filling the guide sits beyond the
  lens's closest focus. The main camera of a recent iPhone cannot focus
  nearer than about 20 cm, while a card fills the guide at about 12 cm, so
  on some phones it never sharpened at all. The zoom is computed from
  `minimumFocusDistance`, the format's field of view and the width of the
  guide, recomputed when either changes, capped by the format, and put back
  when the session stops.
- Cropping the sensor does not move the guide, so the region of interest
  still lines up: the delivered frame covers exactly what is captured.
- Android is untouched for now. The same thing may show on a flagship, and
  CameraX would want its zoom ratio set from
  `LENS_INFO_MINIMUM_FOCUS_DISTANCE`; nobody has reported it yet.

## 0.2.1

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
