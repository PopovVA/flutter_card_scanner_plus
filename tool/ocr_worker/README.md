# OCR worker

Builds `assets/card_ocr_worker.js`, the Web Worker that reads cards in a
browser. The bundle is committed, so an app never builds JavaScript; this
directory exists to rebuild it when the engine is upgraded.

```bash
cd tool/ocr_worker
npm ci
npx tsc --noEmit
npm run build
```

CI runs exactly that and fails if the committed bundle differs, so a change
here has to be committed together with the rebuilt bundle.

## What is in the bundle, and what is not

In: the PaddleOCR pipeline, which is `src/detection.ts` and
`src/recognition.ts` here, the wasm half of `onnxruntime-web`, and
`js-clipper` for growing a detected blob back out to the edges of its
letters. About 157 KB.

The pipeline used to come from `@gutenye/ocr-common`, which is correct and
builds a JavaScript array per pixel per channel while being so: about
100 MB of garbage a frame, which on an iPhone is the difference between
scanning and having the tab killed. It also never released the OpenCV
matrices it allocated, four per line of text. Owning the two models is
what let both be fixed; the arithmetic is the same, and
`ocr_compare.html` is there to prove it stays the same.

Out, because they come to about 33 MB: OpenCV, the ONNX runtime's
WebAssembly, and the two PP-OCRv4 models. Those are fetched at run time
from the folder the worker was loaded from, which
`dart run flutter_card_scanner_plus:install_web` fills in. `bin/install_web.dart`
pins their versions and hashes, so upgrading one means changing both files.

`onnxruntime-web` is pinned to 1.18.0 and imported through `wasm-core`.
1.19 and later ship only a threaded build, whose loader asks iOS Safari for
a 4 GB shared memory even at one thread and is refused; `wasm-core` also
leaves out the WebGL and WebGPU backends this worker never asks for, which
on their own more than doubled the bundle. The README's "Why ONNX Runtime
is pinned" has the error it produces.

OpenCV is reached through `src/opencv_global.ts`, a proxy onto the global
the script installs. Importing `@techstark/opencv-js` directly would bundle
about 10 MB of generated bindings.

## Trying it without a camera

`example/web/ocr_harness.html` draws a synthetic card on a canvas, sends it
to the worker and prints what comes back, with timings. It needs no camera
and no Flutter build, which makes it the quickest way to tell whether a
change to the engine still reads a card:

```bash
cd example
dart run flutter_card_scanner_plus:install_web
( cd web && python3 -m http.server 8731 )
# then open http://localhost:8731/ocr_harness.html
```

A good run looks like this:

```
worker ready in 27 ms
frame 0 in 945 ms, 3 lines
   "ZEBRA MONEY"          c=0.97
   "4111 1111 1111 1111"  c=0.98
   "ALICE GREEN 12/28"    c=0.99
frame 1 in 505 ms, 3 lines
```

The second frame is faster because the first one loads the models. That
output is pinned in `test/web/engine_output_test.dart`, which checks the
Dart side takes it apart correctly: note that the name and the expiry date
arrive as one line, the way a printed row actually reaches the parser.

Two more pages sit beside it.

`ocr_compare.html` runs two builds of the worker over six synthetic cards
at two sizes and prints every line where they disagree. Put the build you
are replacing next to the new one first:

```bash
git show <ref>:assets/card_ocr_worker.js \
  > example/web/flutter_card_scanner_plus/card_ocr_worker_old.js
```

Any change to the engine should come with a run of this. Expect `same: 12,
different: 0`; a difference in the third decimal of a confidence is worth
explaining, not waving through, because it means the pixels reaching the
model changed.

`ocr_soak.html` reads the same card 24 times and prints the mean of the
first eight warm frames against the last eight. They should match: a scan
that gets slower the longer it runs is OpenCV matrices never being
released. Pass `?worker=card_ocr_worker_old.js` to soak another build.

## Why a classic worker

Recognition takes about a second a frame, and a second of a blocked main
thread is a frozen app. It is a classic worker rather than a module because
the engine loads OpenCV with `importScripts`, which a module worker has no
equivalent for.
