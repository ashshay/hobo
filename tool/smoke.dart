/// 纯 Dart 冒烟脚本：不经过 Flutter，直接用 dio 打微博接口，验证数据层解析。
///
/// 用法：
///   dart run tool/smoke.dart                 # 先领访客身份，看公开时间线
///   dart run tool/smoke.dart "<cookie>"      # 用自己的 Cookie 看关注流与私信
///   HOBO_COOKIE="<cookie>" dart run tool/smoke.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../lib/data/json.dart';
import '../lib/data/models.dart';

const _ua =
    'Mozilla/5.0 (Linux; Android 13; MI 9) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

late final Dio dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    validateStatus: (_) => true,
    responseType: ResponseType.plain,
  ),
);

Map<String, String> headers(String? cookie, {String? st}) => {
  'User-Agent': _ua,
  'Accept': 'application/json',
  'Referer': 'https://m.weibo.cn/',
  'X-Requested-With': 'XMLHttpRequest',
  'MWeibo-Pwa': '1',
  if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
  if (st != null && st.isNotEmpty) 'X-XSRF-TOKEN': st,
};

Future<Map<String, dynamic>> fetch(String url, {String? cookie}) async {
  final response = await dio.get<dynamic>(url, options: Options(headers: headers(cookie)));
  final text = response.data?.toString() ?? '';
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}: $text');
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map) throw StateError('不是 JSON 对象');
  return {for (final e in decoded.entries) e.key.toString(): e.value};
}

/// m.weibo.cn 的只读接口不带 cookie 一律 432，先领一个访客身份。
Future<String> genVisitor() async {
  final response = await dio.post<dynamic>(
    'https://visitor.passport.weibo.cn/visitor/genvisitor2',
    data: {'cb': 'visitor_gray_callback', 'tid': '', 'from': 'weibo'},
    options: Options(
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://m.weibo.cn/',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    ),
  );
  final text = response.data?.toString() ?? '';
  final open = text.indexOf('(');
  final close = text.lastIndexOf(')');
  final decoded = jsonDecode(
    open >= 0 && close > open ? text.substring(open + 1, close) : text,
  );
  final data = (decoded as Map)['data'] as Map?;
  final sub = data?['sub']?.toString() ?? '';
  if (sub.isEmpty) throw StateError('领访客身份失败：$text');
  final subp = data?['subp']?.toString() ?? '';
  return subp.isEmpty ? 'SUB=$sub' : 'SUB=$sub; SUBP=$subp';
}

String short(String text, [int max = 60]) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

Future<void> main(List<String> args) async {
  final envCookie = Platform.environment['HOBO_COOKIE'];
  var cookie = args.isNotEmpty ? args.first : envCookie;
  if (cookie == null || cookie.isEmpty) {
    stdout.writeln('· 没有提供 Cookie，领取访客身份…');
    cookie = await genVisitor();
    stdout.writeln('  访客 Cookie: ${cookie.split(';').first}');
  }

  stdout.writeln('\n[1/4] 推荐流 102803');
  final feed = parseCards(
    await fetch(
      'https://m.weibo.cn/api/container/getIndex?containerid=102803',
      cookie: cookie,
    ),
  );
  stdout.writeln('  本页 ${feed.items.length} 条，下一页游标 ${feed.sinceId ?? '（到底）'}');
  for (final status in feed.items.take(3)) {
    stdout.writeln(
      '  · ${status.user?.name ?? '?'} '
      '${formatWeiboTime(status.createdAt)} '
      '图${status.pics.length} '
      '转${status.reposts} 评${status.comments} 赞${status.attitudes}',
    );
    stdout.writeln('    ${short(status.plainText)}');
  }
  if (feed.items.isEmpty) return;

  final first = feed.items.first;
  stdout.writeln('\n[2/4] 详情 ${first.id}');
  final detail = Status.from(
    (await fetch(
      'https://m.weibo.cn/statuses/show?id=${first.id}',
      cookie: cookie,
    )).obj('data'),
  );
  stdout.writeln(
    detail == null
        ? '  详情解析失败'
        : '  ${detail.user?.name}：${short(detail.plainText, 80)}',
  );

  stdout.writeln('\n[3/4] 热门评论');
  final comments = await fetch(
    'https://m.weibo.cn/comments/hotflow?id=${first.id}&mid=${first.mid}&max_id_type=0',
    cookie: cookie,
  );
  final page = comments.obj('data');
  final items = page?.arr('data') ?? const [];
  stdout.writeln('  拿到 ${items.length} 条，max_id=${page?.str('max_id')}');
  for (final raw in items.take(3)) {
    final comment = Comment.from(jObj(raw));
    if (comment == null) continue;
    stdout.writeln('  · ${comment.user?.name}：${short(comment.plainText)}');
  }

  stdout.writeln('\n[4/4] 热搜榜');
  final hot = parseHotItems(
    await fetch(
      'https://m.weibo.cn/api/container/getIndex'
      '?containerid=106003type%3D25%26t%3D3%26disable_hot%3D1%26filter_type%3Drealtimehot',
      cookie: cookie,
    ),
  );
  for (final item in hot.take(5)) {
    stdout.writeln('  ${item.rank}. ${item.title} ${item.label}');
  }
  stdout.writeln('\nOK');
}
