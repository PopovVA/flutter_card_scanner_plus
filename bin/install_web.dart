// Puts the browser OCR engine into an app's web folder.
//
// Run from the root of the app that depends on this package:
//
//     dart run flutter_card_scanner_plus:install_web
//
// The files come to about 38 MB, which is why they are not shipped inside
// the package: every iOS and Android build would carry them for nothing.
// They are fetched from npm at the versions pinned below, checked against
// hashes recorded here, and written next to the app's index.html.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Folder created under the app's `web/`.
const outputDirectory = 'flutter_card_scanner_plus';

/// The worker bundle, which ships inside this package.
const workerFile = 'card_ocr_worker.js';

/// One file the engine needs at run time.
class EngineFile {
  const EngineFile({
    required this.package,
    required this.version,
    required this.path,
    required this.name,
    required this.sha512,
    this.transform,
    this.produces = const {},
  });

  /// npm package it comes from.
  final String package;

  /// Exact version, so a rebuild fetches the same bytes.
  final String version;

  /// Path inside the package tarball, without the leading `package/`.
  final String path;

  /// Name to write it under.
  final String name;

  /// Expected SHA-512 of the file as npm ships it, recorded when it was
  /// pinned. A [transform] runs only after this matches.
  final String sha512;

  /// Rewrites the file on the way in, given the bytes npm shipped and the
  /// directory being written to. Returns a reason to stop, or `null`.
  ///
  /// Only OpenCV needs this, and it needs it badly: see [splitOpenCv].
  final String? Function(List<int> bytes, Directory target)? transform;

  /// What a [transform] writes, by name and expected SHA-512.
  ///
  /// These are what an existing install is checked against, since the bytes
  /// on disk are no longer the ones npm shipped. A transform is
  /// deterministic, so they are as fixed as [sha512] is.
  final Map<String, String> produces;

  /// Files this entry leaves on disk, by name.
  Iterable<String> get outputs => produces.isEmpty ? [name] : produces.keys;

  /// The tarball npm serves for [package] at [version].
  String get tarballUrl {
    final scoped = package.startsWith('@');
    final short = scoped ? package.split('/').last : package;
    return 'https://registry.npmjs.org/$package/-/$short-$version.tgz';
  }
}

/// Everything the worker fetches at run time.
///
/// The versions are the ones the worker bundle was built against.
/// Upgrading one means rebuilding the bundle and re-recording its hash.
const engine = [
  EngineFile(
    package: '@techstark/opencv-js',
    version: '4.9.0-release.3',
    path: 'dist/opencv.js',
    name: 'opencv.js',
    sha512:
        'ea579321bbfb7b6fced787e6bb3c7b1c821de548cd7935c4b8078a2f7712303a'
        '5dcba676cc288834a4018e3d3fc09e54775ae5ce99bb0b8e3c91c28c302aa4dc',
    // Split before it is written. See [splitOpenCv].
    transform: splitOpenCv,
    produces: openCvOutputs,
  ),
  // 1.18 is the last release with a single-threaded build. See the README
  // section "Why ONNX Runtime is pinned": from 1.19 the loader asks for a
  // 4 GB shared memory even at one thread, and iOS Safari refuses it.
  // The glue code is inside the worker bundle, so there is no .mjs.
  EngineFile(
    package: 'onnxruntime-web',
    version: '1.18.0',
    path: 'dist/ort-wasm-simd.wasm',
    name: 'ort-wasm-simd.wasm',
    sha512:
        '866358a04d466c0a334ea927bce02c2cf817623a5245c6cb8d1a60673747c8bd'
        '68ffc2f9285c1a36aa12d152b0fe056da7e1e4cac146b33d453828a2c808ae6c',
  ),
  EngineFile(
    package: '@gutenye/ocr-models',
    version: '1.4.2',
    path: 'assets/ch_PP-OCRv4_det_infer.onnx',
    name: 'ch_PP-OCRv4_det_infer.onnx',
    sha512:
        '8fac6c85726e0e0b055897230d5ab49de5890703e13bd209fd2dfd0325212e01'
        'aa3896ebe9851139029e9208a6000ade3badb378c4a84d4f395fc3c3e5a84d35',
  ),
  EngineFile(
    package: '@gutenye/ocr-models',
    version: '1.4.2',
    path: 'assets/ch_PP-OCRv4_rec_infer.onnx',
    name: 'ch_PP-OCRv4_rec_infer.onnx',
    sha512:
        '78a5367312092559ca21383d8cad24e8b56c4ebc662d7e037bbd169240681c99'
        '6db9290c40bf990a705a2f0fa0500ffeea8eb89ca492699017c0e6fc9e0bc30c',
  ),
  EngineFile(
    package: '@gutenye/ocr-models',
    version: '1.4.2',
    path: 'assets/ppocr_keys_v1.txt',
    name: 'ppocr_keys_v1.txt',
    sha512:
        '85473930e51551790d98973488cb8a4833fa9521ac83d0b6da339907d09d15d5'
        '7fcb98ae3328f712958d142fa57bf5f6f21c219d90fda810aca397979fa9ccd4',
  ),
];

