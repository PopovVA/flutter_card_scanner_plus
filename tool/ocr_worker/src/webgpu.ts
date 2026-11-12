// What the WebGPU build checks before the runtime starts.
//
// Only the two model graphs run on the GPU. OpenCV, the pixel work on
// either side of a model and the rest of the runtime stay in WebAssembly.

type GpuAdapter = {
  info?: { isFallbackAdapter?: boolean };
  isFallbackAdapter?: boolean;
  requestAdapterInfo?: () => Promise<unknown>;
};

declare const self: WorkerGlobalScope & {
  navigator: { gpu?: { requestAdapter(): Promise<GpuAdapter | null> } };
  GPUAdapter?: { prototype: GpuAdapter };
};

/// Refuses to go on without a real GPU, and gives the runtime back a
/// method browsers took away.
///
/// Every refusal here is what lets the page fall back to the WebAssembly
/// build at once, instead of waiting on a runtime that will never start
/// or, worse, on one that starts and is useless.
///
/// A browser can have WebGPU on the page and not in a worker, and it can
/// have WebGPU with nothing behind it but a software rasterizer. The
/// second one loads and reads cards correctly at forty seconds a frame,
/// measured in headless Chromium on SwiftShader, where the WebAssembly
/// build takes one. `?softwareGpu=1` on the worker's URL lets it through
/// anyway, which is how the build is tested on a machine with no GPU.
///
/// ONNX Runtime 1.18 calls `GPUAdapter.requestAdapterInfo()`, which
/// browsers have since removed in favour of an `info` attribute, so its
/// WebGPU provider fails to start in a current browser. The method is put
/// back, answering with that attribute. 1.18 cannot simply be upgraded:
/// see "Why ONNX Runtime is pinned" in the README.
export async function prepareWebGpu(): Promise<void> {
  const gpu = self.navigator?.gpu;
  if (!gpu) {
    throw new Error('WebGPU is not available in this worker');
  }

  const prototype = self.GPUAdapter?.prototype;
  if (prototype && typeof prototype.requestAdapterInfo !== 'function') {
    prototype.requestAdapterInfo = function (this: GpuAdapter) {
      return Promise.resolve(this.info ?? {});
    };
  }

  const adapter = await gpu.requestAdapter();
  if (!adapter) {
    throw new Error('WebGPU has no adapter in this browser');
  }
  // The attribute moved from the adapter to its info between drafts of
  // the specification, and browsers of both kinds are in use.
  const software =
    adapter.info?.isFallbackAdapter === true ||
    adapter.isFallbackAdapter === true;
  const allowed =
    new URL(self.location.href).searchParams.get('softwareGpu') === '1';
  if (software && !allowed) {
    throw new Error('WebGPU is emulated in software in this browser');
  }
}
