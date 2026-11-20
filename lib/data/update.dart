/// 版本号与 GitHub 入口的唯一真源。
///
/// 「设置 → 检查更新」不再自己解析 Releases，而是直接打开 [homepage]（GitHub Pages），
/// 由页面上的「下载最新版」把人送到 Releases 页。这样版本说明、更新日志和安装包只有一处要维护。
///
/// [latest] 保留给以后的原生下载链路：真要做应用内升级、边下边装时；
/// 现在没有界面调用它，仓库也没配置发布内容时它会返回 null，不会抛异常。
library;

import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.downloadUrl,
    this.size = 0,
    this.prerelease = false,
    this.publishedAt = '',
  });

  final String version;
  final String tag;
  final String notes;
  final String downloadUrl;
  final int size;
  final bool prerelease;
  final String publishedAt;

  String get sizeLabel {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}

abstract final class Updater {
  /// GitHub 账号与仓库名；所有对外地址都由这两段拼出来。
  static const owner = 'ashshay';
  static const repository = 'hobo';

  /// 仓库主页，`https://github.com/ashshay/hobo`。
  static const repoUrl = 'https://github.com/$owner/$repository';

  /// GitHub Pages 站点，`https://ashshay.github.io/hobo/`。
  /// 「检查更新」跳到这一页，页头就有「下载最新版」。
  static const homepage = 'https://$owner.github.io/$repository/';

  /// Releases 列表，`https://github.com/ashshay/hobo/releases`。
  static const releasesPage = '$repoUrl/releases';

  /// GitHub REST 接口，只给 [latest] 用。
  static const releasesUrl =
      'https://api.github.com/repos/$owner/$repository/releases';

  /// 界面上显示的版本号，跟 `pubspec.yaml` 的 `version: 1.05.0+7` 对齐。
  static const displayVersion = '1.05';

  /// 跟 pubspec 的 `+N` 对齐。同一个版本号会反复出包，靠它区分是哪一次构建。
  static const buildNumber = '7';

  /// `1.01（build 3）`
  static const versionLabel = '$displayVersion（build $buildNumber）';

  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<UpdateInfo?> latest(
    String current, {
    bool includePrerelease = true,
  }) async {
    if (releasesUrl.isEmpty) return null;
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(releasesUrl));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'Hobo');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! List) return null;
      UpdateInfo? best;
      for (final item in decoded) {
        if (item is! Map) continue;
        final info = _fromRelease(item);
        if (info == null) continue;
        if (!includePrerelease && info.prerelease) continue;
        if (_compare(info.version, current) <= 0) continue;
        if (best == null || _compare(info.version, best.version) > 0) {
          best = info;
        }
      }
      return best;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static UpdateInfo? _fromRelease(Map<dynamic, dynamic> release) {
    final tag = release['tag_name']?.toString() ?? '';
    if (tag.isEmpty) return null;
    final version = _normalizeVersion(tag);
    if (version.isEmpty) return null;
    final assets = release['assets'];
    String downloadUrl = '';
    var size = 0;
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name']?.toString().toLowerCase() ?? '';
        if (!name.endsWith('.apk')) continue;
        downloadUrl = asset['browser_download_url']?.toString() ?? '';
        size = int.tryParse(asset['size']?.toString() ?? '') ?? 0;
        if (downloadUrl.isNotEmpty) break;
      }
    }
    if (downloadUrl.isEmpty) return null;
    return UpdateInfo(
      version: version,
      tag: tag,
      notes: release['body']?.toString() ?? '',
      downloadUrl: downloadUrl,
      size: size,
      prerelease: release['prerelease'] == true,
      publishedAt: release['published_at']?.toString() ?? '',
    );
  }

  static String _normalizeVersion(String tag) {
    var value = tag.trim();
    if (value.toLowerCase().startsWith('v')) value = value.substring(1);
    final dash = value.indexOf('-');
    if (dash > 0) value = value.substring(0, dash);
    return RegExp(r'^\d+(\.\d+)*$').hasMatch(value) ? value : '';
  }

  /// 段对段比较；缺失的段按 0 算。
  static int _compare(String left, String right) {
    final a = left.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final b = right.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