/// What [splitOpenCv] writes, by name and expected SHA-512.
///
/// Recorded from a run against the pinned `opencv.js`: the split is a
/// base64 decode and one string replacement, so it is reproducible.
const openCvOutputs = {
  'opencv.js':
      '969b9062e1f4c8265a46de4908049a627e62103946a4f0cd6ac6ab74fd4fe2b7'
      '64d4c1afe5f0bb33eec9946ff6e0b3f2b5ee4016c0dce9d66cbfd29e9e0d1a68',
  'opencv.wasm':
      '6acfa0cce16ecb54fe318969d76eab2a46e12bc8c9f504b01c69b36a62b68377'
      '9c67eccb497f14bf87a995f90e6cfa2e8a2a5b7dac27ce802561196b7ad2e2bd',
};

/// How the quoted `data:` URI OpenCV carries its WebAssembly in starts.
const _openCvDataUri = '"data:application/octet-stream;base64,';

/// Writes OpenCV's WebAssembly as its own file and points `opencv.js` at
/// it, instead of leaving 10 MB of base64 inside the script.
///
/// `@techstark/opencv-js` inlines the 7.5 MB binary as a `data:` URI.
/// Parsing that string and decoding it costs tens of megabytes of
/// JavaScript heap, which is the difference between a scan that runs on an
/// iPhone and a tab the system kills. Safari also logs a CSP refusal for
/// the fetch of that URI, which is harmless and alarming.
///
/// OpenCV resolves a bare name against the directory the script was loaded
/// from, and in a worker that is this directory, so the name is enough.
String? splitOpenCv(List<int> bytes, Directory target) {
  final script = utf8.decode(bytes, allowMalformed: true);

  // Found by hand rather than by pattern: the URI is 10 MB long, and a
  // regular expression with a capture group that size overflows the stack.
  //
  // The prefix appears twice. The first is the empty literal OpenCV
  // compares against to decide whether its binary is inlined, and it has
  // to stay; the one worth splitting is the one carrying the binary.
  var start = -1;
  var from = -1;
  var end = -1;
  for (var at = script.indexOf(_openCvDataUri); at >= 0;) {
    final payload = at + _openCvDataUri.length;
    final close = script.indexOf('"', payload);
    if (close > 0 && close - payload > _shortestWasm) {
      start = at;
      from = payload;
      end = close;
      break;
    }
    at = script.indexOf(_openCvDataUri, at + 1);
  }
  if (start < 0) {
    return _openCvChanged;
  }

  final Uint8List wasm;
  try {
    wasm = base64.decode(script.substring(from, end));
  } on FormatException {
    return _openCvChanged;
  }

  File('${target.path}/opencv.wasm').writeAsBytesSync(wasm);
  File('${target.path}/opencv.js')
      .writeAsStringSync(script.replaceRange(start, end + 1, '"opencv.wasm"'));
  return null;
}

