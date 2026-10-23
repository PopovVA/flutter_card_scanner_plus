// Turning the detection mask into upright pictures of lines of text.
//
// This is PaddleOCR's DBNet post-processing: find the blobs the model is
// confident about, grow each one a little, and lift it out of the picture
// straightened. The geometry is OpenCV's; what is ours is that every
// matrix it hands back is released. The engine this replaces leaked four
// of them per line of text, and an OpenCV heap that only grows is a scan
// that gets slower the longer it runs.
import cv from '@techstark/opencv-js';
import clipper from 'js-clipper';

import { type Pixels } from './image.js';

/// A quadrilateral, clockwise from the top left.
export type Quad = [number, number][];

/// One line of text, straightened, with where it came from.
export type LineImage = {
  image: Pixels;
  box: Quad;
};

/// Smallest side a blob must have to be worth reading, in mask pixels.
const minimumSide = 3;

/// How far a blob is grown before it is cut out. The model marks the
/// strokes; the letters need their edges back.
const unclipRatio = 1.5;

/// Reads the lines [mask] marks out of [source].
///
/// [mask] is one byte per pixel at [maskWidth] by [maskHeight], which is
/// what the detection model produced; [source] is the picture it was run
/// on, and the lines are cut from that.
export function splitIntoLines(
  mask: Uint8Array,
  maskWidth: number,
  maskHeight: number,
  source: Pixels,
): LineImage[] {
  const lines: LineImage[] = [];

  // Grey from the start, so there is no colour copy and no conversion.
  const marked = cv.matFromArray(maskHeight, maskWidth, cv.CV_8UC1, mask);
  const contours = new cv.MatVector();
  const hierarchy = new cv.Mat();
  // The source is read once for the whole frame. The engine this replaces
  // read it again for every line.
  const picture = cv.matFromImageData(source);

  try {
    cv.findContours(
      marked,
      contours,
      hierarchy,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );

    const scaleX = source.width / maskWidth;
    const scaleY = source.height / maskHeight;

    for (let index = 0; index < contours.size(); index++) {
      const contour = contours.get(index);
      try {
        const tight = miniBox(contour);
        if (tight.side < minimumSide) continue;

        const grown = unclip(tight.points);
        if (grown.length < 8) continue;

        const grownBox = cv.matFromArray(grown.length / 2, 1, cv.CV_32SC2, grown);
        let box: Quad;
        try {
          const bounds = miniBox(grownBox);
          if (bounds.side < minimumSide + 2) continue;
          box = bounds.points;
        } finally {
          grownBox.delete();
        }

        // Scaled onto the picture, then snapped to whole pixels inside it.
        // PaddleOCR's reference rounds and clips before it crops, and a
        // crop taken on the raw fractions reads a hair differently.
        for (const point of box) {
          point[0] = clamp(Math.round(point[0] * scaleX), 0, source.width);
          point[1] = clamp(Math.round(point[1] * scaleY), 0, source.height);
        }

        // Measured across the box rather than along its own corner order,
        // which is what tells a sliver apart from a line of text.
        const ordered = clockwise(box);
        if (
          truncate(distance(ordered[0], ordered[1])) <= 3 ||
          truncate(distance(ordered[0], ordered[3])) <= 3
        ) {
          continue;
        }

        lines.push({ image: straighten(picture, box), box });
      } finally {
        contour.delete();
      }
    }
  } finally {
    marked.delete();
    contours.delete();
    hierarchy.delete();
    picture.delete();
  }

  return lines;
}

/// The tightest rotated rectangle around [contour], as four points sorted
/// into top-left, top-right, bottom-right, bottom-left, with its shorter
/// side.
function miniBox(contour: cv.Mat): { points: Quad; side: number } {
  const rect = cv.minAreaRect(contour);
  const points = cornersOf(rect).sort((a, b) => a[0] - b[0]);

  // Of the two leftmost points the higher one is the top left, and of the
  // two rightmost the higher one is the top right.
  const [first, fourth] = points[1][1] > points[0][1] ? [0, 1] : [1, 0];
  const [second, third] = points[3][1] > points[2][1] ? [2, 3] : [3, 2];

  return {
    points: [points[first], points[second], points[third], points[fourth]],
    side: Math.min(rect.size.width, rect.size.height),
  };
}

/// The four corners of a rotated rectangle.
function cornersOf(rect: {
  center: { x: number; y: number };
  size: { width: number; height: number };
  angle: number;
}): Quad {
  const theta = (rect.angle * Math.PI) / 180;
  const cos = Math.cos(theta);
  const sin = Math.sin(theta);
  const dx = rect.size.width / 2;
  const dy = rect.size.height / 2;
  const { x, y } = rect.center;
  return [
    [x - dx * cos + dy * sin, y - dx * sin - dy * cos],
    [x + dx * cos + dy * sin, y + dx * sin - dy * cos],
    [x + dx * cos - dy * sin, y + dx * sin + dy * cos],
    [x - dx * cos - dy * sin, y - dx * sin + dy * cos],
  ];
}

