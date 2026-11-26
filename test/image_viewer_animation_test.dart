import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/follow_tags.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/data/repo.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/data/store.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/pages/image_viewer_page.dart';
import 'package:hobo/ui/routes.dart';
import 'package:hobo/ui/theme.dart';
import 'package:hobo/ui/widgets/status_card.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  late Settings settings;
  late Store store;
  late FollowTags tags;
  late Repo repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tmp = Directory.systemTemp.createTempSync('hobo_viewer_test_');
    settings = Settings(prefs);
    store = await Store.open(tmp);
    tags = FollowTags(store);
    repo = Repo(store: store, settings: settings, followTags: tags);
  });

  tearDown(() {
    repo.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('同一张图在主贴与转发块里分配互不冲突的 Hero tag', () {
    const pic = Pic(
      thumb: 'https://wx1.sinaimg.cn/orj360/same.jpg',
      large: 'https://wx1.sinaimg.cn/large/same.jpg',
    );
    final a = pic.withHeroTag('s:100#0:${picHeroTag(pic)}');
    final b = pic.withHeroTag('rt:100:200#0:${picHeroTag(pic)}');
    expect(picHeroTag(a), isNot(equals(picHeroTag(b))));
    expect(picHeroTag(pic), 'hobo-pic:https://wx1.sinaimg.cn/orj360/same.jpg');
  });

  testWidgets('看图页走半透明路由展开，支持垂直下拉关闭与短拉回弹', (tester) async {
    const pics = [
      Pic(thumb: '', large: '', width: 800, height: 600, heroTag: 'test-pic-0'),
    ];
    final route = ImageViewerRoute(pics: pics, initialIndex: 0);
    expect(route.opaque, isFalse);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          Provider.value(value: store),
          ChangeNotifierProvider.value(value: tags),
          ChangeNotifierProvider.value(value: repo),
        ],
        child: PrismApp(
          theme: hoboTheme(brightness: Brightness.dark, accentArgb: 0),
          localizationsDelegates: HoboUiLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          locale: const Locale('zh', 'CN'),
          builder: (context, inner) => ViewScope(
            size: MediaQuery.sizeOf(context),
            isMobile: true,
            child: inner ?? const SizedBox.shrink(),
          ),
          home: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => openImages(context, pics: pics),
                child: const Text('打开看图'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 打开看图页
    await tester.tap(find.text('打开看图'));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);

    // 短距离下拉应回弹，不关闭看图页
    await tester.drag(find.byType(ImageViewerPage), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);

    // 超过阈值下拉直接收起关闭
    await tester.drag(find.byType(ImageViewerPage), const Offset(0, 220));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsNothing);
    expect(find.text('打开看图'), findsOneWidget);
  });
}
