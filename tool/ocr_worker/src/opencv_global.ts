// OpenCV, read from the global the script installs rather than bundled.
//
// @techstark/opencv-js ships about 10 MB of generated bindings. The worker
// loads opencv.js with importScripts instead and reaches it through this
// stand-in, so the bundle stays small and the heavy file is cached by the
// browser like any other asset.
//
// Reading is deferred because the import is evaluated before the script
// has run: everything goes through a proxy that looks the member up on
// `self.cv` at the moment it is used.
declare const self: { cv?: Record<string, unknown> } & WorkerGlobalScope;

function opencv(): Record<string, unknown> {
  const cv = self.cv;
  if (!cv) {
    throw new Error('opencv.js has not been loaded yet');
  }
  return cv;
}

const lazy = new Proxy(
  {},
  {
    get(_target, property) {
      const value = opencv()[property as string];
      return typeof value === 'function' ? value.bind(opencv()) : value;
    },
    has(_target, property) {
      return property in opencv();
    },
  },
);

export default lazy as never;
