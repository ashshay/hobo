import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/html_text.dart';
import 'package:hobo/data/links.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/theme.dart';
import 'package:hobo/ui/widgets/status_card.dart';
import 'package:hobo/ui/widgets/weibo_text.dart';
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
  test('微博真实单引号转发链与纯文本 @ 都解析为可点链接，邮箱不误判', () {
    const raw =
        "转发评论//<a href='/n/道法只渡有缘人'>@道法只渡有缘人</a>:内容"
        "//<a href='/n/Miss桃碧·'>@Miss桃碧·</a>:测试"
        "//@纯文本用户:hello user@example.com";
    final links = parseWeiboHtml(raw).whereType<WeiboLinkSegment>().toList();
    expect(links.length, 3);
    expect(links[0].text, '@道法只渡有缘人');
    expect(links[0].url, '/n/道法只渡有缘人');
    expect(weiboMentionName(resolveWeiboLink(links[0].url)!), '道法只渡有缘人');
    expect(links[1].text, '@Miss桃碧·');
    expect(links[1].url, '/n/Miss桃碧·');
    expect(weiboMentionName(resolveWeiboLink(links[1].url)!), 'Miss桃碧·');
    expect(links[2].text, '@纯文本用户');
    expect(links[2].url, '/n/纯文本用户');
    expect(weiboMentionName(resolveWeiboLink(links[2].url)!), '纯文本用户');

    expect(
      resolveWeiboLink('sinaweibo://userinfo?uid=123456'),
      'https://m.weibo.cn/u/123456',
    );
    expect(
      weiboMentionName(
        resolveWeiboLink('sinaweibo://userinfo?nick=%E5%B0%8F%E6%98%8E')!,
      ),
      '小明',
    );
  });

  testWidgets('主卡片转发链里的单引号 @ 链接优先于整卡跳转详情', (tester) async {
    String? linked;
    var openedStatus = false;
    const status = Status(
      id: '3001',
      mid: '3001',
      textHtml:
          "说的对//<a href='/n/道法只渡有缘人'>@道法只渡有缘人</a>:原评论"
          "//<a href='/n/紫瑜Mia'>@紫瑜Mia</a>:赞同",
      createdAt: '',
      source: '',
      user: User(id: '3002', name: '转发者'),
    );
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 360,
            child: StatusCard(
              status: status,
              showActions: false,
              onOpen: () => openedStatus = true,
              onLink: (url) => linked = url,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('@道法只渡有缘人'));
    await tester.pumpAndSettle();
    expect(linked, '/n/道法只渡有缘人');
    expect(openedStatus, isFalse);

    linked = null;
    await tester.tapOnText(find.textRange.ofSubstring('@紫瑜Mia'));
    await tester.pumpAndSettle();
    expect(linked, '/n/紫瑜Mia');
    expect(openedStatus, isFalse);
  });

  testWidgets('转发块里的单引号与双引号 @ 链接优先于整块点击', (tester) async {
    String? linked;
    var openedQuoted = false;
    const quoted = Status(
      id: '2001',
      mid: '2001',
      textHtml:
          "//<a href='/n/小明'>@小明</a> 你好 //<a href=\"https://m.weibo.cn/n/%E5%B0%8F%E7%BA%A2\">@小红</a>",
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
    expect(linked, '/n/小明');
    expect(openedQuoted, isFalse);

    linked = null;
    await tester.tapOnText(find.textRange.ofSubstring('@小红'));
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

  testWidgets('WeiboText 从不可点切换为可点时自动重建点击识别器', (tester) async {
    String? linked;
    const html = "//<a href='/n/小王'>@小王</a>:来了";
    await tester.pumpWidget(_host(const Center(child: WeiboText(html: html))));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(
        Center(
          child: WeiboText(html: html, onLink: (url) => linked = url),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('@小王'));
    await tester.pumpAndSettle();
    expect(linked, '/n/小王');
  });
}
