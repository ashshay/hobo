import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/theme.dart';
import 'package:hobo/ui/widgets/status_card.dart';
import 'package:prism_ui/prism_ui.dart';

Widget _host(Widget child) {
  return PrismApp(
    theme: hoboTheme(brightness: Brightness.light, accentArgb: 0),
    localizationsDelegates: HoboUiLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    builder: (context, inner) => ViewScope(
      size: MediaQuery.sizeOf(context),
      isMobile: true,
      child: inner ?? const SizedBox.shrink(),
    ),
    home: child,
  );
}

void main() {
  testWidgets('转发块里的 @ 链接优先于整块点击', (tester) async {
    String? linked;
    var openedQuoted = false;
    const quoted = Status(
      id: '2001',
      mid: '2001',
      textHtml:
          '//<a href="https://m.weibo.cn/n/%E5%B0%8F%E6%98%8E">@小明</a> 你好',
      createdAt: '',
      source: '',
      user: User(id: '2002', name: '原博主'),
    );
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 360,
            child: RetweetBlock(
              status: quoted,
              onOpen: () => openedQuoted = true,
              onLink: (url) => linked = url,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('@小明'));
    await tester.pumpAndSettle();
    expect(linked, contains('/n/'));
    expect(openedQuoted, isFalse);
  });

  testWidgets('转发块顶部的 @原作者 打开个人主页', (tester) async {
    User? openedUser;
    const quoted = Status(
      id: '2001',
      mid: '2001',
      textHtml: '正文',
      createdAt: '',
      source: '',
      user: User(id: '2002', name: '原博主'),
    );
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 360,
            child: RetweetBlock(
              status: quoted,
              onOpen: () {},
              onUser: (user) => openedUser = user,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('@原博主'));
    await tester.pumpAndSettle();
    expect(openedUser?.id, '2002');
  });
}
