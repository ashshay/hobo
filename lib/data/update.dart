/// 版本号、GitHub Release 自动检测与更新入口的唯一真源。
///
/// 冷启动在首页自动拉取 GitHub Releases（带 ETag 条件请求避免消耗匿名限流额度），
/// 发现更高版本且用户未勾选「不再提醒」时在首页弹窗提醒；点击「立即更新」直接跳转到
/// GitHub 最新 Release 页面下载安装包。
library;

import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'settings.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    this.name = '',
    this.pageUrl = '',
    this.downloadUrl = '',
    this.size = 0,
    this.prerelease = false,
    this.publishedAt = '',
  });

  final String version;
  final String tag;
  final String name;
  final String notes;

  /// GitHub Release 详情页，例如 `https://github.com/ashshay/hobo/releases/tag/v1.09.0`。
  final String pageUrl;

  /// APK 附件直链（没有 APK 附件时为空串，仍可通过 [pageUrl] 打开 Release 页）。
  final String downloadUrl;
  final int size;
  final bool prerelease;
  final String publishedAt;

  /// 点击更新时跳转的目标页面：优先具体版本的 Release 页，缺失时退回 `/releases/latest`。
  String get targetReleaseUrl =>
      pageUrl.isNotEmpty ? pageUrl : Updater.latestReleasePage;

  String get sizeLabel {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}

/// 一次更新检查的结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.update,
    this.skipped = false,
    this.error,
  });

  final String currentVersion;
  final UpdateInfo? update;

  /// 用户之前对这个版本勾过「不再提醒」。
  final bool skipped;
  final String? error;

  bool get hasUpdate => update != null;

  /// 自动检查时是否应当弹出首页提醒窗口。
  bool get shouldPrompt => update != null && !skipped;
}

abstract final class Updater {
  /// GitHub 账号与仓库名；所有对外地址都由这两段拼出来。
  static const owner = 'ashshay';
  static const repository = 'hobo';

  /// 仓库主页，`https://github.com/ashshay/hobo`。
  static const repoUrl = 'https://github.com/$owner/$repository';

  /// GitHub Pages 站点，`https://ashshay.github.io/hobo/`。
  static const homepage = 'https://$owner.github.io/$repository/';

  /// Releases 列表，`https://github.com/ashshay/hobo/releases`。
  static const releasesPage = '$repoUrl/releases';

  /// GitHub 最新 Release 页面，`https://github.com/ashshay/hobo/releases/latest`。
  static const latestReleasePage = '$releasesPage/latest';

  /// GitHub REST 接口：拉取最近 15 条 release，自己按版本号挑出最新的正式版。
  static const releasesUrl =
      'https://api.github.com/repos/$owner/$repository/releases?per_page=15';

  /// 自动检查网络节流间隔：6 小时内优先复用本地缓存结果，避免频繁打 GitHub 接口。
  static const autoCheckInterval = Duration(hours: 6);

  /// 界面上显示的版本号，跟 `pubspec.yaml` 的 `version: 1.09.0+11` 对齐。
  static const displayVersion = '1.10';

  /// 跟 pubspec 的 `+N` 对齐。同一个版本号会反复出包，靠它区分是哪一次构建。
  static const buildNumber = '12';

  /// `1.09（build 11）`
  static const versionLabel = '$displayVersion（build $buildNumber）';

