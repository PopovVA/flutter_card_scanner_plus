// Reading the text out of the lines detection found.
//
// PaddleOCR's CRNN head: each line is scaled to a fixed height, the model
// returns a character distribution per column, and the columns collapse
// into text. Rows that sit at the same height are then joined, which is
// why a cardholder name and an expiry date printed side by side arrive as
// one line.
import { InferenceSession, Tensor } from 'onnxruntime-web/wasm-core';

import { type LineImage, type Quad } from './boxes.js';
import { resize, toModelInput } from './image.js';

/// Height every line is scaled to. Taller is no more accurate.
const lineHeight = 48;

/// Below this the reading is not trusted at all.
const minimumConfidence = 0.5;

/// A line of text that was read.
export type ReadLine = {
  text: string;
  confidence: number;
  box?: Quad;
};

export class Recognition {
  private constructor(
    private readonly model: InferenceSession,
    private readonly dictionary: string[],
  ) {}

  static async load(
    modelPath: string,
    dictionaryPath: string,
  ): Promise<Recognition> {
    const [model, dictionary] = await Promise.all([
      InferenceSession.create(modelPath, { executionProviders: ['wasm'] }),
      fetch(dictionaryPath).then(async (response) => {
        if (!response.ok) throw new Error(`Could not read ${dictionaryPath}`);
        // The trailing space is the blank the model emits between words.
        return [...(await response.text()).split('\n'), ' '];
      }),
    ]);
    return new Recognition(model, dictionary);
  }

  /// Reads every line in [lines], drops what it is unsure of and joins
  /// what belongs on the same row.
  async run(lines: LineImage[]): Promise<ReadLine[]> {
    const read: ReadLine[] = [];
    for (const line of lines) {
      const scaled = resize(
        line.image,
        Math.max(1, Math.round((line.image.width * lineHeight) / line.image.height)),
        lineHeight,
      );
      const feeds: Record<string, Tensor> = {
        [this.model.inputNames[0]]: new Tensor(
          'float32',
          toModelInput(scaled),
          [1, 3, scaled.height, scaled.width],
        ),
      };
      const output = await this.model.run(feeds);
      const decoded = this.decode(output[this.model.outputNames[0]]);
      if (decoded.confidence < minimumConfidence) continue;
      read.push({ ...decoded, box: line.box });
    }
    return joinRows(read);
  }

  /// Collapses the model's per-column distribution into text.
  ///
  /// Greedy CTC: take the likeliest character in each column, drop the
  /// blank at index 0 and drop a character that repeats the one before
  /// it, which is how the model spells out a letter wider than a column.
  private decode(output: Tensor): { text: string; confidence: number } {
    const columns = output.dims[1] as number;
    const classes = output.dims[2] as number;
    const data = output.data as Float32Array;

    let text = '';
    let total = 0;
    let counted = 0;
    let previous = -1;

    for (let column = 0; column < columns; column++) {
      const at = column * classes;
      let best = 0;
      let bestValue = Number.NEGATIVE_INFINITY;
      for (let index = 0; index < classes; index++) {
        const value = data[at + index];
        if (value > bestValue) {
          bestValue = value;
          best = index;
        }
      }

      if (best !== 0 && best !== previous) {
        text += this.dictionary[best - 1] ?? '';
        total += bestValue;
        counted++;
      }
      previous = best;
    }

    return {
      text,
      confidence: counted === 0 ? 0 : total / counted,
    };
  }
}

/// Joins lines whose middles sit within half a line height of each other,
/// left to right, and orders the result down the card.
///
/// A card prints the name and the expiry date on one row, and reading them
/// as one line is what lets the parser tell which is which from where they
/// sit rather than from the order they arrived in.
function joinRows(lines: ReadLine[]): ReadLine[] {
  const boxed = lines.filter((line) => line.box !== undefined);
  if (boxed.length === 0) return lines;

  const averageHeight =
    boxed.reduce((total, line) => total + heightOf(line.box!), 0) /
    boxed.length;

  const rows: ReadLine[][] = [];
  for (const line of boxed) {
    const middle = middleOf(line.box!);
    const row = rows.find(
      (candidate) =>
        Math.abs(middleOf(candidate[0].box!) - middle) < averageHeight / 2,
    );
    if (row) {
      row.push(line);
    } else {
      rows.push([line]);
    }
  }

  for (const row of rows) {
    row.sort((a, b) => a.box![0][0] - b.box![0][0]);
  }
  rows.sort((a, b) => a[0].box![0][1] - b[0].box![0][1]);

  return rows.map((row) => {
    const first = row[0].box!;
    const last = row[row.length - 1].box!;
    return {
      text: row.map((line) => line.text).join(' '),
      confidence:
        row.reduce((total, line) => total + line.confidence, 0) / row.length,
      box: [first[0], last[1], last[2], first[3]] as Quad,
    };
  });
}

function heightOf(box: Quad): number {
  return box[2][1] - box[0][1];
}

function middleOf(box: Quad): number {
  return (box[0][1] + box[2][1]) / 2;
}
