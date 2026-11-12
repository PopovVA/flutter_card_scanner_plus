// Which build this is. The same sources are bundled twice, and build.mjs
// replaces this with a literal in each, so the half that belongs to the
// other build is dropped rather than shipped.
//
//   wasm    the models run in WebAssembly, on one thread
//   webgpu  the models run on the GPU; everything around them stays in
//           WebAssembly
declare const __BACKEND__: 'wasm' | 'webgpu';
