import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../channel/card_scanner_platform.dart';
import 'js_await.dart';
import 'web_camera_error.dart';

/// One open camera in a browser tab: the stream, the `<video>` element
/// drawing it, and the torch if the device has one.
///
/// Everything here is per session. A new scan opens a new camera and
/// registers a new view, because a view factory cannot be unregistered and
/// reusing one would show the previous session's element.
class WebCamera {
  WebCamera._(this._stream, this.video, this.viewType);

  /// Whether this browser can be asked for a camera at all.
  ///
  /// `getUserMedia` only exists in a secure context, so a page served over
  /// plain HTTP, or an embedded browser without the API, can never scan.
  static bool get isSupported {
    if (!web.window.isSecureContext) return false;
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('mediaDevices')) return false;
    final devices = navigator['mediaDevices'] as JSObject?;
    return devices != null && devices.has('getUserMedia');
  }

  /// Opens the back camera and returns once the first frame is on screen.
  ///
  /// [viewType] is the name this session's element is registered under.
  /// Throws [CardScannerException] with a code from [WebCameraError].
  static Future<WebCamera> open({required String viewType}) async {
    if (!isSupported) throw WebCameraError.unsupported;

    final constraints =
        {
              'audio': false,
              // A phone has more than one camera and the back one reads cards.
              // Asked for as ideal rather than exact, so a laptop with only a
              // front camera still opens.
              'video': {
                'facingMode': {'ideal': 'environment'},
                'width': {'ideal': 1920},
                'height': {'ideal': 1080},
              },
            }.jsify()!
            as web.MediaStreamConstraints;

    final opened = await settle(
      web.window.navigator.mediaDevices.getUserMedia(constraints),
    );
    final stream = opened.value;
    if (stream == null) {
      throw CardScannerException(
        WebCameraError.codeFor(opened.errorName ?? ''),
        'The browser refused the camera',
      );
    }

    final video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      // Both the property and the attribute: iOS Safari reads the
      // attribute, and without it the video takes over the whole screen
      // instead of playing in the page.
      ..playsInline = true
      ..srcObject = stream;
    video.setAttribute('playsinline', '');
    video.style
      ..width = '100%'
      ..height = '100%'
      // The scanner scales and clips the element itself, so it must not
      // letterbox or crop on its own.
      ..objectFit = 'fill'
      // Every touch belongs to Flutter, not to the video.
      ..pointerEvents = 'none';

    final camera = WebCamera._(stream, video, viewType);
    try {
      await camera._play();
    } on CardScannerException {
      camera.close();
      rethrow;
    }
    return camera;
  }

  final web.MediaStream _stream;

  /// The element drawing the camera, registered under [viewType].
  final web.HTMLVideoElement video;

  /// The platform view name this session's element is registered under.
  final String viewType;

  final _shapeChanges = StreamController<void>.broadcast();
  StreamSubscription<web.Event>? _resize;
  bool _closed = false;

  /// Emits when the browser changes the shape of the video, which is what a
  /// rotation looks like from here: a mobile browser swaps the width and
  /// the height of the same stream.
  Stream<void> get shapeChanges => _shapeChanges.stream;

  final _lost = StreamController<void>.broadcast();

  /// Emits when the camera is taken away, by another app or by the user
  /// revoking access mid-scan.
  Stream<void> get lost => _lost.stream;

  /// Frame width in pixels, zero until the browser reports one.
  int get width => video.videoWidth;

  /// Frame height in pixels, zero until the browser reports one.
  int get height => video.videoHeight;

  /// Whether this camera has been closed.
  bool get isClosed => _closed;

  Future<void> _play() async {
    if (video.readyState < 1) {
      final ready = Completer<void>();
      final done = video.onLoadedMetadata.listen((_) {
        if (!ready.isCompleted) ready.complete();
      });
      final failed = video.onError.listen((_) {
        if (!ready.isCompleted) ready.complete();
      });
      await ready.future;
      await done.cancel();
      await failed.cancel();
    }
    final played = await settle<JSAny?>(video.play());
    if (played.errorName != null) {
      throw CardScannerException(
        CardScannerException.cameraError,
        'The browser would not play the camera stream',
      );
    }

    _resize = video.onResize.listen((_) => _shapeChanges.add(null));
    final track = _videoTrack;
    if (track != null) {
      // The track ends when something else takes the camera, or when the
      // user revokes access while the scan is running.
      track.addEventListener(
        'ended',
        ((web.Event _) {
          if (!_closed) _lost.add(null);
        }).toJS,
      );
    }
  }

  web.MediaStreamTrack? get _videoTrack {
    final tracks = _stream.getVideoTracks().toDart;
    return tracks.isEmpty ? null : tracks.first;
  }

  /// Whether the camera reports a torch.
  ///
  /// Read from the track's capabilities, and a missing field counts as no
  /// torch. WebKit has reported this inconsistently (bugs 243075 and
  /// 270779), so a scanner should hide the control rather than offer one
  /// that does nothing.
  bool get hasTorch {
    final track = _videoTrack;
    if (track == null) return false;
    final capabilities = track.getCapabilities() as JSObject;
    if (!capabilities.has('torch')) return false;
    final torch = capabilities['torch'];
    return torch.isA<JSBoolean>() && (torch as JSBoolean).toDart;
  }

  /// Turns the torch on when [enabled], off otherwise.
  ///
  /// Whether it worked is taken from the promise alone. The track's
  /// settings are not read back: iOS 18 reports the old value (bug 280970).
  Future<void> setTorch(bool enabled) async {
    final track = _videoTrack;
    if (track == null || !hasTorch) return;
    final constraints =
        {
              'advanced': [
                {'torch': enabled},
              ],
            }.jsify()!
            as web.MediaTrackConstraints;
    // Best effort, exactly as on the native platforms: the promise is the
    // only answer, and a rejection means no torch today.
    await settle<JSAny?>(track.applyConstraints(constraints));
  }

  /// Stops the stream and releases the element.
  void close() {
    if (_closed) return;
    _closed = true;
    _resize?.cancel();
    for (final track in _stream.getTracks().toDart) {
      track.stop();
    }
    video
      ..pause()
      ..srcObject = null;
    video.remove();
    _shapeChanges.close();
    _lost.close();
  }
}
