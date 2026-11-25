import 'dart:async';
import 'dart:convert';
import 'package:bot_toast/bot_toast.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pixez/component/ai_visibility_button.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/er/reading_image.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/zoom/photo_zoom_page.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'reading_image_test.dart' show TestCache;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryFileSystem filesystem;
  late TestCache cache;
  late ReadingImages images;
  late Illusts illust;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNoWHACAAOMAel7qFGdAAAAAElFTkSuQmCC',
  );
  final originalPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAD0lEQVR4nGNsWHCCgYEBAAlOAer+nQXJAAAAAElFTkSuQmCC',
  );
  const hdTooltip = '点按切换原图／低清，长按全部图片原图';

  Widget app(Widget home) => MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    builder: BotToastInit(),
    home: home,
  );

  Future<void> flushImages(WidgetTester tester) async {
    // File reads and image codecs use the real event loop in widget tests.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectImage(WidgetTester tester, int width) {
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((widget) => widget.image?.width == width),
      true,
      reason:
          'Expected width $width; image widths: ${tester.widgetList<RawImage>(find.byType(RawImage)).map((widget) => widget.image?.width).toList()}; texts: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}',
    );
  }

  ReadingImageProvider currentProvider(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .map((widget) => widget.image)
      .whereType<ReadingImageProvider>()
      .first;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    userSetting.prefs = await SharedPreferences.getInstance();
    userSetting.format = '{illust_id}_p{part}';
    userSetting.fileNameEval = 0;
    userSetting.starAfterSave = false;
    userSetting.zoomQuality =
        1; // An old HD preference must not force originals.
    await Prefer.init();
    muteStore.banAIIllust = false;
    filesystem = MemoryFileSystem();
    cache = TestCache();
    for (var i = 0; i < 3; i++) {
      for (final name in ['preview$i', 'original$i']) {
        final file = filesystem.file('/$name');
        await file.writeAsBytes(
          name.startsWith('original') ? originalPng : png,
        );
        if (name.startsWith('preview'))
          cache.files[name] = file;
        else
          cache.responses[name] = file;
      }
    }
    images = ReadingImages(
      cache: cache,
      findSaved: (url, names) async => null,
      readSaved: (_) async => null,
    );
    illust = Illusts(
      id: 123,
      title: 'reader',
      type: 'manga',
      imageUrls: ImageUrls(
        squareMedium: '',
        medium: 'preview0',
        large: 'preview0',
      ),
      caption: 'caption',
      restrict: 0,
      user: User(
        id: 42,
        name: 'artist',
        account: 'artist',
        profileImageUrls: ProfileImageUrls(medium: ''),
      ),
      tags: [],
      tools: [],
      createDate: '',
      pageCount: 3,
      width: 1,
      height: 1,
      sanityLevel: 0,
      xRestrict: 0,
      metaPages: List.generate(
        3,
        (i) => MetaPages(
          imageUrls: MetaPagesImageUrls(
            squareMedium: 'preview$i',
            medium: 'preview$i',
            large: 'preview$i',
            original: 'original$i',
          ),
        ),
      ),
      totalView: 0,
      totalComments: 0,
      totalBookmarks: 0,
      isBookmarked: false,
      visible: true,
      isMuted: false,
      illustAIType: 1,
    );
  });

  PhotoZoomPage reader() => PhotoZoomPage(
    index: 0,
    illusts: illust,
    illustStore: IllustStore(illust.id, illust),
    images: images,
  );

  testWidgets(
    'HD tap affects one page, HD long press affects rest, download long press is independent',
    (tester) async {
      await tester.pumpWidget(app(reader()));
      await flushImages(tester);
      expect(
        cache.requested.where((url) => url.startsWith('original')),
        isEmpty,
      );
      final hd = find.byTooltip(hdTooltip);
      await tester.tap(hd);
      await flushImages(tester);
      expect(cache.requested.where((url) => url.startsWith('original')), [
        'original0',
      ]);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
      await flushImages(tester);
      expect(find.text('2/3'), findsOneWidget);
      expect(cache.requested.contains('original1'), false);
      await tester.longPress(hd);
      await flushImages(tester);
      expect(cache.requested.contains('original1'), true);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.drag(find.byType(PhotoViewGallery), const Offset(-800, 0));
      await flushImages(tester);
      expect(find.text('3/3'), findsOneWidget);
      expect(cache.requested.contains('original2'), true);
      final count = cache.requested.length;
      await tester.longPress(find.byTooltip('下载当前图片，长按多选下载'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(cache.requested.length, count);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'download handoff retains preview until original frame, cleanup never replaces it',
    (tester) async {
      // Exercise the same lifetime as an original exceeding the memory cache:
      // the prepared stream must stay alive until PhotoView adopts its frame.
      final imageCache = PaintingBinding.instance.imageCache;
      final cacheLimit = imageCache.maximumSizeBytes;
      imageCache.maximumSizeBytes = 1;
      addTearDown(() => imageCache.maximumSizeBytes = cacheLimit);
      final lookup = Completer<String?>();
      var delayOriginal = false;
      images = ReadingImages(
        cache: cache,
        findSaved: (url, names) async =>
            delayOriginal && url == 'original0' ? await lookup.future : null,
        readSaved: (_) async => null,
      );
      await tester.pumpWidget(app(reader()));
      await flushImages(tester);
      expectImage(tester, 1);
      final previewProvider = currentProvider(tester);
      delayOriginal = true;
      var handedOff = false;
      final handoff = images
          .downloaded('original0', cache.responses['original0']!)
          .then((_) {
            handedOff = true;
          });
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectImage(tester, 1);
        expect(currentProvider(tester), same(previewProvider));
        expect(handedOff, false);
      }
      lookup.complete(null);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        if (handedOff) expectImage(tester, 2);
        expect(find.byType(RawImage), findsWidgets);
        expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null),
          true,
        );
      }
      await handoff;
      expectImage(tester, 2);
      final originalProvider = currentProvider(tester);
      expect(originalProvider, isNot(same(previewProvider)));
      await images.saved('original0', ['preview0']);
      await flushImages(tester);
      expect(currentProvider(tester), same(originalProvider));
      expectImage(tester, 2);
      expect(cache.removed.toSet(), {'preview0', 'original0'});
      cache.responses['preview0'] = filesystem.file('/refetched-preview')
        ..writeAsBytesSync(png);
      await tester.tap(find.byTooltip(hdTooltip));
      await flushImages(tester);
      expectImage(tester, 1);
      expect(cache.requested.last, 'preview0');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'HD can return to preview despite local original, downloads do not override choice',
    (tester) async {
      cache.files['original0'] = cache.responses['original0']!;
      await tester.pumpWidget(app(reader()));
      await flushImages(tester);
      expectImage(tester, 2);
      await tester.tap(find.byTooltip(hdTooltip));
      await flushImages(tester);
      expectImage(tester, 1);
      expect(currentProvider(tester).mode, ReadingImageMode.preview);
      final previewProvider = currentProvider(tester);
      await images.downloaded('original0', cache.responses['original0']!);
      await flushImages(tester);
      expect(currentProvider(tester), same(previewProvider));
      expectImage(tester, 1);
      await tester.tap(find.byTooltip(hdTooltip));
      await flushImages(tester);
      expectImage(tester, 2);
      await tester.tap(find.byTooltip(hdTooltip));
      await flushImages(tester);
      expectImage(tester, 1);
      await tester.longPress(find.byTooltip(hdTooltip));
      await flushImages(tester);
      expectImage(tester, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed replacement keeps displayed preview, background releases handoff',
    (tester) async {
      final lookup = Completer<String?>();
      var delayOriginal = false;
      images = ReadingImages(
        cache: cache,
        findSaved: (url, names) async =>
            delayOriginal && url == 'original0' ? await lookup.future : null,
        readSaved: (_) async => null,
      );
      await tester.pumpWidget(app(reader()));
      await flushImages(tester);
      final displayed = currentProvider(tester);
      cache.responses['original0'] = filesystem.file('/corrupt')
        ..writeAsBytesSync([1, 2]);
      cache.failRequests = true;
      await tester.tap(find.byTooltip(hdTooltip));
      await flushImages(tester);
      expectImage(tester, 1);
      expect(currentProvider(tester), same(displayed));
      cache.failRequests = false;
      delayOriginal = true;
      var handedOff = false;
      final handoff = images
          .downloaded('original0', cache.responses['original1']!)
          .then((_) => handedOff = true);
      await tester.pump();
      expect(handedOff, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await handoff;
      expect(handedOff, true);
      lookup.complete(null);
      await flushImages(tester);
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets('long press image opens download menu while staying in reader', (
    tester,
  ) async {
    await tester.pumpWidget(app(reader()));
    await flushImages(tester);
    await tester.longPress(find.byType(PhotoViewGallery));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(PhotoZoomPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AI button toggles shared setting both directions and persists', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Scaffold(body: AiVisibilityButton())));
    await tester.tap(find.byType(IconButton));
    await flushImages(tester);
    expect(muteStore.banAIIllust, true);
    expect(Prefer.getBool('ban_ai_illust'), true);
    await tester.tap(find.byType(IconButton));
    await flushImages(tester);
    expect(muteStore.banAIIllust, false);
    expect(Prefer.getBool('ban_ai_illust'), false);
    await tester.pumpWidget(const SizedBox());
  });
}
