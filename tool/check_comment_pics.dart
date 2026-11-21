// 用真实接口数据验证评论配图解析。
//
// 跑法（需要登录态 cookie，从模拟器里取）：
//   dart run tool/check_comment_pics.dart
//
// 不联网也能跑：把 hotflow 的 JSON 存成 build/hotflow-raw.json 就会直接读本地文件。
import 'dart:convert';
import 'dart:io';

import 'package:hobo/data/models.dart';

const _statusIds = ['5367002429655439', '5367486239474184'];

Future<void> main(List<String> args) async {
  final cookie = _readCookie();
  var checked = 0;
  var withPic = 0;

  for (final id in _statusIds) {
    final raw = await _fetch(id, cookie);
    if (raw == null) {
      stderr.writeln('$id: 拿不到数据，跳过');
      continue;
    }
    final decoded = jsonDecode(raw);
    final data = (decoded as Map)['data'];
    final list = data is Map ? data['data'] : null;
    if (list is! List) {
      stderr.writeln('$id: 结构不对，跳过');
      continue;
    }
    for (final item in list) {
      if (item is! Map) continue;
      final comment = Comment.from({
        for (final e in item.entries) e.key.toString(): e.value,
      });
      if (comment == null) continue;
      checked++;
      if (comment.pics.isEmpty) continue;
      withPic++;
      final pic = comment.pics.first;
      final placeholder = pic.thumb.contains('&690') || pic.large.contains('&690');
      stdout.writeln(
        '${placeholder ? '✗ 仍是占位' : '✓'} 评论 ${comment.id}  '
        '${comment.pics.length} 张  thumb=${pic.thumb}',
      );
    }
  }

  stdout.writeln('\n共解析 $checked 条评论，其中 $withPic 条带图。');
  if (withPic == 0) {
    stderr.writeln('没有带图评论可验证。');
    exitCode = 1;
  }
}

String? _readCookie() {
  final file = File('build/cookie.txt');
  if (!file.existsSync()) return null;
  return file.readAsStringSync().trim();
}

Future<String?> _fetch(String id, String? cookie) async {
  final local = File('build/hotflow-$id.json');
  if (local.existsSync()) return local.readAsStringSync();

  final client = HttpClient();
  try {
    final uri = Uri.parse(
      'https://m.weibo.cn/comments/hotflow?id=$id&mid=$id&max_id_type=0',
    );
    final request = await client.getUrl(uri);
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Linux; Android 13; MI 9) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    );
    request.headers.set('Referer', 'https://m.weibo.cn/');
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    request.headers.set('MWeibo-Pwa', '1');
    if (cookie != null && cookie.isNotEmpty) {
      request.headers.set('Cookie', cookie);
    }
    final response = await request.close();
    if (response.statusCode != 200) return null;
    return await response.transform(utf8.decoder).join();
  } on Object catch (e) {
    stderr.writeln('$id: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}
