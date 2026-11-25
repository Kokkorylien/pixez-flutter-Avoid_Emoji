import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:pixez/component/pixiv_image.dart';
import 'package:pixez/document_plugin.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/task_persist.dart';
import 'package:pixez/store/save_store.dart';

class ReadingImageRequest {
  final String original;
  final String preview;
  final List<String> previews;
  final Future<List<String>> Function() savedNames;

  ReadingImageRequest({
    required this.original,
    required this.preview,
    required this.previews,
    required this.savedNames,
  });

  factory ReadingImageRequest.forIllust(Illusts illust, int index) {
    final page = illust.metaPages.elementAtOrNull(index)?.imageUrls;
    final original = page?.original ?? illust.metaSinglePage!.originalImageUrl!;
    return ReadingImageRequest(
      original: original,
      preview: page?.large ?? illust.imageUrls.large,
      previews: [
        page?.medium ?? illust.imageUrls.medium,
        page?.large ?? illust.imageUrls.large,
      ],
      savedNames: () async {
        final extension = Uri.parse(original).path.endsWith('.png')
            ? '.png'
            : '.jpg';
        final names = <String>{};
        // Retain compatibility with downloads made before the location index.
        final old = await _oldTask(original);
        if (old != null) {
          names.addAll([
            old.fileName,
            applySaveFolders(illust, old.fileName),
            '${userSetting.sanitizeFileName(old.userName)}_${old.userId}/${old.fileName}',
            'sanity/${old.fileName}',
          ]);
        }
        try {
          final name = await buildSaveFileName(illust, index, extension);
          names.addAll([applySaveFolders(illust, name), name]);
        } catch (_) {
          // A changed/removed naming script must not hide older downloads.
        }
        return names.toList();
      },
    );
  }

  static Future<TaskPersist?> _oldTask(String url) async {
    try {
      return await fetcher.taskPersistProvider.getAccount(url);
    } catch (_) {
      return null;
    }
  }
}

/// Reading uses a saved document, a completed original cache, or the normal
/// (large) preview. Only an explicit HD request downloads an original.
class ReadingImages {
  final BaseCacheManager cache;
  final Future<String?> Function(String, List<String>) findSaved;
  final Future<Uint8List?> Function(String) readSaved;
  final _readers = <ReadingImageSubscription>{};
  final _completed = <String, File>{};
  final _reads = <String, Future<Uint8List>>{};
  final _revisions = <String, int>{};

  ReadingImages({
    required this.cache,
    required this.findSaved,
    required this.readSaved,
  });

  int revisionOf(String url) => _revisions[url] ?? 0;

  ReadingImageSubscription watchOriginals(Future<void> Function(String) ready) {
    final subscription = ReadingImageSubscription._(ready, _readers.remove);
    _readers.add(subscription);
    return subscription;
  }

  Future<void> downloaded(String url, File file) async {
    _completed[url] = file;
    _revisions[url] = revisionOf(url) + 1;
    // Only active readers have a handoff to finish. Disposing/backgrounding a
    // reader releases its wait; saving without an open reader starts at once.
    await Future.wait(_readers.toList().map((reader) => reader._ready(url)));
  }

  Future<Uint8List?> original(ReadingImageRequest request) async {
    try {
      final location = await findSaved(request.original, const []);
      if (location != null) {
        final bytes = await readSaved(location);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      // Removed card, revoked grant, deleted file, or a non-Android platform.
    }
    try {
      final file =
          _completed[request.original] ??
          (await cache.getFileFromCache(
            request.original,
            ignoreMemCache: true,
          ))?.file;
      if (file != null) {
        return await _read(request.original, file.readAsBytes);
      }
    } catch (_) {}
    try {
      final location = await findSaved(
        request.original,
        await request.savedNames(),
      );
      if (location != null) {
        final bytes = await readSaved(location);
        if (bytes != null && bytes.isNotEmpty) return bytes;
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List> preview(ReadingImageRequest request) async {
    return _read(
      request.preview,
      () async => (await cache.getSingleFile(
        request.preview,
        headers: Hoster.header(url: request.preview),
      )).readAsBytes(),
    );
  }

  Future<Uint8List> _read(String url, Future<Uint8List> Function() load) async {
    final pending = _reads.putIfAbsent(url, load);
    try {
      return await pending;
    } finally {
      if (identical(_reads[url], pending)) _reads.remove(url);
    }
  }

  Future<Uint8List> bytes(ReadingImageRequest request) async =>
      await original(request) ?? await preview(request);

  Future<Uint8List> downloadOriginal(ReadingImageRequest request) => _read(
    request.original,
    () async => (await cache.getSingleFile(
      request.original,
      headers: Hoster.header(url: request.original),
    )).readAsBytes(),
  );

  /// Only call after the destination is closed, readable, and indexed.
  Future<void> saved(String original, Iterable<String> previews) async {
    // The decoded image is independent of its storage location. Moving the
    // source must not replace/redecode the image already on screen.
    for (final url in {...previews, original}) {
      try {
        // A preview already being read must finish before its file is unlinked.
        await _reads[url];
        await cache.removeFile(url);
      } catch (_) {}
    }
    _completed.remove(original);
  }
}

class ReadingImageSubscription {
  final Future<void> Function(String) _onOriginal;
  final void Function(ReadingImageSubscription) _remove;
  final _closed = Completer<void>();

  ReadingImageSubscription._(this._onOriginal, this._remove);

  Future<void> _ready(String url) async {
    if (_closed.isCompleted) return;
    try {
      await Future.any([_onOriginal(url), _closed.future]);
    } catch (_) {
      // Reader/decode failure must not discard an otherwise valid download.
    }
  }

  void cancel() {
    if (_closed.isCompleted) return;
    _remove(this);
    _closed.complete();
  }
}

enum ReadingImageMode { automatic, original, preview }

final readingImages = ReadingImages(
  cache: pixivCacheManager!,
  findSaved: (url, names) => Platform.isAndroid
      ? DocumentPlugin.findOriginal(url, names)
      : Future.value(null),
  readSaved: DocumentPlugin.readOriginal,
);

class ReadingImageProvider extends ImageProvider<ReadingImageProvider> {
  final ReadingImageRequest request;
  final int revision;
  final ReadingImageMode mode;
  final ReadingImages images;
  final VoidCallback? onDecoded;
  bool? isOriginal;

  ReadingImageProvider(
    this.request, {
    this.revision = 0,
    this.mode = ReadingImageMode.automatic,
    this.onDecoded,
    ReadingImages? images,
  }) : images = images ?? readingImages;

  @override
  Future<ReadingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ReadingImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = mode == ReadingImageMode.preview
        ? null
        : await images.original(request) ??
              (mode == ReadingImageMode.original
                  ? await images.downloadOriginal(request)
                  : null);
    if (bytes != null) {
      try {
        final codec = await decode(
          await ui.ImmutableBuffer.fromUint8List(bytes),
        );
        isOriginal = true;
        onDecoded?.call();
        return codec;
      } catch (_) {
        // An unreadable/corrupt original must not strand the reader on an error.
      }
    }
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(await images.preview(request)),
    );
    isOriginal = false;
    onDecoded?.call();
    return codec;
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingImageProvider &&
      other.request.original == request.original &&
      other.revision == revision &&
      other.mode == mode &&
      identical(other.images, images);

  @override
  int get hashCode => Object.hash(request.original, revision, mode, images);
}
