import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/follow_tags.dart';
import 'package:hobo/data/repo.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/data/store.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/pages/login_page.dart';
import 'package:hobo/ui/theme.dart';
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
    tmp = Directory.systemTemp.createTempSync('hobo_login_test_');
    settings = Settings(prefs);
    store = await Store.open(tmp);
    tags = FollowTags(store);
    repo = Repo(store: store, settings: settings, followTags: tags);
  });

  tearDown(() {
    repo.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('登录页 WebView 严格让出顶栏与底栏，不遮挡切换登录方式', (tester) async {
    const webKey = Key('login-web-slot');
    const topPadding = 36.0;
    const bottomPadding = 24.0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          Provider.value(value: store),
          ChangeNotifierProvider.value(value: tags),
          ChangeNotifierProvider.value(value: repo),
        ],
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          ),
          child: PrismApp(
            theme: hoboTheme(brightness: Brightness.light, accentArgb: 0),
            localizationsDelegates: HoboUiLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            locale: const Locale('zh', 'CN'),
            builder: (context, inner) => ViewScope(
              size: const Size(393, 852),
              isMobile: true,
              child: inner ?? const SizedBox.shrink(),
            ),
            home: LoginPage(
              webSlotBuilder: (_) => const SizedBox.expand(key: webKey),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final webRect = tester.getRect(find.byKey(webKey));
    final cookieBtnRect = tester.getRect(find.text('粘贴 Cookie'));

    // 顶部必须让出 状态栏 + 顶栏 高度，确保网页顶部切换登录方式可见可点。
    expect(
      webRect.top,
      greaterThanOrEqualTo(topPadding + pageToolbarHeight - 0.5),
    );
    // 底部不能被「粘贴 Cookie / 纯本地浏览」遮挡。
    expect(webRect.bottom, lessThanOrEqualTo(cookieBtnRect.top));
    expect(webRect.height, greaterThan(400));
  });
}
