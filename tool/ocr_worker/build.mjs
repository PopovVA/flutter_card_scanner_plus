// Bundles the OCR worker into assets/, twice from the same sources.
//
//   card_ocr_worker.js         the models run in WebAssembly
//   card_ocr_worker_webgpu.js  the models run on the GPU
//
// Each bundle holds the engine's JavaScript and nothing else. OpenCV, the
// ONNX runtime's WebAssembly and the models stay out of it: they come to
// tens of megabytes and are fetched at run time from the folder the worker
// was loaded from, which `dart run flutter_card_scanner_plus:install_web`
// fills in.
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const assets = resolve(here, '../../assets');

// The two builds differ in which half of onnxruntime-web they import and
// in the name of the execution provider the sessions ask for. Everything
// else, the pipeline and the protocol, is one source.
const bundles = [
  { file: 'card_ocr_worker.js', backend: 'wasm' },
  {
    file: 'card_ocr_worker_webgpu.js',
    backend: 'webgpu',
    // The sources import `wasm-core`, which has no GPU backend in it.
    // This entry point is the same runtime with the WebGPU one added.
    runtime: 'onnxruntime-web/webgpu',
  },
];

for (const { file, backend, runtime } of bundles) {
  const result = await build({
    entryPoints: [resolve(here, 'src/worker.ts')],
    outfile: resolve(assets, file),
    bundle: true,
    minify: true,
    // A classic worker, not a module: the engine loads OpenCV with
    // importScripts, which a module worker does not have.
    format: 'iife',
    target: ['es2020'],
    platform: 'browser',
    legalComments: 'none',
    metafile: true,
    alias: {
      // OpenCV is not bundled. Everything that imports it gets a stand-in
      // that reads the global the script installs.
      '@techstark/opencv-js': resolve(here, 'src/opencv_global.ts'),
      ...(runtime ? { 'onnxruntime-web/wasm-core': runtime } : {}),
    },
    define: {
      'process.env.NODE_ENV': '"production"',
      __BACKEND__: JSON.stringify(backend),
    },
  });

  const bytes = Object.values(result.metafile.outputs)[0].bytes;
  console.log(`${file}: ${(bytes / 1024).toFixed(0)} KB`);
}
