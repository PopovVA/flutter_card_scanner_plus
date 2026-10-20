import 'dart:async';

import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_card_scanner_plus/src/web/scan_crop.dart';
import 'package:flutter_card_scanner_plus/src/web/scan_loop.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera that always has a 1920 by 1080 frame to give.
class FakeSource implements ScanFrameSource {
  int grabs = 0;
  int released = 0;
  ({int width, int height})? size = (width: 1920, height: 1080);
  ScanCrop? lastCrop;

  @override
  ({int width, int height})? get frameSize => size;

  @override
  Future<Object?> grab(ScanCrop crop) async {
    grabs++;
    lastCrop = crop;
    return 'frame $grabs';
  }

  @override
  void release(Object frame) => released++;
}

/// An engine a test drives: it answers, fails, or never answers at all.
class FakeRecognizer implements ScanRecognizer {
  FakeRecognizer({this.lines = const []});

  List<TextLine> lines;
  int calls = 0;
  int restarts = 0;
  int disposals = 0;

  /// Fails every call while set.
  Object? failWith;

  /// Never answers while set, so the loop has to time out.
  bool hang = false;

  @override
  Future<RecognizedFrame> recognize(Object frame, ScanCrop crop) async {
    calls++;
    if (hang) return Completer<RecognizedFrame>().future;
    final failure = failWith;
    if (failure != null) throw failure;
    return RecognizedFrame(lines: lines);
  }

  @override
  void restart() => restarts++;

  @override
  Future<void> dispose() async => disposals++;
}

void main() {
  const tick = Duration(milliseconds: 10);

  /// Waits until [done] holds. The loop runs on real timers, so a test
  /// that slept a fixed number of them would fail on a busy machine.
  Future<void> until(
    bool Function() done, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'timed out waiting');
  }

  /// Gives the loop room to do something it should not do. Only used for
  /// expectations that nothing happened, which cannot flake.
  Future<void> quiet() => Future<void>.delayed(tick * 6);

  ScanLoop loopFor(
    FakeSource source,
    FakeRecognizer recognizer, {
    required void Function(RecognizedFrame) onFrame,
    required void Function(CardScannerException) onError,
    Duration frameTimeout = const Duration(milliseconds: 50),
  }) => ScanLoop(
    source: source,
    recognizer: recognizer,
    onFrame: onFrame,
    onError: onError,
    interval: tick,
    frameTimeout: frameTimeout,
  );

  test('recognized frames reach the listener', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer(
      lines: const [TextLine(text: '4111 1111 1111 1111')],
    );
    final frames = <RecognizedFrame>[];
    final loop = loopFor(
      source,
      recognizer,
      onFrame: frames.add,
      onError: (_) => fail('should not give up'),
    );
    addTearDown(loop.dispose);

    loop.start();
    await until(() => frames.isNotEmpty);
    loop.stop();

    expect(frames.first.lines.single.text, '4111 1111 1111 1111');
    expect(source.released, source.grabs, reason: 'every frame is released');
  });

  test('the region is cropped out of the frame', () async {
    final source = FakeSource();
    final loop = loopFor(
      source,
      FakeRecognizer(),
      onFrame: (_) {},
      onError: (_) {},
    )..region = const TextBox(left: 0.25, top: 0, width: 0.5, height: 0.5);
    addTearDown(loop.dispose);

    loop.start();
    await until(() => source.lastCrop != null);
    loop.stop();

    expect(source.lastCrop?.left, 480);
    expect(source.lastCrop?.width, 960);
  });

  test('a region off the frame is skipped, not failed', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer();
    final loop = loopFor(
      source,
      recognizer,
      onFrame: (_) => fail('nothing to recognize'),
      onError: (_) => fail('not a failure'),
    )..region = const TextBox(left: 1, top: 0, width: 0.2, height: 0.2);
    addTearDown(loop.dispose);

    loop.start();
    await quiet();
    loop.stop();

    expect(source.grabs, 0);
    expect(recognizer.calls, 0);
  });

  test('a camera with no size yet is waited for', () async {
    final source = FakeSource()..size = null;
    final loop = loopFor(
      source,
      FakeRecognizer(),
      onFrame: (_) {},
      onError: (_) => fail('not a failure'),
    );
    addTearDown(loop.dispose);

    loop.start();
    await quiet();
    loop.stop();

    expect(source.grabs, 0);
  });

  test('one bad frame is forgiven', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer()..failWith = StateError('decode failed');
    final frames = <RecognizedFrame>[];
    final loop = loopFor(
      source,
      recognizer,
      onFrame: frames.add,
      onError: (_) => fail('one failure is not enough to give up'),
    );
    addTearDown(loop.dispose);

    loop.start();
    await until(() => loop.consecutiveFailures == 1);
    recognizer.failWith = null;
    await until(() => frames.isNotEmpty);
    loop.stop();

    expect(loop.consecutiveFailures, 0);
  });

  test('three failures in a row mean the engine is gone', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer()..failWith = StateError('no worker');
    final errors = <CardScannerException>[];
    final loop = loopFor(
      source,
      recognizer,
      onFrame: (_) => fail('nothing works'),
      onError: errors.add,
    );
    addTearDown(loop.dispose);

    loop.start();
    await until(() => errors.isNotEmpty);

    expect(errors, hasLength(1));
    expect(errors.single.code, 'ocrUnavailable');
    expect(loop.isRunning, isFalse, reason: 'it stopped trying');
    expect(recognizer.restarts, 1, reason: 'the engine is replaced');
    expect(recognizer.calls, 3, reason: 'and no fourth attempt');
  });

  test('a frame that never comes back counts as a failure', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer()..hang = true;
    final errors = <CardScannerException>[];
    final loop = loopFor(
      source,
      recognizer,
      onFrame: (_) => fail('nothing comes back'),
      onError: errors.add,
      frameTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(loop.dispose);

    loop.start();
    await until(() => errors.isNotEmpty);

    expect(errors.single.code, 'ocrUnavailable');
  });

  test('only one frame is in flight at a time', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer()..hang = true;
    final loop = loopFor(
      source,
      recognizer,
      onFrame: (_) {},
      onError: (_) {},
      frameTimeout: const Duration(seconds: 10),
    );
    addTearDown(loop.dispose);

    loop.start();
    await until(() => recognizer.calls == 1);
    await quiet();
    loop.stop();

    expect(recognizer.calls, 1, reason: 'the first frame is still in flight');
  });

  test('stopping drops a frame that was already in flight', () async {
    final source = FakeSource();
    final recognizer = FakeRecognizer();
    final frames = <RecognizedFrame>[];
    final loop = loopFor(
      source,
      recognizer,
      onFrame: frames.add,
      onError: (_) {},
    );
    addTearDown(loop.dispose);

    loop.start();
    loop.stop();
    await quiet();

    expect(frames, isEmpty);
  });

  test('disposing releases the engine', () async {
    final recognizer = FakeRecognizer();
    final loop = loopFor(
      FakeSource(),
      recognizer,
      onFrame: (_) {},
      onError: (_) {},
    );
    loop.start();
    await loop.dispose();

    expect(loop.isRunning, isFalse);
    expect(recognizer.disposals, 1);
  });
}
