// 用真实接口数据渲染评论配图，确认 UI 层拿到的是能加载的地址。
//
// 跑法：
//   flutter test test/comment_pics_render_test.dart
//
// 数据来自 build/hotflow-*.json（由 tool/check_comment_pics.dart 同一套抓取脚本落盘）。
// 这里不联网：只验证「解析 → PicGrid 拿到的 URL」这一段，图片本身由 RemoteImage 负责。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';

void main() {
  test('真实 hotflow 数据里的图片评论解析出可加载的地址', () {
    final files = Directory('build')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('hotflow-') && f.path.endsWith('.json'))
        .toList();
    expect(files, isNotEmpty, reason: '先跑 tool/check_comment_pics.dart 抓数据');

    var withPics = 0;
    for (final file in files) {
      final decoded = jsonDecode(file.readAsStringSync());
      final data = (decoded as Map)['data'];
      final list = data is Map ? data['data'] : null;
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final comment = Comment.from({
          for (final e in item.entries) e.key.toString(): e.value,
        });
        if (comment == null || comment.pics.isEmpty) continue;
        withPics++;
        for (final pic in comment.pics) {
          // 占位串 `&690` 请求必 404，绝不能出现在渲染地址里。
          expect(pic.thumb, isNot(contains('&690')));
          expect(pic.large, isNot(contains('&690')));
          expect(pic.thumb, contains('sinaimg.cn'));
          expect(pic.large, contains('/large/'));
        }
      }
    }
    expect(withPics, greaterThan(0), reason: '样本里应该有带图评论');
  });
}
