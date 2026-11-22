// 消息中心四类通知的解析，用真实接口返回的样本钉住字段。
//
// 样本取自 `GET https://m.weibo.cn/message/{mentionsAt,mentionsCmt,cmt,attitude}?page=N`
// （每条各留一项），放在 test/fixtures/，跑测试不联网。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/json.dart';
import 'package:hobo/data/models.dart';

Map<String, dynamic> _fixture(String name) {
  final raw = File('test/fixtures/$name').readAsStringSync();
  final decoded = jsonDecode(raw) as Map;
  return {for (final e in decoded.entries) e.key.toString(): e.value};
}

Map<String, dynamic> _firstItem(String name) {
  final arr = _fixture(name).arr('data');
  expect(arr, isNotNull, reason: '$name 的 data 应该是数组');
  final item = jObj(arr!.first);
  expect(item, isNotNull);
  return item!;
}

void main() {
  test('@我的微博：每条就是一条完整微博', () {
    final status = Status.from(_firstItem('notice_at_me.json'));
    expect(status, isNotNull);
    expect(status!.id, isNotEmpty);
    expect(status.textHtml, isNotEmpty);
    expect(status.plainText, isNot(contains('<a ')), reason: '纯文本里不该留标签');
    expect(status.user?.name, isNotEmpty);
    expect(status.user?.id, isNotEmpty);
  });

  test('收到的评论：带出评论正文和被评论的那条微博', () {
    final comment = Comment.from(
      _firstItem('notice_comment.json'),
      withStatus: true,
    );
    expect(comment, isNotNull);
    expect(comment!.id, isNotEmpty);
    expect(comment.user?.name, isNotEmpty);
    expect(comment.plainText, isNotEmpty);
    expect(comment.status, isNotNull, reason: '通知卡片要显示被评论的微博');
    expect(comment.status!.plainText, isNotEmpty);
    expect(comment.status!.id, isNotEmpty);
  });

  test('收到的赞：带出点赞人和被赞的微博', () {
    final notice = LikeNotice.from(_firstItem('notice_like.json'));
    expect(notice, isNotNull);
    expect(notice!.id, isNotEmpty);
    expect(notice.user?.name, isNotEmpty);
    expect(notice.status, isNotNull);
    expect(notice.status!.plainText, isNotEmpty);
    expect(notice.createdAt, isNotEmpty);
  });

  test('翻到底：data 是 false，不当作空数组', () {
    final root = _fixture('notice_end.json');
    expect(root.intOf('ok'), 1);
    // Repo 就是按「不是数组」判定到底的，别改成判长度。
    expect(root.arr('data'), isNull);
    expect(root.opt('data'), isFalse);
  });
}
