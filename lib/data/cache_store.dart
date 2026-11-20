/// GET 响应的磁盘缓存。
///
/// 时间线允许过期：进页面先铺上次的内容，只有下拉刷新或显式 reload 才回源。
/// 键里带会话 cookie，多账号之间不会串页。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../app_dirs.dart';

class CacheStore {
  CacheStore._(this._dir);

  static CacheStore? _instance;

  static Future<CacheStore> instance() async {
    final existing = _instance;
    if (existing != null) return existing;
    final root = await appDataDir();
    final store = CacheStore._(Directory(p.join(root.path, 'http-cache')));
    await store._dir.create(recursive: true);
    _instance = store;
    return store;
  }

  final Directory _dir;
  static const _maxBytes = 16 * 1024 * 1024;

  String key(String url, String? cookie) =>
      sha256.convert(utf8.encode('${cookie ?? ''}\n$url')).toString();

  Map<String, dynamic>? read(String url, String? cookie) {
    final file = File(p.join(_dir.path, '${key(url, cookie)}.json'));
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return {for (final e in decoded.entries) e.key.toString(): e.value};
      }
    } on Object {
      // 缓存坏了就当没有。
    }
    return null;
  }

  void write(String url, String? cookie, Map<String, dynamic> json) {
    try {
      File(p.join(_dir.path, '${key(url, cookie)}.json'))
          .writeAsStringSync(jsonEncode(json));
      _trim();
    } on Object {
      // 磁盘写失败不影响本次请求。
    }
  }

  void invalidate(String url, String? cookie) {
    try {
      final file = File(p.join(_dir.path, '${key(url, cookie)}.json'));
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // 同上。
    }
  }

  void clear() {
    try {
      for (final entity in _dir.listSync()) {
        if (entity is File) entity.deleteSync();
      }
    } on Object {
      // 同上。
    }
  }

  void _trim() {
    final files = _dir.listSync().whereType<File>().toList();
    var total = 0;
    for (final file in files) {
      total += file.lengthSync();
    }
    if (total <= _maxBytes) return;
    files.sort(
      (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
    );
    for (final file in files) {
      if (total <= _maxBytes) break;
      total -= file.lengthSync();
      file.deleteSync();
    }
  }
}
