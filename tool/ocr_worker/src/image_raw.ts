// The image type the OCR engine works with, backed by OffscreenCanvas.
//
// The engine's own browser backend draws through `document`, which a worker
// does not have. This is the same contract on an OffscreenCanvas, with the
// debug hooks left empty: they write files, which a worker has no business
// doing and a scanner never asks for.

export type ImageRawData = {
  data: Uint8Array | Uint8ClampedArray;
  width: number;
  height: number;
};

export type SizeOption = {
  width?: number;
  height?: number;
  fit?: 'contain' | 'cover' | 'fill' | 'inside' | 'outside';
};

export class ImageRaw {
  data: ImageRawData['data'];
  width: number;
  height: number;

  constructor({ data, width, height }: ImageRawData) {
    this.data = data;
    this.width = width;
    this.height = height;
  }

  /// Only reached when the engine is handed a path, which this worker never
  /// does: it is always given pixels.
  static async open(_path: string): Promise<ImageRaw> {
    throw new Error('The scanner passes pixels, not paths');
  }

  getImageRawData(): ImageRawData {
    return { data: this.data, width: this.width, height: this.height };
  }

  /// Scales to [size]. A missing side keeps the aspect ratio, which is how
  /// the recognition model asks for a fixed height.
  async resize(size: SizeOption): Promise<ImageRaw> {
    const width = Math.max(
      1,
      Math.round(
        size.width ??
          (size.height ? (this.width * size.height) / this.height : this.width),
      ),
    );
    const height = Math.max(
      1,
      Math.round(
        size.height ??
          (size.width ? (this.height * size.width) / this.width : this.height),
      ),
    );
    if (width === this.width && height === this.height) return this;

    const source = new OffscreenCanvas(this.width, this.height);
    const sourceContext = source.getContext('2d');
    if (!sourceContext) throw new Error('No 2d context in this worker');
    // Copied rather than viewed: ImageData insists on a plain ArrayBuffer,
    // and what the engine hands over may be a view of something else.
    sourceContext.putImageData(
      new ImageData(new Uint8ClampedArray(this.data), this.width, this.height),
      0,
      0,
    );

    const target = new OffscreenCanvas(width, height);
    const targetContext = target.getContext('2d');
    if (!targetContext) throw new Error('No 2d context in this worker');
    targetContext.drawImage(source, 0, 0, width, height);

    const resized = targetContext.getImageData(0, 0, width, height);
    return new ImageRaw({ data: resized.data, width, height });
  }

  /// Debug hooks the engine calls when asked to dump its work. A worker has
  /// nowhere to write and a scanner must not leave card images anywhere, so
  /// both do nothing.
  async write(_path: string): Promise<void> {}

  async drawBox(_boxes: number[][][], _path?: string): Promise<void> {}
}
