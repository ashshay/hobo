import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/routes.dart';
import 'package:hobo/ui/theme.dart';
import 'package:hobo/ui/widgets/comment_tile.dart';
import 'package:hobo/ui/widgets/copy_dialog.dart';
import 'package:prism_ui/prism_ui.dart';

/// 弹窗走 prism_ui 的浮动对话框路由，需要 App 里那套本地化委托。
Widget _host(String text) => PrismApp(
  theme: hoboTheme(brightness: Brightness.light, accentArgb: 0),
  localizationsDelegates: HoboUiLocalizations.delegates,
  supportedLocales: const [Locale('zh', 'CN')],
  locale: const Locale('zh', 'CN'),
  builder: (context, inner) => ViewScope(
    size: MediaQuery.sizeOf(context),
    isMobile: true,
    child: inner ?? const SizedBox.shrink(),
  ),
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () => showHoboCopyDialog(context, text),
      child: const Text('open'),
    ),
  ),
);

Future<void> _open(WidgetTester tester, String text) async {
  await tester.pumpWidget(_host(text));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 评论卡片只要一条能长按的正文，不涉及主题与 Provider。
Widget _tileHost(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(400, 800)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 400, child: child),
    ),
  ),
);

const _comment = Comment(
  id: 'c1',
  user: User(id: 'u1', name: '大名螳螂'),
  textHtml: '这波啊，最招笑的是跟着狗哨围剿的水军。',
);

void main() {
  testWidgets('复制面板先摆全文，点「复制全部」才写进剪贴板', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _open(tester, '第一行\n第二行');

    // 面板打开时还没动剪贴板，用户先看到全文再决定复制什么。
    expect(find.textContaining('长按正文选中一段'), findsOneWidget);
    expect(find.text('第一行\n第二行'), findsOneWidget);
    expect(calls.where((c) => c.method == 'Clipboard.setData'), isEmpty);

    await tester.tap(find.text('复制全部'));
    await tester.pumpAndSettle();

    final writes = calls.where((c) => c.method == 'Clipboard.setData').toList();
    expect(writes, hasLength(1));
    expect((writes.single.arguments as Map)['text'], '第一行\n第二行');
    // 复制完面板自动关闭。
    expect(find.text('复制全部'), findsNothing);
  });

  testWidgets('空内容不弹面板', (tester) async {
    await _open(tester, '   ');

    expect(find.text('复制全部'), findsNothing);
  });

  testWidgets('面板里长按正文可以框选', (tester) async {
    await _open(tester, '第一行 第二行 第三行');

    await tester.longPress(find.text('第一行 第二行 第三行'));
    await tester.pumpAndSettle();

    expect(find.byType(TextSelectionMenu), findsOneWidget);
  });

  group('评论长按进复制入口', () {
    testWidgets('卡片式评论长按触发 onLongPress', (tester) async {
      var longPresses = 0;
      await tester.pumpWidget(
        _tileHost(
          CommentTile(comment: _comment, onLongPress: () => longPresses++),
        ),
      );
      await tester.pump();

      await tester.longPress(find.textContaining('跟着狗哨围剿的水军'));
      await tester.pumpAndSettle();

      expect(longPresses, 1);
    });

    testWidgets('融合式评论长按同样触发 onLongPress', (tester) async {
      var longPresses = 0;
      await tester.pumpWidget(
        _tileHost(
          CommentTile(
            comment: _comment,
            style: CommentStyle.merged,
            onLongPress: () => longPresses++,
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.textContaining('跟着狗哨围剿的水军'));
      await tester.pumpAndSettle();

      expect(longPresses, 1);
    });
  });

  group('正文复制文本', () {
    test('纯正文原样复制', () {
      const status = Status(
        id: 's1',
        mid: 'm1',
        textHtml: '<p>今天的风好大</p>',
        createdAt: '2026-11-28 12:00:00',
        source: '来自 iPhone客户端',
      );
      expect(statusCopyText(status), '今天的风好大');
    });

    test('转发微博把原文按 //@ 拼在后面', () {
      const status = Status(
        id: 's2',
        mid: 'm2',
        textHtml: '<p>转发理由</p>',
        createdAt: '2026-11-28 12:00:00',
        source: '来自 iPhone客户端',
        retweeted: Status(
          id: 's0',
          mid: 'm0',
          textHtml: '<p>原文内容</p>',
          createdAt: '2026-11-27 09:00:00',
          source: '来自 微博网页版',
          user: User(id: 'u2', name: '原作者'),
        ),
      );
      expect(statusCopyText(status), '转发理由\n\n//@原作者：原文内容');
    });
  });
}