/// Shortest base64 payload worth treating as the WebAssembly binary.
/// OpenCV's is about 10 million characters; the decoy is empty.
const _shortestWasm = 1024;

const _openCvChanged =
    'opencv.js no longer carries its WebAssembly as one quoted base64 data '
    'URI. The split in bin/install_web.dart has to be revisited before this '
    'version of OpenCV can be used.';

Future<int> main(List<String> arguments) async {
  final force = arguments.contains('--force');
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(_usage);
    return 0;
  }

  final web = Directory('web');
  if (!web.existsSync()) {
    stderr.writeln(
      'No web/ directory here. Run this from the root of a Flutter app '
      'that has web enabled.',
    );
    return 1;
  }

  final target = Directory('${web.path}/$outputDirectory');
  target.createSync(recursive: true);

  final worker = _workerSource();
  if (worker == null) {
    stderr.writeln(
      'Could not find $workerFile inside the package. A checkout of the '
      'repository builds it with: cd tool/ocr_worker && npm install && '
      'npm run build',
    );
    return 1;
  }
  worker.copySync('${target.path}/$workerFile');
  stdout.writeln('  $workerFile  ${_size(worker.lengthSync())}');

  final temporary = Directory.systemTemp.createTempSync('card_scanner_web');
  try {
    for (final file in engine) {
      if (!force && await _alreadyInstalled(file, target)) {
        stdout.writeln('  ${file.name}  already in place');
        continue;
      }
      final written = File('${target.path}/${file.name}');
      if (!await _fetch(file, temporary, written)) return 1;
    }
  } finally {
    temporary.deleteSync(recursive: true);
  }

  stdout.writeln(
    '\nDone. Two things left, both in your app rather than here:\n'
    '\n'
    '  1. Serve web/$outputDirectory/ as it is. Nothing in it should be\n'
    '     renamed or inlined.\n'
    '  2. Send a Content-Security-Policy with $workerFile:\n'
    "       default-src 'none'; script-src 'self' 'unsafe-eval' "
    "'wasm-unsafe-eval'; connect-src 'self'\n"
    "     'unsafe-eval' is required: OpenCV's bindings generate code.\n"
    "     connect-src 'self' is what stops the worker, which sees pictures\n"
    '     of cards, from sending them anywhere.\n'
    '\n'
    'Add web/$outputDirectory/ to .gitignore and run this in CI instead of\n'
    'committing 38 MB.',
  );
  return 0;
}

const _usage =
    '''
Installs the browser OCR engine into web/$outputDirectory/.

Usage: dart run flutter_card_scanner_plus:install_web [--force]

  --force   Fetch every file again, even one already in place.

Needs npm on PATH: the files are pulled from the npm registry, which checks
each tarball against its own hash, and every extracted file is checked
again against a hash pinned in this script.
''';

/// The worker bundle inside this package, wherever pub put it.
File? _workerSource() {
  final candidates = <String>[
    // Resolved through the package config, which is how an app sees it.
    ..._fromPackageConfig(),
    // A checkout of the repository itself.
    'assets/$workerFile',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) return file;
  }
  return null;
}

Iterable<String> _fromPackageConfig() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return const [];
  // Read without a JSON dependency: the one entry needed is easy to find
  // and this script deliberately has no package dependencies at all.
  final text = config.readAsStringSync();
  final marker = '"name": "flutter_card_scanner_plus"';
  final at = text.indexOf(marker);
  if (at < 0) return const [];
  final rootKey = '"rootUri": "';
  final start = text.indexOf(rootKey, at);
  if (start < 0) return const [];
  final from = start + rootKey.length;
  final end = text.indexOf('"', from);
  if (end < 0) return const [];
  var root = text.substring(from, end);
  if (root.startsWith('file://')) {
    root = Uri.parse(root).toFilePath();
  } else {
    root = Uri.file('${Directory('.dart_tool').absolute.path}/$root')
        .normalizePath()
        .toFilePath();
  }
  return ['$root/assets/$workerFile'];
}

