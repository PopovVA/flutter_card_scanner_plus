// How fast WebAssembly runs in this worker, as one number.
//
// Some iOS 27 Safari processes run WebAssembly about fifteen times slower
// than normal, as if without their optimizing compilers. Nothing fails:
// the engine loads, and then a frame takes ten or twenty seconds instead
// of under one, so a scan never finishes and never gives up either. The
// models cannot tell you that without running, which takes those twenty
// seconds. This loop tells you in a few milliseconds.

/// A module exporting `bench(n)`, which runs `acc = acc * 31 + i` over
/// i32 for i from 0 to n and returns acc.
///
///   (func (export "bench") (param $n i32) (result i32)
///     (local $i i32) (local $acc i32)
///     (loop
///       (local.set $acc
///         (i32.add (i32.mul (local.get $acc) (i32.const 31)) (local.get $i)))
///       (br_if 0
///         (i32.lt_u
///           (local.tee $i (i32.add (local.get $i) (i32.const 1)))
///           (local.get $n))))
///     (local.get $acc))
///
/// Written out by hand so the bundle carries 66 bytes rather than a
/// toolchain. The thresholds the scanner uses were measured with exactly
/// this module, so changing the loop means measuring again.
const module = new Uint8Array([
  // Magic and version.
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
  // Types: one function, i32 to i32.
  0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
  // Functions: one, of that type.
  0x03, 0x02, 0x01, 0x00,
  // Exports: "bench", function 0.
  0x07, 0x09, 0x01, 0x05, 0x62, 0x65, 0x6e, 0x63, 0x68, 0x00, 0x00,
  // Code: one body of 31 bytes with two i32 locals.
  0x0a, 0x21, 0x01, 0x1f, 0x01, 0x02, 0x7f,
  // loop
  0x03, 0x40,
  //   acc = acc * 31 + i
  0x20, 0x02, 0x41, 0x1f, 0x6c, 0x20, 0x01, 0x6a, 0x21, 0x02,
  //   i = i + 1
  0x20, 0x01, 0x41, 0x01, 0x6a, 0x22, 0x01,
  //   again while i < n
  0x20, 0x00, 0x49, 0x0d, 0x00,
  // end, return acc
  0x0b, 0x20, 0x02, 0x0b,
]);

/// Iterations in one run. Five million takes 4 to 15 ms on an iPhone in
/// its normal state and 55 to 87 ms in the slow one.
const steps = 5_000_000;

/// Runs timed. One is not enough: in desktop Chromium under load a single
/// run has taken 33 ms, and the first run of any module is the one the
/// engine has not compiled properly yet.
const runs = 3;

/// The fastest of [runs] runs, in milliseconds.
///
/// The fastest rather than the mean, because everything that can go wrong
/// with a timing makes it longer.
export function benchmark(): number {
  const instance = new WebAssembly.Instance(new WebAssembly.Module(module));
  const bench = instance.exports.bench as (n: number) => number;
  let fastest = Infinity;
  for (let run = 0; run < runs; run++) {
    const started = performance.now();
    bench(steps);
    fastest = Math.min(fastest, performance.now() - started);
  }
  return fastest;
}
