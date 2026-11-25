import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/er/reading_image.dart';

class TestCache extends Fake implements BaseCacheManager {
  final files = <String, fs.File>{};
  final responses = <String, fs.File>{};
  final requested = <String>[];
  final removed = <String>[];
  Future<fs.File>? pending;
  bool failRequests = false;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final file = files[key];
    return file == null
        ? null
        : FileInfo(
            file,
            FileSource.Cache,
            DateTime.now().add(const Duration(days: 1)),
            key,
          );
  }

  @override
  Future<fs.File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    requested.add(url);
    if (failRequests) throw StateError('offline');
    return pending ?? responses[url] ?? files[url]!;
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
    final file = files.remove(key);
    if (file != null && await file.exists()) await file.delete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TestCache cache;
  late ReadingImages images;
  String? saved;
  Uint8List? savedBytes;
  var fallbackLookups = 0;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7H8AAAAASUVORK5CYII=',
  );
  final request = ReadingImageRequest(
    original: 'original',
    preview: 'large',
    previews: ['large', 'medium'],
    savedNames: () async {
      fallbackLookups++;
      return ['custom name.jpg'];
    },
  );

  Future<fs.File> put(String url, List<int> bytes) async {
    final file = const LocalFileSystem().file('${directory.path}/$url');
    await file.writeAsBytes(bytes);
    cache.files[url] = file;
    return file;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pixez-reading-');
    cache = TestCache();
    saved = null;
    savedBytes = null;
    fallbackLookups = 0;
    images = ReadingImages(
      cache: cache,
      findSaved: (url, names) async => saved,
      readSaved: (location) async => savedBytes,
    );
    await put('large', [1, 2]);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('default reads preview and never downloads original', () async {
    expect(await images.bytes(request), [1, 2]);
    expect(cache.requested, ['large']);
  });

  test(
    'saved URI wins over original cache, without regenerating file names',
    () async {
      saved = 'content://card/opaque-id';
      savedBytes = Uint8List.fromList([9]);
      await put('original', [7]);
      expect(await images.bytes(request), [9]);
      expect(cache.requested, isEmpty);
      expect(fallbackLookups, 0);
    },
  );

  test(
    'completed original cache is used without network or scanning directory',
    () async {
      await put('original', [7]);
      expect(await images.bytes(request), [7]);
      expect(cache.requested, isEmpty);
      expect(fallbackLookups, 0);
    },
  );

  test('missing original file and removed card fall back to preview', () async {
    final old = await put('original', [7]);
    await old.delete();
    saved = 'content://removed-card/file';
    expect(await images.bytes(request), [1, 2]);
    expect(cache.requested, ['large']);
  });

  test('old custom download is discovered by candidate name', () async {
    images = ReadingImages(
      cache: cache,
      findSaved: (url, names) async =>
          names.contains('custom name.jpg') ? 'content://old/file' : null,
      readSaved: (location) async => Uint8List.fromList([6]),
    );
    expect(await images.bytes(request), [6]);
    expect(cache.requested, isEmpty);
  });

  test(
    'download completion updates active reader before destination save',
    () async {
      final notifications = <String>[];
      final sub = images.watchOriginals((url) async => notifications.add(url));
      final file = await put('temp-original', [8]);
      await images.downloaded('original', File(file.path));
      expect(notifications, ['original']);
      expect(await images.bytes(request), [8]);
      expect(cache.requested, isEmpty);
      sub.cancel();
    },
  );

  test(
    'migration waits for reader handoff, save does not notify twice',
    () async {
      final ready = Completer<void>();
      var notifications = 0;
      final reader = images.watchOriginals((_) {
        notifications++;
        return ready.future;
      });
      final file = await put('temp-original', [8]);
      var handedOff = false;
      final handoff = images.downloaded('original', file).then((_) {
        handedOff = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(handedOff, false);
      expect(cache.removed, isEmpty);
      ready.complete();
      await handoff;
      await images.saved('original', request.previews);
      expect(notifications, 1);
      expect(images.revisionOf('original'), 1);
      reader.cancel();
    },
  );

  test(
    'closing reader releases handoff without waiting for its decode',
    () async {
      final reader = images.watchOriginals((_) => Completer<void>().future);
      final file = await put('temp-original', [8]);
      var handedOff = false;
      final handoff = images.downloaded('original', file).then((_) {
        handedOff = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(handedOff, false);
      reader.cancel();
      await handoff;
      expect(handedOff, true);
    },
  );

  test(
    'destination save replaces cache, then deleted destination returns to preview',
    () async {
      await put('original', [7]);
      await put('medium', [0]);
      saved = 'content://card/saved';
      savedBytes = Uint8List.fromList([9]);
      await images.saved(request.original, request.previews);
      expect(cache.removed.toSet(), {'original', 'medium', 'large'});
      expect(await images.bytes(request), [9]);
      expect(cache.requested, isEmpty);
      saved = null;
      savedBytes = null;
      await put('large', [2]);
      expect(await images.bytes(request), [2]);
      expect(cache.requested, ['large']);
    },
  );

  test(
    'cleanup waits for actual image read and removes finished preview',
    () async {
      final pending = Completer<fs.File>();
      cache.pending = pending.future;
      final read = images.preview(request);
      var cleaned = false;
      final cleanup = images
          .saved('original', request.previews)
          .then((_) => cleaned = true);
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, false);
      pending.complete(cache.files['large']);
      expect(await read, [1, 2]);
      await cleanup;
      expect(cache.files.containsKey('large'), false);
    },
  );

  test('explicit HD downloads original and leaves preview alone', () async {
    final file = await put('original', png);
    cache.files.remove('original');
    cache.responses['original'] = file;
    expect(await images.downloadOriginal(request), png);
    expect(cache.requested, ['original']);
    expect(cache.files.containsKey('large'), true);
  });
}