/// Whether every file [entry] produces is already on disk and intact.
///
/// A machine with no SHA-512 tool cannot tell, and fetching again is the
/// safe answer there.
Future<bool> _alreadyInstalled(EngineFile entry, Directory target) async {
  for (final name in entry.outputs) {
    final file = File('${target.path}/$name');
    if (!file.existsSync()) return false;
    final actual = await _sha512(file.path);
    if (actual == null) return false;
    if (actual != (entry.produces[name] ?? entry.sha512)) return false;
  }
  return true;
}

/// Downloads [file]'s package, checks the file and writes it to [written].
Future<bool> _fetch(EngineFile file, Directory temporary, File written) async {
  // One directory per package, so the tarball in it is unambiguous. Two
  // packages sharing a directory made the second one extract the first.
  final slug = '${file.package}@${file.version}'.replaceAll(
    RegExp('[^A-Za-z0-9._-]'),
    '_',
  );
  final home = Directory('${temporary.path}/$slug');

  if (!home.existsSync()) {
    home.createSync(recursive: true);
    stdout.writeln('  fetching ${file.package}@${file.version}');
    final packed = await Process.run('npm', [
      'pack',
      '${file.package}@${file.version}',
      '--pack-destination',
      home.path,
      '--silent',
    ], runInShell: true);
    if (packed.exitCode != 0) {
      stderr.writeln(
        'npm pack failed for ${file.package}@${file.version}:\n'
        '${packed.stderr}',
      );
      return false;
    }
  }

  final tarball = home
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.tgz'))
      .firstOrNull;
  if (tarball == null) {
    stderr.writeln('npm pack produced nothing for ${file.package}');
    return false;
  }

  final extracted = await Process.run('tar', [
    '-xzf',
    tarball.path,
    '-C',
    home.path,
    'package/${file.path}',
  ]);
  if (extracted.exitCode != 0) {
    stderr.writeln(
      'Could not extract ${file.path} from ${file.package}:\n'
      '${extracted.stderr}',
    );
    return false;
  }

  final source = File('${home.path}/package/${file.path}');
  final actual = await _sha512(source.path);
  if (actual != null && actual != file.sha512) {
    stderr.writeln(
      'The hash of ${file.name} does not match what this script pins.\n'
      '  expected ${file.sha512}\n'
      '  got      $actual\n'
      'Refusing to install it.',
    );
    return false;
  }
  if (actual == null) {
    stdout.writeln(
      '  warning: no SHA-512 tool on this machine, so ${file.name} was '
      'taken on npm\'s word alone',
    );
  }

  final transform = file.transform;
  if (transform != null) {
    final refusal = transform(source.readAsBytesSync(), written.parent);
    if (refusal != null) {
      stderr.writeln(refusal);
      return false;
    }
  } else {
    source.copySync(written.path);
  }
  stdout.writeln('  ${file.name}  ${_size(written.lengthSync())}');
  return true;
}

/// The SHA-512 of [path], or `null` when the machine has no tool for it.
Future<String?> _sha512(String path) async {
  for (final attempt in [
    ['shasum', '-a', '512', path],
    ['sha512sum', path],
    ['openssl', 'dgst', '-sha512', path],
  ]) {
    try {
      final run = await Process.run(attempt.first, attempt.skip(1).toList());
      if (run.exitCode != 0) continue;
      final out = (run.stdout as String).trim();
      final hash = RegExp('[0-9a-f]{128}').firstMatch(out)?.group(0);
      if (hash != null) return hash;
    } on ProcessException {
      continue;
    }
  }
  return null;
}

String _size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).round()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
