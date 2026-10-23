// Reads cards in a Web Worker.
//
// The page sends one cropped frame at a time and gets back the lines found
// in it, with boxes normalized to that crop so the Dart parser needs to
// know nothing about the camera.
//
// Everything the engine loads at run time, OpenCV, the ONNX runtime's
// WebAssembly and the two models, is fetched from the folder this script
// was loaded from. Nothing is fetched from a third party.
import { env } from 'onnxruntime-web/wasm-core';

import { type Quad } from './boxes.js';
import { Detection } from './detection.js';
import { pixelsOf } from './image.js';
import { Recognition } from './recognition.js';

declare const self: DedicatedWorkerGlobalScope & {
  cv?: { onRuntimeInitialized?: () => void };
};

type Request = { id: number; bitmap: ImageBitmap };

type Engine = { detection: Detection; recognition: Recognition };

const base = new URL('./', self.location.href).href;

let engine: Promise<Engine> | null = null;

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

async function load(): Promise<Engine> {
  await loadOpenCv();

  // The runtime's own files sit next to this script.
  env.wasm.wasmPaths = base;
  // One thread: more would need the page to be cross-origin isolated,
  // which is not something a package can ask of every host app.
  env.wasm.numThreads = 1;

  const [detection, recognition] = await Promise.all([
    Detection.load(`${base}ch_PP-OCRv4_det_infer.onnx`),
    Recognition.load(
      `${base}ch_PP-OCRv4_rec_infer.onnx`,
      `${base}ppocr_keys_v1.txt`,
    ),
  ]);
  return { detection, recognition };
}

/// The engine reports a quadrilateral in the pixels of the image it
/// resized internally. The scanner wants an upright box as a fraction of
/// the crop it sent, which is what every box in the Dart core is.
function normalize(
  box: Quad | undefined,
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
    const { detection, recognition } = await engine;

    const detected = await detection.run(pixelsOf(bitmap));
    const read = await recognition.run(detected.lines);

    const lines = read
      .map((line) => {
        const box = normalize(line.box, detected.width, detected.height);
        return {
          text: line.text,
          confidence: line.confidence,
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
