import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/ui/widgets/comment_tile.dart';
import 'package:hobo/ui/widgets/common.dart';

/// 一条带楼中楼预览的评论：块里几行长短不一，最容易出现「按内容收紧再居中」。
Comment _comment() => const Comment(
  id: 'c1',
  user: User(id: 'u1', name: '大名螳螂'),
  textHtml: '这波啊，最招笑的是湾湾那帮跟着民主党狗哨围剿老黄的水军。',
  createdAt: '2026-11-23 22:10:00',
  region: '福建',
  replyCount: 7,
  replies: [
    Comment(
      id: 'r1',
      user: User(id: 'u2', name: '刹那之夜'),
      textHtml: '这波啊，是一根筋两头堵啦！',
    ),
    Comment(
      id: 'r2',
      user: User(id: 'u3', name: '瓜哒老付'),
      textHtml: '天才！',
    ),
  ],
);

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(400, 800)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 400, child: child),
    ),
  ),
);

void main() {
  testWidgets('楼中楼预览块铺满正文宽度，文字统一从左边起排', (tester) async {
    await tester.pumpWidget(_host(CommentTile(comment: _comment())));
    await tester.pump();

    final card = tester.getRect(find.byType(HoboCard));
    final line = find.textContaining('一根筋两头堵');
    expect(line, findsOneWidget);

    // 卡片内边距 14 + 预览块内边距 10：文字盒的左边界就落在那里，
    // 而不是被居中到块中间。
    final rect = tester.getRect(line);
    expect(rect.left, closeTo(card.left + 14 + 10, 0.5));
    expect(rect.right, closeTo(card.right - 14 - 10, 0.5));

    // 盒子铺满 + 显式左对齐，短的一行也不会跑到中间。
    expect(tester.widget<Text>(line).textAlign, TextAlign.start);

    final short = find.textContaining('天才');
    expect(tester.getRect(short).left, closeTo(rect.left, 0.5));
  });

  testWidgets('非卡片式：不要卡片底，条目之间拉一条浅色分隔线', (tester) async {
    await tester.pumpWidget(
      _host(
        CommentTile(
          comment: _comment(),
          style: CommentStyle.flat,
          showDivider: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(HoboCard), findsNothing);
    expect(find.byKey(const ValueKey('comment-divider')), findsOneWidget);
    // 楼中楼仍是块状预览，标题行照 Bifu 的「昵称：正文」。
    expect(find.textContaining('查看全部 7 条回复'), findsOneWidget);
    expect(find.textContaining('一根筋两头堵'), findsOneWidget);
    // 时间/来源落在正文右下那一行。
    expect(find.textContaining('福建'), findsOneWidget);
  });

  testWidgets('非卡片式最后一条不画分隔线', (tester) async {
    await tester.pumpWidget(
      _host(CommentTile(comment: _comment(), style: CommentStyle.flat)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('comment-divider')), findsNothing);
  });

  testWidgets('卡片式默认不带分隔线', (tester) async {
    await tester.pumpWidget(_host(CommentTile(comment: _comment())));
    await tester.pump();

    expect(find.byType(HoboCard), findsOneWidget);
    expect(find.byKey(const ValueKey('comment-divider')), findsNothing);
  });
}
