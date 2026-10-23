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

In: the engine's own JavaScript, about 190 KB. `@gutenye/ocr-common` (the
PaddleOCR pipeline), the wasm half of `onnxruntime-web`, and the small
helpers they pull in.

Out, because they come to about 38 MB: OpenCV, the ONNX runtime's
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

## Why a classic worker

Recognition takes about a second a frame, and a second of a blocked main
thread is a frozen app. It is a classic worker rather than a module because
the engine loads OpenCV with `importScripts`, which a module worker has no
equivalent for.
