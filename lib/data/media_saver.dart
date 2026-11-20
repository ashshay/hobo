/// 保存图片 / 视频到系统相册。
///
/// 落盘走原生 `hobo/media` 通道写 MediaStore：Android 10+ 不需要任何权限，
/// 更老的系统在第一次保存时申请一次存储权限。Dart 这边只负责把文件下下来。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

class MediaSaver {
  MediaSaver._();

  static const _channel = MethodChannel('hobo/media');

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
  static const _videoExts = {'mp4', 'm4v', 'mov', 'webm'};

  /// 下载并保存一张图片，返回相册里的地址。
  static Future<String> saveImage(
    String url, {
    String? cookie,
    String referer = 'https://m.weibo.cn/',
  }) async {
    final bytes = await Api.downloadBytes(
      url,
      cookie: cookie,
      referer: referer,
    );
    if (bytes.isEmpty) throw ApiException('图片内容为空');
    final saved = await _channel.invokeMethod<String>('saveImage', {
      'bytes': Uint8List.fromList(bytes),
      'name': _fileName(url, _imageExts, 'jpg'),
    });
    return saved ?? '';
  }

  /// 下载并保存一段视频，返回相册里的地址。
  static Future<String> saveVideo(
    String url, {
    String? cookie,
    String referer = 'https://m.weibo.cn/',
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'hobo_${DateTime.now().millisecondsSinceEpoch}.mp4',
      ),
    );
    try {
      final size = await Api.downloadToFile(
        url,
        file,
        cookie: cookie,
        referer: referer,
        onProgress: onProgress,
      );
      if (size <= 0) throw ApiException('视频内容为空');
      final saved = await _channel.invokeMethod<String>('saveVideo', {
        'path': file.path,
        'name': _fileName(url, _videoExts, 'mp4'),
        'mime': 'video/mp4',
      });
      return saved ?? '';
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  static String _fileName(String url, Set<String> allowed, String fallback) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final safe = allowed.contains(ext) ? ext : fallback;
    return 'hobo_${DateTime.now().millisecondsSinceEpoch}.$safe';
  }
}
