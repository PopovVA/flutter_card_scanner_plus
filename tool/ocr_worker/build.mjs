// Bundles the OCR worker into assets/card_ocr_worker.js.
//
// The bundle holds the engine's JavaScript and nothing else. OpenCV, the
// ONNX runtime's WebAssembly and the models stay out of it: they come to
// about 40 MB and are fetched at run time from the folder the worker was
// loaded from, which `dart run flutter_card_scanner_plus:install_web`
// fills in.
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../../assets/card_ocr_worker.js');
const require = createRequire(import.meta.url);

const result = await build({
  entryPoints: [resolve(here, 'src/worker.ts')],
  outfile: out,
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
  },
  define: { 'process.env.NODE_ENV': '"production"' },
});

const bytes = Object.values(result.metafile.outputs)[0].bytes;
console.log(`card_ocr_worker.js: ${(bytes / 1024).toFixed(0)} KB`);
