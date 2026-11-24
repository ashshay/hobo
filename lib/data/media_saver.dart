/// 保存图片 / 实况图 / 视频到系统相册，并缓存实况短视频供看图页播放。
///
/// 落盘走原生 `hobo/media` 通道写 MediaStore：Android 10+ 不需要任何权限，
/// 更老的系统在第一次保存时申请一次存储权限。Dart 这边只负责把文件下下来。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

class MediaSaver {
  MediaSaver._();

  static const _channel = MethodChannel('hobo/media');

  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
  static const _videoExts = {'mp4', 'm4v', 'mov', 'webm'};

  /// 同一条实况视频并发下载时复用同一个 Future，避免重复落盘。
  static final Map<String, Future<File>> _liveDownloads = {};

  /// 下载并保存一张静图，返回相册里的地址。
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

  /// 下载并缓存实况图附带的短视频到本地临时目录，用于看图页即时播放与相册封装。
  ///
  /// 微博实况播放页会 302 跳到签名 mov，个别情况下 `m.weibo.cn` Referer 会被拒或
  /// 返回 HTML 报错页；这里会依次尝试 `m.weibo.cn`、`weibo.com` 以及解包后的直链，
  /// 并校验文件头确实是 ISO BMFF / QuickTime 容器。
  static Future<File> cacheLiveVideo(
    String url, {
    String? cookie,
    bool force = false,
  }) async {
    final target = url.trim();
    if (target.isEmpty) throw ApiException('实况视频地址为空');
    final dir = await _liveCacheDir();
    final hash = sha256.convert(utf8.encode(target)).toString();
    final dest = File(p.join(dir.path, '$hash.mov'));
    if (!force && dest.existsSync() && isValidVideoContainer(dest)) {
      return dest;
    }
    if (force && dest.existsSync()) {
      try {
        dest.deleteSync();
      } on Object {
        // 删除旧缓存失败仍会通过覆盖改名更新。
      }
    }
    final existing = _liveDownloads[target];
    if (existing != null) return existing;

    final future = _downloadLiveVideo(target, dest, cookie: cookie);
    _liveDownloads[target] = future;
    try {
      return await future;
    } finally {
      if (identical(_liveDownloads[target], future)) {
        _liveDownloads.remove(target);
      }
    }
  }

  /// 下载并保存一张实况图（Android Motion Photo：JPEG + XMP + MP4）到系统相册。
  static Future<String> saveLivePhoto({
    required String imageUrl,
    required String liveUrl,
    String? cookie,
    File? cachedVideo,
  }) async {
    if (imageUrl.isEmpty) throw ApiException('图片地址为空');
    if (liveUrl.isEmpty) throw ApiException('实况视频地址为空');
    final results = await Future.wait<Object>([
      Api.downloadBytes(imageUrl, cookie: cookie),
      cachedVideo != null &&
              cachedVideo.existsSync() &&
              isValidVideoContainer(cachedVideo)
          ? Future<File>.value(cachedVideo)
          : cacheLiveVideo(liveUrl, cookie: cookie),
    ]);
    final imageBytes = results[0] as List<int>;
    final videoFile = results[1] as File;
    if (imageBytes.isEmpty) throw ApiException('图片内容为空');
    final saved = await _channel.invokeMethod<String>('saveLivePhoto', {
      'imageBytes': Uint8List.fromList(imageBytes),
      'videoPath': videoFile.path,
      'name': 'MVIMG_${DateTime.now().millisecondsSinceEpoch}.jpg',
    });
    return saved ?? '';
  }

  /// 仅保存实况图里的短视频到系统相册（原生侧会自动把 `.mov` 无损转封装为 `.mp4`）。
  static Future<String> saveLiveVideo(
    String liveUrl, {
    String? cookie,
    File? cachedVideo,
  }) async {
    final videoFile = cachedVideo != null &&
            cachedVideo.existsSync() &&
            isValidVideoContainer(cachedVideo)
        ? cachedVideo
        : await cacheLiveVideo(liveUrl, cookie: cookie);
    final saved = await _channel.invokeMethod<String>('saveVideo', {
      'path': videoFile.path,
      'name': 'hobo_live_${DateTime.now().millisecondsSinceEpoch}.mov',
      'mime': 'video/quicktime',
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

  /// 判断已下载文件头是否为有效 MP4 / QuickTime MOV 容器（避免把 200 HTML 报错页当视频）。
  static bool isValidVideoContainer(File file) {
    try {
      if (!file.existsSync() || file.lengthSync() < 16) return false;
      final raf = file.openSync();
      try {
        final header = raf.readSync(12);
        return isValidVideoHeaderBytes(header);
      } finally {
        raf.closeSync();
      }
    } on Object {
      return false;
    }
  }

  /// 校验前 12 字节是否为 ISO BMFF / QuickTime 盒头（`ftyp` / `moov` / `mdat` / `free` / `wide` / `skip`）。
  static bool isValidVideoHeaderBytes(List<int> header) {
    if (header.length < 8) return false;
    final box = String.fromCharCodes(header.sublist(4, 8));
    return box == 'ftyp' ||
        box == 'moov' ||
        box == 'mdat' ||
        box == 'free' ||
        box == 'wide' ||
        box == 'skip';
  }

  /// 从 `video.weibo.com/media/play?livephoto=...` 解出内部原始地址（回退用）。
  static String? unwrapLivePhotoParam(String url) {
    final uri = Uri.tryParse(url);
    final inner = uri?.queryParameters['livephoto']?.trim() ?? '';
    if (inner.isEmpty) return null;
    if (inner.startsWith('//')) return 'https:$inner';
    if (inner.startsWith('http://') || inner.startsWith('https://')) {
      return inner;
    }
    return null;
  }

  static Future<Directory> _liveCacheDir() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'hobo_live'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> _downloadLiveVideo(
    String target,
    File dest, {
    String? cookie,
  }) async {
    final attempts = <(String url, String referer)>[
      (target, 'https://m.weibo.cn/'),
      (target, 'https://weibo.com/'),
    ];
    final inner = unwrapLivePhotoParam(target);
    if (inner != null && inner != target) {
      attempts.add((inner, 'https://weibo.com/'));
      attempts.add((inner, 'https://m.weibo.cn/'));
    }

    Object? lastError;
    for (final (url, referer) in attempts) {
      final part = File('${dest.path}.${DateTime.now().microsecondsSinceEpoch}.part');
      try {
        final size = await Api.downloadToFile(
          url,
          part,
          cookie: cookie,
          referer: referer,
        );
        if (size > 0 && isValidVideoContainer(part)) {
          if (dest.existsSync()) dest.deleteSync();
          try {
            part.renameSync(dest.path);
          } on Object {
            part.copySync(dest.path);
            if (part.existsSync()) part.deleteSync();
          }
          return dest;
        }
        lastError = ApiException('实况视频格式无效');
      } on Object catch (e) {
        lastError = e;
      } finally {
        if (part.existsSync()) {
          try {
            part.deleteSync();
          } on Object {
            // ignore
          }
        }
      }
    }
    throw lastError ?? ApiException('实况视频下载失败');
  }

  static String _fileName(String url, Set<String> allowed, String fallback) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final safe = allowed.contains(ext) ? ext : fallback;
    return 'hobo_${DateTime.now().millisecondsSinceEpoch}.$safe';
  }
}