/// Grows [box] outwards by an area over perimeter step, flattened to the
/// pairs OpenCV takes.
///
/// The model marks where the strokes are, which is inside the letters. A
/// crop on those edges clips the letters it is meant to read.
function unclip(box: Quad): number[] {
  const step = (Math.abs(area(box)) * unclipRatio) / perimeter(box);
  const offset = new clipper.ClipperOffset();
  offset.AddPath(
    box.map(([x, y]) => ({ X: x, Y: y })),
    clipper.JoinType.jtRound,
    clipper.EndType.etClosedPolygon,
  );
  const grown: { X: number; Y: number }[][] = [];
  offset.Execute(grown, step);
  const first = grown[0] ?? [];
  const flat: number[] = [];
  for (const point of first) {
    flat.push(point.X, point.Y);
  }
  return flat;
}

/// [points] in clockwise order from the top left.
function clockwise(points: Quad): Quad {
  const sums = points.map(([x, y]) => x + y);
  const topLeft = points[sums.indexOf(Math.min(...sums))];
  const bottomRight = points[sums.indexOf(Math.max(...sums))];
  const rest = points.filter(
    (point) => point !== topLeft && point !== bottomRight,
  );
  const spread = [rest[1][0] - rest[0][0], rest[1][1] - rest[0][1]];
  const topRight = rest[spread.indexOf(Math.min(...spread))];
  const bottomLeft = rest[spread.indexOf(Math.max(...spread))];
  return [topLeft, topRight, bottomRight, bottomLeft];
}

/// Lifts the quadrilateral [box] out of [picture], straightened.
///
/// A card is rarely held square to the camera, so the line of text is a
/// trapezium; the recognizer wants a rectangle. A line taller than it is
/// wide is turned upright, which is how vertical text ends up readable.
function straighten(picture: cv.Mat, box: Quad): Pixels {
  const width = truncate(
    Math.max(distance(box[0], box[1]), distance(box[2], box[3])),
  );
  const height = truncate(
    Math.max(distance(box[0], box[3]), distance(box[1], box[2])),
  );

  const from = cv.matFromArray(4, 1, cv.CV_32FC2, box.flat());
  const to = cv.matFromArray(4, 1, cv.CV_32FC2, [
    0, 0, width, 0, width, height, 0, height,
  ]);
  const transform = cv.getPerspectiveTransform(from, to);
  const straightened = new cv.Mat();
  let turned: cv.Mat | null = null;

  try {
    cv.warpPerspective(
      picture,
      straightened,
      transform,
      new cv.Size(width, height),
      cv.INTER_CUBIC,
      cv.BORDER_REPLICATE,
      new cv.Scalar(),
    );

    let result = straightened;
    if (straightened.rows / straightened.cols >= 1.5) {
      turned = new cv.Mat();
      const rotation = cv.getRotationMatrix2D(
        new cv.Point(straightened.cols / 2, straightened.cols / 2),
        90,
        1,
      );
      try {
        cv.warpAffine(
          straightened,
          turned,
          rotation,
          new cv.Size(straightened.rows, straightened.cols),
          cv.INTER_CUBIC,
          cv.BORDER_REPLICATE,
          new cv.Scalar(),
        );
      } finally {
        rotation.delete();
      }
      result = turned;
    }

    // Copied out before the matrix goes: the data is a view into it.
    return {
      data: new Uint8ClampedArray(result.data),
      width: result.cols,
      height: result.rows,
    };
  } finally {
    from.delete();
    to.delete();
    transform.delete();
    straightened.delete();
    turned?.delete();
  }
}

function area(polygon: Quad): number {
  let total = 0;
  let previous = polygon[polygon.length - 1];
  for (const point of polygon) {
    total += previous[1] * point[0] - previous[0] * point[1];
    previous = point;
  }
  return total / 2;
}

function perimeter(polygon: Quad): number {
  let total = 0;
  let previous = polygon[polygon.length - 1];
  for (const point of polygon) {
    total += Math.hypot(previous[0] - point[0], previous[1] - point[1]);
    previous = point;
  }
  return total;
}

function distance(a: [number, number], b: [number, number]): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

function clamp(value: number, low: number, high: number): number {
  return Math.max(low, Math.min(value, high));
}

/// Towards zero, which is what PaddleOCR's reference does.
function truncate(value: number): number {
  return value > 0 ? Math.floor(value) : Math.ceil(value);
}