  static Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.trim().isNotEmpty) return info.version.trim();
    } on Object {
      // 单元测试或非平台环境下回退到内置版本常量。
    }
    return displayVersion;
  }

  /// 检查是否有新版本。
  ///
  /// - [force] 为 false（启动自动检查）：遵守 `settings.autoCheckUpdate` 开关与节流间隔；
  ///   节流窗口内有缓存时直接解析缓存，这样用户上次只点「稍后」没勾「不再提醒」的话，
  ///   下次启动仍会提醒，但不会多发一次网络请求。
  /// - [force] 为 true（设置页手动点击）：无视节流直接向 GitHub 请求（带 ETag 条件头）。
  static Future<UpdateCheckResult> checkForUpdate({
    required Settings settings,
    bool force = false,
    bool includePrerelease = false,
    String? currentVersionOverride,
    int? nowMillis,
  }) async {
    final current = currentVersionOverride ?? await currentVersion();
    if (!force && !settings.autoCheckUpdate) {
      return UpdateCheckResult(currentVersion: current);
    }

    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final withinInterval =
        settings.updateCheckedAt > 0 &&
        now - settings.updateCheckedAt < autoCheckInterval.inMilliseconds;

    if (!force && withinInterval && settings.updateCache.isNotEmpty) {
      final info = parseLatest(
        settings.updateCache,
        current,
        includePrerelease: includePrerelease,
      );
      return UpdateCheckResult(
        currentVersion: current,
        update: info,
        skipped: info != null && settings.skippedUpdate == info.version,
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Hobo';
    try {
      final request = await client
          .getUrl(Uri.parse(releasesUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'Hobo');
      if (settings.updateEtag.isNotEmpty && settings.updateCache.isNotEmpty) {
        request.headers.set('If-None-Match', settings.updateEtag);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == HttpStatus.notModified &&
          settings.updateCache.isNotEmpty) {
        await response.drain<void>();
        settings.applyUpdateCheckedAt(now);
        final info = parseLatest(
          settings.updateCache,
          current,
          includePrerelease: includePrerelease,
        );
        return UpdateCheckResult(
          currentVersion: current,
          update: info,
          skipped: info != null && settings.skippedUpdate == info.version,
        );
      }
      if (response.statusCode == HttpStatus.ok) {
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 15));
        final etag = response.headers.value('etag') ?? '';
        settings
          ..applyUpdateCache(etag, body)
          ..applyUpdateCheckedAt(now);
        final info = parseLatest(
          body,
          current,
          includePrerelease: includePrerelease,
        );
        return UpdateCheckResult(
          currentVersion: current,
          update: info,
          skipped: info != null && settings.skippedUpdate == info.version,
        );
      }
      await response.drain<void>();
      final message = _failureMessage(
        response.statusCode,
        response.headers.value('x-ratelimit-reset'),
      );
      if (!force && settings.updateCache.isNotEmpty) {
        final info = parseLatest(
          settings.updateCache,
          current,
          includePrerelease: includePrerelease,
        );
        return UpdateCheckResult(
          currentVersion: current,
          update: info,
          skipped: info != null && settings.skippedUpdate == info.version,
        );
      }
      return UpdateCheckResult(currentVersion: current, error: message);
    } on Object {
      if (!force && settings.updateCache.isNotEmpty) {
        final info = parseLatest(
          settings.updateCache,
          current,
          includePrerelease: includePrerelease,
        );
        return UpdateCheckResult(
          currentVersion: current,
          update: info,
          skipped: info != null && settings.skippedUpdate == info.version,
        );
      }
      return UpdateCheckResult(
        currentVersion: current,
        error: '检查更新失败，请检查网络或直接访问 GitHub 发布页',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 直接请求 GitHub Releases，返回比 [current] 新的最高版本；失败或已是最新时返回 null。
  static Future<UpdateInfo?> latest(
    String current, {
    bool includePrerelease = false,
  }) async {
    if (releasesUrl.isEmpty) return null;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Hobo';
    try {
      final request = await client
          .getUrl(Uri.parse(releasesUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('User-Agent', 'Hobo');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      return parseLatest(
        body,
        current,
        includePrerelease: includePrerelease,
      );
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 从 GitHub Releases JSON（支持数组与单对象）挑出比 [current] 新的最高版本。
  static UpdateInfo? parseLatest(
    String body,
    String current, {
    bool includePrerelease = false,
  }) {
    if (body.trim().isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on Object {
      return null;
    }
    final List<dynamic> items;
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map) {
      items = [decoded];
    } else {
      return null;
    }
    final currentNorm = normalizeVersion(current);
    final baseline = currentNorm.isNotEmpty ? currentNorm : current.trim();
    UpdateInfo? best;
    for (final item in items) {
      if (item is! Map) continue;
      final info = fromRelease(item);
      if (info == null) continue;
      if (!includePrerelease && info.prerelease) continue;
      if (compareVersions(info.version, baseline) <= 0) continue;
      if (best == null || compareVersions(info.version, best.version) > 0) {
        best = info;
      }
    }
    return best;
  }

  /// 解析单条 GitHub Release JSON；跳过草稿或无有效版本号的条目。
  static UpdateInfo? fromRelease(Map<dynamic, dynamic> release) {
    if (release['draft'] == true) return null;
    final tag = release['tag_name']?.toString().trim() ?? '';
    if (tag.isEmpty) return null;
    final version = normalizeVersion(tag);
    if (version.isEmpty) return null;

    var downloadUrl = '';
    var size = 0;
    final assets = release['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name']?.toString().toLowerCase() ?? '';
        if (!name.endsWith('.apk')) continue;
        final url = asset['browser_download_url']?.toString().trim() ?? '';
        if (url.isEmpty) continue;
        downloadUrl = url;
        size = int.tryParse(asset['size']?.toString() ?? '') ?? 0;
        break;
      }
    }

    final rawHtmlUrl = release['html_url']?.toString().trim() ?? '';
    final pageUrl = rawHtmlUrl.isNotEmpty
        ? rawHtmlUrl
        : '$releasesPage/tag/$tag';
    final prerelease =
        release['prerelease'] == true || tag.contains('-');

    return UpdateInfo(
      version: version,
      tag: tag,
      name: release['name']?.toString().trim() ?? '',
      notes: release['body']?.toString().trim() ?? '',
      pageUrl: pageUrl,
      downloadUrl: downloadUrl,
      size: size,
      prerelease: prerelease,
      publishedAt: release['published_at']?.toString() ?? '',
    );
  }

  static String normalizeVersion(String tag) {
    var value = tag.trim();
    if (value.toLowerCase().startsWith('v')) value = value.substring(1);
    final plus = value.indexOf('+');
    if (plus > 0) value = value.substring(0, plus);
    final dash = value.indexOf('-');
    if (dash > 0) value = value.substring(0, dash);
    return RegExp(r'^\d+(\.\d+)*$').hasMatch(value) ? value : '';
  }

  /// 段对段比较；缺失的段按 0 算。
  static int compareVersions(String left, String right) {
    final a = left.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final b = right.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// 把 Release 说明整理成适合弹窗阅读的纯文本：去掉 Markdown 标记并限制行数。
  static String plainReleaseNotes(String raw, {int maxLines = 14}) {
    final lines = <String>[];
    for (final source in raw.split('\n')) {
      var line = source.trimRight();
      if (line.startsWith('#')) {
        line = line.replaceFirst(RegExp(r'^#+\s*'), '');
      }
      line = line.replaceAll('`', '').replaceAll('**', '');
      line = line.replaceFirst(RegExp(r'^[-*]\s+'), '· ');
      if (line.trim().isEmpty) continue;
      lines.add(line);
      if (lines.length >= maxLines) break;
    }
    return lines.join('\n');
  }

  static String _failureMessage(int statusCode, String? resetHeader) {
    if (statusCode == 403 || statusCode == 429) {
      final resetAt = int.tryParse(resetHeader ?? '');
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (resetAt != null && resetAt > nowSec) {
        final minutes = ((resetAt - nowSec) / 60).ceil().clamp(1, 60);
        return 'GitHub 接口请求过于频繁，约 $minutes 分钟后再试';
      }
      return 'GitHub 接口限流，请稍后再试';
    }
    return '检查更新失败（HTTP $statusCode）';
  }
}
