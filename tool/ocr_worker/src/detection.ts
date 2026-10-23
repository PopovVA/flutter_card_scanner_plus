// Finding the lines of text in a picture of a card.
//
// PaddleOCR's DBNet: the model returns a probability per pixel, which is
// thresholded into a mask, and the mask's blobs become the lines. This
// used to come from @gutenye/ocr-common, which is correct and allocates
// a JavaScript array per pixel per channel while doing it.
import { InferenceSession, Tensor } from 'onnxruntime-web/wasm-core';

import { splitIntoLines, type LineImage } from './boxes.js';
import { resize, toMask, toModelInput, type Pixels } from './image.js';

/// The model's input has to be a multiple of this on both sides.
const baseSize = 32;

/// Above this the model is taken to have found text. PaddleOCR's own
/// default, and low on purpose: the mask is grown afterwards anyway.
const textThreshold = 0.03;

/// What one frame's detection found.
export type Detected = {
  lines: LineImage[];
  /// The size the picture was read at, which is what the boxes are in.
  width: number;
  height: number;
};

export class Detection {
  private constructor(private readonly model: InferenceSession) {}

  static async load(path: string): Promise<Detection> {
    return new Detection(
      await InferenceSession.create(path, { executionProviders: ['wasm'] }),
    );
  }

  /// Finds the lines of text in [image].
  async run(image: Pixels): Promise<Detected> {
    const input = resize(
      image,
      multipleOfBase(image.width),
      multipleOfBase(image.height),
    );

    const feeds: Record<string, Tensor> = {
      [this.model.inputNames[0]]: new Tensor(
        'float32',
        toModelInput(input),
        [1, 3, input.height, input.width],
      ),
    };
    const output = await this.model.run(feeds);
    const probabilities = output[this.model.outputNames[0]];

    const height = probabilities.dims[2] as number;
    const width = probabilities.dims[3] as number;
    const mask = toMask(
      probabilities.data as Float32Array,
      width * height,
      textThreshold,
    );

    return {
      lines: splitIntoLines(mask, width, height, input),
      width: input.width,
      height: input.height,
    };
  }
}

function multipleOfBase(side: number): number {
  return Math.max(Math.ceil(side / baseSize) * baseSize, baseSize);
}
