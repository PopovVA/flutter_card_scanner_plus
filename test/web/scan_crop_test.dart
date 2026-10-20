import 'package:flutter_card_scanner_plus/flutter_card_scanner_plus.dart';
import 'package:flutter_card_scanner_plus/src/web/scan_crop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanCrop? cropFor(
    TextBox? region, {
    int w = 1920,
    int h = 1080,
    int side = 960,
  }) => ScanCrop.from(
    region: region,
    videoWidth: w,
    videoHeight: h,
    longestSide: side,
  );

  test('no region means the whole frame, shrunk to the limit', () {
    final crop = cropFor(null)!;
    expect(crop.left, 0);
    expect(crop.top, 0);
    expect(crop.width, 1920);
    expect(crop.height, 1080);
    expect(crop.outWidth, 960);
    expect(crop.outHeight, 540);
  });

  test('a region becomes whole pixels of the frame', () {
    final crop = cropFor(
      const TextBox(left: 0.25, top: 0.1, width: 0.5, height: 0.3),
    )!;
    expect(crop.left, 480);
    expect(crop.top, 108);
    expect(crop.width, 960);
    expect(crop.height, 324);
  });

  test('the shape of the region survives the shrink', () {
    final crop = cropFor(
      const TextBox(left: 0.1, top: 0.1, width: 0.8, height: 0.5),
    )!;
    expect(
      crop.outWidth / crop.outHeight,
      closeTo(crop.width / crop.height, 0.01),
    );
    expect(crop.outWidth, lessThanOrEqualTo(960));
    expect(crop.outHeight, lessThanOrEqualTo(960));
  });

  test('a small crop is never enlarged', () {
    final crop = cropFor(
      const TextBox(left: 0.4, top: 0.4, width: 0.1, height: 0.1),
    )!;
    expect(crop.width, 192);
    expect(crop.outWidth, 192);
    expect(crop.isFullSize, isTrue);
  });

  test('a region off the frame yields nothing to recognize', () {
    expect(
      cropFor(const TextBox(left: 1, top: 0, width: 0.2, height: 0.2)),
      isNull,
    );
    expect(
      cropFor(const TextBox(left: 0, top: 0, width: 0, height: 0.2)),
      isNull,
    );
  });

  test('a region hanging over an edge is clipped to the frame', () {
    final crop = cropFor(
      const TextBox(left: 0.8, top: 0.8, width: 0.5, height: 0.5),
    )!;
    expect(crop.left + crop.width, 1920);
    expect(crop.top + crop.height, 1080);
  });

  test('a camera that has not reported a size yet yields nothing', () {
    expect(cropFor(null, w: 0, h: 0), isNull);
  });

  test('a portrait frame is capped on its long side too', () {
    final crop = cropFor(null, w: 1080, h: 1920)!;
    expect(crop.outHeight, 960);
    expect(crop.outWidth, 540);
  });
}
