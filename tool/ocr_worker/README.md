# OCR worker

Builds the two Web Workers that read cards in a browser, from one set of
sources:

| Bundle | Models run | Size |
|---|---|---|
| `assets/card_ocr_worker.js` | in WebAssembly, one thread | 158 KB |
| `assets/card_ocr_worker_webgpu.js` | on the GPU, through WebGPU | 807 KB |

Both are committed, so an app never builds JavaScript; this directory
exists to rebuild them when the engine is upgraded.

```bash
cd tool/ocr_worker
npm ci
npx tsc --noEmit
npm run build
```

CI runs exactly that and fails if a committed bundle differs, so a change
here has to be committed together with both rebuilt bundles.

## One source, two builds

`build.mjs` bundles `src/worker.ts` twice. The second time it points the
`onnxruntime-web/wasm-core` import at `onnxruntime-web/webgpu`, and it
defines `__BACKEND__` as `'wasm'` or `'webgpu'` in each. That constant is
the execution provider the two sessions ask for, and the only switch in
the sources: what belongs to the other build is dropped by the bundler
rather than shipped.

The WebGPU build differs from the other in two places, both in
`src/webgpu.ts`, both before anything is fetched:

- It refuses to load without `navigator.gpu` in the worker, without an
  adapter, or with only a software adapter. Each refusal is what lets the
  page fall back to the WebAssembly worker at once. A software adapter is
  the one that would otherwise go unnoticed: it loads, reads correctly,
  and takes forty seconds a frame.
- It puts `GPUAdapter.requestAdapterInfo()` back. ONNX Runtime 1.18 calls
  it, browsers have removed it for the `info` attribute, and without it
  the WebGPU provider does not start.

Only the model graphs run on the GPU. OpenCV and the pixel work stay in
WebAssembly in both builds.

## What the page and a worker say to each other

| The page sends | The worker answers |
|---|---|
| nothing, it just starts the worker | `{ ready: true, backend }` once the script has run |
| `{ benchmark: true }` | `{ benchmarkMs }`, the fastest of three runs of a fixed WebAssembly loop |
| `{ load: true }` | `{ loaded: true, backend }` or `{ loadError, backend }` |
| `{ id, bitmap }` | `{ id, lines }` or `{ id, error }` |

Loading is a message of its own so that an engine that will not load is
not mistaken for a frame that failed. The first means try the other
build; the second means try the next frame. A frame still loads the
engine if nothing has, so a page that only sends frames works.

The benchmark is `src/benchmark.ts`: 66 bytes of hand-written WebAssembly
running `acc = acc * 31 + i` five million times. It exists for iOS 27
Safari, where some processes run WebAssembly about fifteen times slower
than normal and a frame takes ten or twenty seconds. The loop takes 4 to
15 ms on an iPhone normally and 55 to 87 ms in that state; the scanner
gives up above 40. Those numbers were measured with this module, so
changing the loop means measuring again. The decision is made in Dart, in
`lib/src/web/ocr_engine.dart`; the worker only reports.

`backend` in the first message is also how the scanner tells a worker
from before 0.4.0, which says `{ ready: true }` and would never answer a
benchmark.

## What is in the bundles, and what is not

In: the PaddleOCR pipeline, which is `src/detection.ts` and
`src/recognition.ts` here, the JavaScript half of `onnxruntime-web`, and
`js-clipper` for growing a detected blob back out to the edges of its
letters. The WebGPU bundle is five times the size of the other because
that half carries the shader for every operator.

The pipeline used to come from `@gutenye/ocr-common`, which is correct and
builds a JavaScript array per pixel per channel while being so: about
100 MB of garbage a frame, which on an iPhone is the difference between
scanning and having the tab killed. It also never released the OpenCV
matrices it allocated, four per line of text. Owning the two models is
what let both be fixed; the arithmetic is the same, and
`ocr_compare.html` is there to prove it stays the same.

Out, because they come to about 51 MB: OpenCV, the two builds of the ONNX
runtime's WebAssembly, and the two PP-OCRv4 models. Those are fetched at run time
from the folder the worker was loaded from, which
`dart run flutter_card_scanner_plus:install_web` fills in. `bin/install_web.dart`
pins their versions and hashes, so upgrading one means changing both files.

`onnxruntime-web` is pinned to 1.18.0. The WebAssembly build imports it
through `wasm-core` and loads `ort-wasm-simd.wasm`; the WebGPU build
imports `webgpu` and loads `ort-wasm-simd.jsep.wasm`. Both runtimes are
single-threaded. 1.19 and later ship only a threaded build, whose loader
asks iOS Safari for a 4 GB shared memory even at one thread and is
refused; `wasm-core` also leaves out the WebGL and WebGPU backends the
WebAssembly worker never asks for, which is why that bundle is a fifth of
the other. The README's "Why ONNX Runtime is pinned" has the error it
produces.

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
worker: card_ocr_worker.js
worker ready in 27 ms, backend wasm
benchmark before the load: 7.1 ms
engine loaded in 1125 ms, backend wasm
benchmark after the load: 7.1 ms
frame 0 in 945 ms, 3 lines
   "ZEBRA MONEY"          c=0.97
   "4111 1111 1111 1111"  c=0.98
   "ALICE GREEN 12/28"    c=0.99
frame 1 in 505 ms, 3 lines
```

It takes the same steps the scanner does: time WebAssembly, load, time it
again, and only then send a frame. Add
`?worker=card_ocr_worker_webgpu.js` to run the WebGPU build. On a machine
with no GPU that build refuses to load, which is the answer the scanner
wants and not the one a test wants, so `&softwareGpu=1` lets it run on a
software adapter: the same lines, at most of a minute a frame. Headless
Chromium needs `--enable-unsafe-webgpu --enable-features=Vulkan
--use-webgpu-adapter=swiftshader --enable-unsafe-swiftshader` to have an
adapter at all.

The first frame is slower than the second because the models compile on
it. That output is pinned in `test/web/engine_output_test.dart`, which checks the
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

The same page sets one build against the other:

```
ocr_compare.html?old=card_ocr_worker.js&new=card_ocr_worker_webgpu.js&text=1
```

`&text=1` compares what was read and leaves the confidences out. A GPU
and a CPU round differently, so the third decimal is not expected to
agree between the two builds, and the text is.

`fake_camera.js` is not a harness but the thing that makes the whole
scanner testable without a camera: open the example with `?fakeCamera=1`
and `getUserMedia` returns a drawing of a card instead. `&w=`, `&h=` and
`&card=` set the stream size and how much of it the card fills, which is
what decides whether it lands inside the guide. A portrait stream on a
phone sized viewport, `?fakeCamera=1&w=720&h=1280&card=0.56`, frames it
about right. It found both of the bugs in the "Found by running it"
section of the changelog. Every open gets a stream of its own, so the
scanner can be opened and closed several times on one page, which is how
the choice of engine is seen to stick.

`ocr_soak.html` reads the same card 24 times and prints the mean of the
first eight warm frames against the last eight. They should match: a scan
that gets slower the longer it runs is OpenCV matrices never being
released. Pass `?worker=card_ocr_worker_old.js` to soak another build.

## Why a classic worker

Recognition takes up to a second a frame, and a second of a blocked main
thread is a frozen app. It is a classic worker rather than a module because
the engine loads OpenCV with `importScripts`, which a module worker has no
equivalent for.
