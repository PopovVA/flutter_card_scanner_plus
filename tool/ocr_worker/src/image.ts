// Pixels, and the two things the models want them turned into.
//
// Both conversions used to go through JavaScript arrays: one value pushed
// at a time into three of them, then spread into a fourth of 1.75 million
// numbers for a 960 by 608 frame. That is about 100 MB of garbage a frame,
// and on an iPhone it is the difference between scanning and having the
// tab killed. Everything here writes into a typed array of the final size.

/// An image as the models see it: RGBA bytes, width, height.
export type Pixels = {
  data: Uint8ClampedArray;
  width: number;
  height: number;
};

/// One canvas, reused: a scan resizes several images a second, and a fresh
/// OffscreenCanvas for each one is a fresh allocation for each one.
const scratch = {
  canvas: null as OffscreenCanvas | null,
  context: null as OffscreenCanvasRenderingContext2D | null,
};

function canvasOf(
  width: number,
  height: number,
): OffscreenCanvasRenderingContext2D {
  if (!scratch.canvas) {
    scratch.canvas = new OffscreenCanvas(width, height);
    scratch.context = scratch.canvas.getContext("2d");
  }
  if (scratch.canvas.width !== width || scratch.canvas.height !== height) {
    scratch.canvas.width = width;
    scratch.canvas.height = height;
  }
  const context = scratch.context;
  if (!context) throw new Error("No 2d context in this worker");
  return context;
}

/// Draws [image] at [width] by [height] and reads it back.
///
/// Through a canvas rather than through OpenCV so the filtering is the one
/// the models were being fed before: changing how pixels are interpolated
/// changes what the recognizer reads.
export function resize(image: Pixels, width: number, height: number): Pixels {
  if (width === image.width && height === image.height) return image;

  const source = new OffscreenCanvas(image.width, image.height);
  const sourceContext = source.getContext("2d");
  if (!sourceContext) throw new Error("No 2d context in this worker");
  sourceContext.putImageData(
    new ImageData(new Uint8ClampedArray(image.data), image.width, image.height),
    0,
    0,
  );

  // A canvas of its own, not the shared one: reusing a canvas changes the
  // pixels a downscale produces, by a hair, and the recognizer reads them.
  const target = new OffscreenCanvas(width, height);
  const context = target.getContext('2d');
  if (!context) throw new Error('No 2d context in this worker');
  context.drawImage(source, 0, 0, width, height);
  const resized = context.getImageData(0, 0, width, height);
  return { data: resized.data, width, height };
}

/// The pixels of [bitmap], which is closed either way.
export function pixelsOf(bitmap: ImageBitmap): Pixels {
  try {
    const context = canvasOf(bitmap.width, bitmap.height);
    context.clearRect(0, 0, bitmap.width, bitmap.height);
    context.drawImage(bitmap, 0, 0);
    const image = context.getImageData(0, 0, bitmap.width, bitmap.height);
    return { data: image.data, width: bitmap.width, height: bitmap.height };
  } finally {
    bitmap.close();
  }
}

/// [image] as the planar float input both models take: one value per
/// channel per pixel, divided by 255, in the order blue, green, red.
///
/// That order is not a mistake. PaddleOCR's exported models were trained
/// on OpenCV's BGR, and feeding them RGB costs accuracy on coloured cards.
export function toModelInput(image: Pixels): Float32Array {
  const pixels = image.width * image.height;
  const input = new Float32Array(pixels * 3);
  const data = image.data;
  const green = pixels;
  const red = pixels * 2;

  for (let pixel = 0, at = 0; pixel < pixels; pixel++, at += 4) {
    input[pixel] = data[at + 2] / 255;
    input[green + pixel] = data[at + 1] / 255;
    input[red + pixel] = data[at] / 255;
  }
  return input;
}

/// The detection model's probability map as a single channel mask: 255
/// where it is confident there is text, 0 elsewhere.
///
/// One byte per pixel rather than four. OpenCV wants grey for contours, so
/// building it grey saves both the colour copy and the conversion.
export function toMask(
  probabilities: Float32Array,
  pixels: number,
  threshold: number,
): Uint8Array {
  const mask = new Uint8Array(pixels);
  for (let at = 0; at < pixels; at++) {
    if (probabilities[at] > threshold) mask[at] = 255;
  }
  return mask;
}
