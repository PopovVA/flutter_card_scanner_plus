// js-clipper ships no types. Only the polygon offsetting is used, which
// is what grows a detected blob back out to the edges of its letters.
declare module 'js-clipper' {
  export type ClipperPoint = { X: number; Y: number };

  export const JoinType: { jtRound: number };
  export const EndType: { etClosedPolygon: number };

  export class ClipperOffset {
    AddPath(path: ClipperPoint[], joinType: number, endType: number): void;
    Execute(solution: ClipperPoint[][], delta: number): void;
  }
}
