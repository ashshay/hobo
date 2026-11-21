// 按「图片文件名」而不是完整 URL 检查 picsOf 是否产出重复。
//
// 同一张图可能来自不同 CDN 域名（wx1/wx3/ss1）或不同尺寸目录（orj360/large），
// 完整 URL 去重会漏掉它们，但文件名（pid）是唯一的。
//
// 跑法：dart run tool/check_duplicate_pics.dart
import 'dart:convert';
import 'dart:io';

import 'package:hobo/data/models.dart';

void main() {
  final dir = Directory('build/cache-dump/files/http-cache');
  if (!dir.existsSync()) {
    stderr.writeln('没有缓存目录');
    exitCode = 1;
    return;
  }

  var statuses = 0;
  var dupByUrl = 0;
  var dupByName = 0;
  final samples = <String>[];

  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final text = file.readAsStringSync();
    for (final match in RegExp(r'"mblog":\{').allMatches(text)) {
      final obj = _balancedObject(text, match.end - 1);
      if (obj == null) continue;
      Map<String, dynamic> map;
      try {
        map = jsonDecode(obj) as Map<String, dynamic>;
      } on Object {
        continue;
      }
      statuses++;
      final pics = picsOf(map);
      if (pics.length < 2) continue;

      final urls = pics.map((p) => p.large.isNotEmpty ? p.large : p.thumb).toList();
      final names = urls.map(_picName).toList();

      final urlDup = urls.length != urls.toSet().length;
      final nameDup = names.length != names.toSet().length;
      if (urlDup) dupByUrl++;
      if (nameDup) {
        dupByName++;
        if (samples.length < 6) {
          samples.add(
            'id=${map['id']}  ${urls.length} 张 / ${names.toSet().length} 唯一文件名\n'
            '${urls.map((u) => '    $u').join('\n')}',
          );
        }
      }
    }
  }

  stdout.writeln('检查 $statuses 条微博');
  stdout.writeln('  按完整 URL 重复: $dupByUrl');
  stdout.writeln('  按文件名重复:   $dupByName');
  for (final s in samples) {
    stdout.writeln('\n$s');
  }
  if (dupByName > 0) exitCode = 1;
}

/// 取图片文件名（不含目录与查询串），如 `0092j2IYgy1ij7ljfblb3j30j60tr7e4.jpg`。
String _picName(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  return path.split('/').last;
}

String? _balancedObject(String text, int start) {
  if (start >= text.length || text[start] != '{') return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}
