import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/install_web.dart';

/// A stand-in for `opencv.js`, built the way OpenCV builds it: the prefix
/// appears twice, once as the empty literal it compares against and once
/// carrying the binary.
String opencvScript(List<int> wasm) {
  final payload = base64.encode(wasm);
  return 'var dataURIPrefix="data:application/octet-stream;base64,";'
      'function isDataURI(f){return f.indexOf(dataURIPrefix)===0}'
      'var wasmBinaryFile="data:application/octet-stream;base64,$payload";'
      'var rest=1;';
}

void main() {
  late Directory target;

  setUp(() => target = Directory.systemTemp.createTempSync('install_web'));
  tearDown(() => target.deleteSync(recursive: true));

  File written(String name) => File('${target.path}/$name');

  group('splitOpenCv', () {
    // Long enough to be taken for the binary rather than the decoy.
    final wasm = List<int>.generate(4096, (i) => i % 256);

    test('writes the binary as its own file', () {
      final refusal = splitOpenCv(utf8.encode(opencvScript(wasm)), target);

      expect(refusal, isNull);
      expect(written('opencv.wasm').readAsBytesSync(), wasm);
    });

    test('points the script at the file and keeps the rest of it', () {
      splitOpenCv(utf8.encode(opencvScript(wasm)), target);
      final script = written('opencv.js').readAsStringSync();

      expect(script, contains('var wasmBinaryFile="opencv.wasm";'));
      expect(script, contains('var rest=1;'));
      // The literal OpenCV compares against has to survive, or it stops
      // recognizing an inlined binary at all.
      expect(
        script,
        contains('var dataURIPrefix="data:application/octet-stream;base64,";'),
      );
      expect(script, isNot(contains(base64.encode(wasm))));
    });

    test('the script loses the weight of the base64', () {
      final before = opencvScript(wasm);
      splitOpenCv(utf8.encode(before), target);

      expect(
        written('opencv.js').lengthSync(),
        lessThan(before.length - wasm.length),
      );
    });

    test('refuses a script that no longer inlines its binary', () {
      final refusal = splitOpenCv(
        utf8.encode(
          'var dataURIPrefix="data:application/octet-stream;base64,";'
          'var wasmBinaryFile="opencv.wasm";',
        ),
        target,
      );

      expect(refusal, contains('bin/install_web.dart'));
      expect(written('opencv.wasm').existsSync(), isFalse);
    });

    test('refuses a payload that is not base64', () {
      final refusal = splitOpenCv(
        utf8.encode(
          'var wasmBinaryFile="data:application/octet-stream;base64,'
          '${'!' * 2048}";',
        ),
        target,
      );

      expect(refusal, isNotNull);
      expect(written('opencv.js').existsSync(), isFalse);
    });
  });

  group('the engine manifest', () {
    test('installs one single-threaded ONNX runtime and no module glue', () {
      final names = engine.expand((e) => e.outputs).toList();

      expect(names, contains('ort-wasm-simd.wasm'));
      expect(
        names.where((n) => n.contains('threaded')),
        isEmpty,
        reason: 'the threaded build asks iOS for a 4 GB shared memory',
      );
      expect(names.where((n) => n.endsWith('.mjs')), isEmpty);
    });

    test('ONNX runtime stays on the last single-threaded release', () {
      final ort = engine.where((e) => e.package == 'onnxruntime-web');
      expect(ort, isNotEmpty);
      expect(ort.every((e) => e.version == '1.18.0'), isTrue);
    });

    test('OpenCV arrives as a script and a separate binary', () {
      final opencv = engine.singleWhere(
        (e) => e.package == '@techstark/opencv-js',
      );
      expect(opencv.outputs, containsAll(['opencv.js', 'opencv.wasm']));
      expect(opencv.transform, isNotNull);
    });

    test('every entry pins a version and a hash', () {
      for (final file in engine) {
        expect(file.version, matches(RegExp(r'^\d')), reason: file.name);
        expect(file.sha512.length, 128, reason: file.name);
        for (final hash in file.produces.values) {
          expect(hash.length, 128, reason: file.name);
        }
      }
    });
  });
}
