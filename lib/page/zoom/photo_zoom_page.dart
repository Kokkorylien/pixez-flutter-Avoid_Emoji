import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' show join, basenameWithoutExtension;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pixez/clipboard_plugin.dart';
import 'package:pixez/component/reader_download_sheet.dart';
import 'package:pixez/er/reading_image.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/utils/haptic_util.dart';
import 'package:share_plus/share_plus.dart';

class PhotoZoomPage extends StatefulWidget {
  final int index;
  final Illusts illusts;
  final IllustStore illustStore;
  final ReadingImages? images;

  const PhotoZoomPage({
    super.key,
    required this.index,
    required this.illusts,
    required this.illustStore,
    this.images,
  });

  @override
  State<PhotoZoomPage> createState() => _PhotoZoomPageState();
}

class _PhotoZoomPageState extends State<PhotoZoomPage>
    with WidgetsBindingObserver {
  static int _session = 0;
  late int _index;
  late PageController _pageController;
  late List<ReadingImageRequest> _requests;
  late ReadingImageSubscription _subscription;
  final _hdPages = <int>{};
  final _previewPages = <int>{};
  final _providers = <int, ReadingImageProvider>{};
  final _pendingImages = <int, VoidCallback>{};
  bool _allHd = false;
  bool _foreground = true;
  bool _fullScreen = false;
  bool _downloadSheetOpen = false;
  int _resumeRevision = ++_session;
  ReadingImages get _images => widget.images ?? readingImages;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _pageController = PageController(initialPage: _index);
    _requests = List.generate(
      widget.illusts.pageCount,
      (index) => ReadingImageRequest.forIllust(widget.illusts, index),
    );
    WidgetsBinding.instance.addObserver(this);
    _subscription = _images.watchOriginals((url) async {
      final page = _requests.indexWhere((request) => request.original == url);
      if (page < 0 || !mounted || _mode(page) == ReadingImageMode.preview)
        return;
      if (page == _index && _foreground) {
        await _replaceProvider(page);
      } else {
        _providers.remove(page)?.evict();
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _cancelPendingImages();
    if (state == AppLifecycleState.resumed && mounted) {
      for (final provider in _providers.values) {
        provider.evict();
      }
      setState(() {
        _providers.clear();
        _resumeRevision = ++_session;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _cancelPendingImages();
    _pageController.dispose();
    for (final provider in _providers.values) {
      provider.evict();
    }
    if (_fullScreen)
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  ReadingImageMode _mode(int index) => _previewPages.contains(index)
      ? ReadingImageMode.preview
      : _allHd || _hdPages.contains(index)
      ? ReadingImageMode.original
      : ReadingImageMode.automatic;

  bool _isHd(int index) {
    if (!_pendingImages.containsKey(index)) {
      final displayed = _providers[index]?.isOriginal;
      if (displayed != null) return displayed;
    }
    return _mode(index) != ReadingImageMode.preview &&
        (_mode(index) == ReadingImageMode.original ||
            _providers[index]?.isOriginal == true);
  }

  ReadingImageProvider _provider(int index) =>
      _providers.putIfAbsent(index, () => _newProvider(index));

  ReadingImageProvider _newProvider(int index) => ReadingImageProvider(
    _requests[index],
    images: _images,
    revision: _images.revisionOf(_requests[index].original) + _resumeRevision,
    mode: _mode(index),
    onDecoded: () {
      if (mounted) setState(() {});
    },
  );

  void _cancelPendingImages() {
    final pending = _pendingImages.values.toList();
    _pendingImages.clear();
    for (final cancel in pending) {
      cancel();
    }
  }

  Future<void> _replaceProvider(int index) async {
    _pendingImages.remove(index)?.call();
    final provider = _newProvider(index);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final ready = Completer<bool>();
    final cancelled = Completer<void>();
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!ready.isCompleted) ready.complete(true);
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.complete(false);
      },
    );
    void cancel() {
      if (cancelled.isCompleted) return;
      cancelled.complete();
      stream.removeListener(listener);
      if (!ready.isCompleted) ready.complete(false);
      if (!identical(_providers[index], provider)) provider.evict();
    }

    _pendingImages[index] = cancel;
    stream.addListener(listener);
    try {
      final decoded = await ready.future;
      if (!mounted || !identical(_pendingImages[index], cancel)) return;
      if (!decoded) {
        BotToast.showText(text: '无法切换画质，已保留当前图片');
        return;
      }
      final old = _providers[index];
      setState(() => _providers[index] = provider);
      // Keep the decoded stream alive until PhotoView has adopted it. This
      // also works for originals too large for Flutter's normal image cache.
      await Future.any([WidgetsBinding.instance.endOfFrame, cancelled.future]);
      old?.evict();
    } finally {
      if (identical(_pendingImages[index], cancel)) {
        _pendingImages.remove(index);
        if (mounted) setState(() {});
      }
      cancel();
    }
  }

  void _enableHd({bool all = false}) {
    HapticUtil.selectionClick();
    setState(() {
      if (all) {
        _allHd = true;
        _hdPages.clear();
        _previewPages.clear();
        for (final index in _providers.keys.toList()) {
          if (index != _index) _providers.remove(index)?.evict();
        }
      } else if (_isHd(_index)) {
        _hdPages.remove(_index);
        _previewPages.add(_index);
      } else {
        _hdPages.add(_index);
        _previewPages.remove(_index);
      }
    });
    _replaceProvider(_index);
    if (all) BotToast.showText(text: '本作品全部图片已启用原图，翻到时加载');
  }

  Future<void> _bookmarkAfterSave() async {
    if (userSetting.starAfterSave && widget.illustStore.state == 0) {
      await widget.illustStore.star(
        restrict: userSetting.defaultPrivateLike ? 'private' : 'public',
      );
    }
  }

  void _saveCurrent() {
    saveStore.saveImage(widget.illusts, index: _index);
    _bookmarkAfterSave();
  }

  Future<void> _showDownloads() async {
    if (_downloadSheetOpen) return;
    _downloadSheetOpen = true;
    HapticUtil.heavy();
    try {
      await showReaderDownloadSheet(context, widget.illusts, _index, (
        selected,
      ) {
        saveStore.saveChoiceImage(widget.illusts, selected);
        _bookmarkAfterSave();
      });
    } finally {
      _downloadSheetOpen = false;
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final request = _requests[_index];
    try {
      final bytes = _mode(_index) == ReadingImageMode.preview
          ? await _images.preview(request)
          : await _images.bytes(request);
      final dir = Directory(
        join((await getTemporaryDirectory()).path, 'share_cache'),
      );
      await dir.create(recursive: true);
      final extension =
          bytes.length >= 4 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47
          ? '.png'
          : '.jpg';
      final file = File(
        join(
          dir.path,
          '${basenameWithoutExtension(Uri.parse(request.original).path)}$extension',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!buttonContext.mounted) return;
      final box = buttonContext.findRenderObject() as RenderBox;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      BotToast.showText(text: '无法读取图片，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      bottomNavigationBar: _buildBottom(context),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _showDownloads,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.mouse,
            },
          ),
          child: PhotoViewGallery.builder(
            gaplessPlayback: true,
            pageController: _pageController,
            scrollPhysics: const BouncingScrollPhysics(),
            itemCount: _requests.length,
            onPageChanged: (index) {
              final pendingPages = _pendingImages.keys.toList();
              _cancelPendingImages();
              for (final page in pendingPages) {
                if (page != index) _providers.remove(page)?.evict();
              }
              setState(() => _index = index);
            },
            loadingBuilder: (context, event) => const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(),
              ),
            ),
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: _provider(index),
              initialScale: PhotoViewComputedScale.contained,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stack) => Center(
                child: TextButton(
                  onPressed: () {
                    _providers.remove(index)?.evict();
                    setState(() {
                      _resumeRevision = ++_session;
                    });
                  },
                  child: Text(I18n.of(context).retry),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottom(BuildContext context) {
    if (_fullScreen) {
      return BottomAppBar(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: '退出全屏',
            icon: const Icon(Icons.fullscreen_exit, color: Colors.white54),
            onPressed: () {
              setState(() => _fullScreen = false);
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            },
          ),
        ),
      );
    }
    return BottomAppBar(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            '${_index + 1}/${_requests.length}',
            style: const TextStyle(color: Colors.white),
          ),
          const Spacer(),
          Flexible(
            flex: 8,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                    onPressed: () {
                      setState(() => _fullScreen = true);
                      SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.manual,
                        overlays: [],
                      );
                    },
                  ),
                  if (ClipboardPlugin.supported)
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white),
                      onPressed: () =>
                          ClipboardPlugin.copy(context, widget.illusts, _index),
                    ),
                  Tooltip(
                    message: '下载当前图片，长按多选下载',
                    triggerMode: TooltipTriggerMode.manual,
                    child: GestureDetector(
                      onLongPress: _showDownloads,
                      child: IconButton(
                        icon: const Icon(Icons.save_alt, color: Colors.white),
                        onPressed: _saveCurrent,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: I18n.of(context).share,
                      icon: const Icon(Icons.share, color: Colors.white),
                      onPressed: () => _share(context),
                    ),
                  ),
                  Tooltip(
                    message: '点按切换原图／低清，长按全部图片原图',
                    triggerMode: TooltipTriggerMode.manual,
                    child: GestureDetector(
                      onLongPress: () => _enableHd(all: true),
                      child: IconButton(
                        icon: Icon(
                          _isHd(_index) ? Icons.hd : Icons.hd_outlined,
                          color: Colors.white,
                        ),
                        onPressed: _enableHd,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
