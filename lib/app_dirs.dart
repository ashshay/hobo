import 'dart:io';

import 'package:path_provider/path_provider.dart';

Directory? _cached;

/// App 私有目录（Android 上是 `/data/data/com.hobo.app/files`）。
/// 会话、草稿、历史、收藏、HTTP 缓存都放在这里。
Future<Directory> appDataDir() async {
  final existing = _cached;
  if (existing != null) return existing;
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  _cached = dir;
  return dir;
}

Future<File> appDataFile(String name) async =>
    File('${(await appDataDir()).path}/$name');
