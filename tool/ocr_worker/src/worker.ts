// Reads cards in a Web Worker.
//
// The page sends one cropped frame at a time and gets back the lines found
// in it, with boxes normalized to that crop so the Dart parser needs to
// know nothing about the camera.
//
// Everything the engine loads at run time, OpenCV, the ONNX runtime's
// WebAssembly and the two models, is fetched from the folder this script
// was loaded from. Nothing is fetched from a third party.
import Ocr, { registerBackend } from '@gutenye/ocr-common';
// Its own entry point, because the engine exports it for exactly this:
// a backend that supplies everything else still wants the line splitter
// the engine ships.
import { splitIntoLineImages } from '@gutenye/ocr-common/splitIntoLineImages';
// wasm-core of 1.18, which is the last release with a single-threaded
// build. From 1.19 the loader asks for a 4 GB shared WebAssembly.Memory
// even at numThreads = 1, and iOS Safari refuses it once the page holds
// other WebAssembly: "no available backend found. ERR: [wasm] RangeError:
// Out of memory". See README, "Why ONNX Runtime is pinned".
import { InferenceSession, env } from 'onnxruntime-web/wasm-core';

import { ImageRaw } from './image_raw.js';

declare const self: DedicatedWorkerGlobalScope & {
  cv?: { onRuntimeInitialized?: () => void };
};

type Request = { id: number; bitmap: ImageBitmap };

type Line = { text: string; mean: number; box?: number[][] };

const base = new URL('./', self.location.href).href;

let engine: Promise<Ocr> | null = null;

/// Loads OpenCV and waits for its WebAssembly to finish starting.
///
/// The bindings call back through `onRuntimeInitialized` rather than a
/// promise, and anything that touches `cv` before then throws.
function loadOpenCv(): Promise<void> {
  return new Promise((resolve, reject) => {
    try {
      self.importScripts(`${base}opencv.js`);
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
      return;
    }
    const cv = self.cv;
    if (!cv) {
      reject(new Error('opencv.js did not install itself'));
      return;
    }
    // Already started: the bindings replace the hook with a no-op once
    // they are through it.
    if (!('onRuntimeInitialized' in cv) || cv.onRuntimeInitialized === undefined) {
      resolve();
      return;
    }
    cv.onRuntimeInitialized = () => resolve();
  });
}

async function load(): Promise<Ocr> {
  await loadOpenCv();

  // The runtime's own files sit next to this script.
  env.wasm.wasmPaths = base;
  // One thread: more would need the page to be cross-origin isolated,
  // which is not something a package can ask of every host app.
  env.wasm.numThreads = 1;

  registerBackend({
    FileUtils: {
      read: async (path: string) => {
        const response = await fetch(path);
        if (!response.ok) {
          throw new Error(`Could not read ${path}`);
        }
        return response.text();
      },
    },
    ImageRaw,
    InferenceSession,
    splitIntoLineImages,
    defaultModels: undefined,
  } as never);

  return Ocr.create({
    models: {
      detectionPath: `${base}ch_PP-OCRv4_det_infer.onnx`,
      recognitionPath: `${base}ch_PP-OCRv4_rec_infer.onnx`,
      dictionaryPath: `${base}ppocr_keys_v1.txt`,
    },
    onnxOptions: { executionProviders: ['wasm'] },
  });
}

/// The pixels of [bitmap], which is closed either way.
function pixelsOf(bitmap: ImageBitmap): ImageRaw {
  try {
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    if (!context) throw new Error('No 2d context in this worker');
    context.drawImage(bitmap, 0, 0);
    const image = context.getImageData(0, 0, bitmap.width, bitmap.height);
    return new ImageRaw({
      data: image.data,
      width: bitmap.width,
      height: bitmap.height,
    });
  } finally {
    bitmap.close();
  }
}

/// The engine reports a quadrilateral in the pixels of the image it
/// resized internally. The scanner wants an upright box as a fraction of
/// the crop it sent, which is what every box in the Dart core is.
function normalize(
  box: number[][] | undefined,
  width: number,
  height: number,
): { left: number; top: number; width: number; height: number } | null {
  if (!box || box.length === 0 || width <= 0 || height <= 0) return null;
  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  for (const point of box) {
    const [x, y] = point;
    if (typeof x !== 'number' || typeof y !== 'number') continue;
    left = Math.min(left, x);
    top = Math.min(top, y);
    right = Math.max(right, x);
    bottom = Math.max(bottom, y);
  }
  if (!Number.isFinite(left) || !Number.isFinite(top)) return null;
  const clamp = (value: number) => Math.min(1, Math.max(0, value));
  const l = clamp(left / width);
  const t = clamp(top / height);
  return {
    left: l,
    top: t,
    width: clamp(right / width) - l,
    height: clamp(bottom / height) - t,
  };
}

self.onmessage = async (event: MessageEvent<Request>) => {
  const { id, bitmap } = event.data ?? ({} as Request);
  if (typeof id !== 'number') return;

  try {
    engine ??= load();
    const ocr = await engine;
    const image = pixelsOf(bitmap);
    const result = await ocr.detect(image.getImageRawData());

    const lines = (result.texts as Line[])
      .map((line) => {
        const box = normalize(
          line.box,
          result.resizedImageWidth as number,
          result.resizedImageHeight as number,
        );
        return {
          text: line.text ?? '',
          confidence: typeof line.mean === 'number' ? line.mean : 1,
          box: box ?? { left: 0, top: 0, width: 0, height: 0 },
        };
      })
      .filter((line) => line.text.trim().length > 0);

    self.postMessage({ id, lines });
  } catch (error) {
    // A failed load leaves nothing usable behind, so the next frame tries
    // again rather than awaiting a promise that already rejected.
    engine = null;
    bitmap?.close?.();
    self.postMessage({ id, error: String(error) });
  }
};

// The page waits for this before it sends a frame, so a worker that could
// not even be fetched is a load failure rather than a silent stall.
self.postMessage({ ready: true });
