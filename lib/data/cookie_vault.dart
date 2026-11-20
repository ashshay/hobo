/// 登录态存放方式：一张「域名 → 该域名下的 cookie」表，域名下的多条用换行分隔。
///
/// 同一个账号在 `m.weibo.cn` 和 `weibo.com` 上各有一份 cookie，网页端还会持续用
/// `Set-Cookie` 往回调，所以不能只存一个 `Cookie` 头字符串。
library;

import 'dart:io';

import 'package:flutter/services.dart';

const weiboCnDomain = '.weibo.cn';
const weiboComDomain = '.weibo.com';
const passportCnDomain = 'passport.weibo.cn';

abstract final class CookieVault {
  static const MethodChannel _channel = MethodChannel('hobo/cookies');

  static bool isWeibo(String host) =>
      host == 'weibo.cn' ||
      host.endsWith('.weibo.cn') ||
      host == 'weibo.com' ||
      host.endsWith('.weibo.com') ||
      host == 'sina.cn' ||
      host.endsWith('.sina.cn');

  /// 把 `Cookie` 头拆成「一行一条」。
  static List<String> parseHeader(String header) => header
      .split(';')
      .map((line) => line.trim())
      .where((line) => line.contains('='))
      .toList();

  static String joinHeader(Iterable<String> lines) => lines.join('; ');

  /// 只有一个域名的表：网页登录刚拿到的那一串先挂在 `.weibo.cn` 上。
  static Map<String, String> seed(String header, [String domain = weiboCnDomain]) {
    final lines = parseHeader(header);
    if (lines.isEmpty) return const {};
    return {domain: lines.join('\n')};
  }

  /// 把一次响应里的 `Set-Cookie` 合进表：同名覆盖，空值或 `Max-Age<=0` 视为删除。
  static Map<String, String> absorb(
    Map<String, String> cookies,
    Uri? url,
    List<String> setCookies,
  ) {
    if (setCookies.isEmpty) return cookies;
    final out = Map<String, String>.from(cookies);
    for (final raw in setCookies) {
      final parts = raw.split(';');
      final pair = parts.first.trim();
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      String? domain;
      for (final part in parts.skip(1)) {
        final attr = part.trim();
        if (attr.toLowerCase().startsWith('domain=')) {
          final rawDomain = attr.substring('domain='.length).trim();
          final bare = rawDomain.replaceFirst(RegExp(r'^\.+'), '');
          domain = bare.isEmpty ? null : '.$bare';
          break;
        }
      }
      domain ??= url?.host.isEmpty == false ? '.${url!.host}' : null;
      if (domain == null) continue;
      final expired =
          value.isEmpty ||
          parts.any((part) {
            final attr = part.trim();
            if (attr.toLowerCase().startsWith('max-age=')) {
              final seconds = int.tryParse(attr.substring('max-age='.length));
              return (seconds ?? 1) <= 0;
            }
            return attr.toLowerCase().startsWith('expires=') &&
                attr.contains('1970');
          });
      final lines = (out[domain] ?? '')
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      lines.removeWhere(
        (line) =>
            line.split('=').first.trim().toLowerCase() == name.toLowerCase(),
      );
      if (!expired) lines.add('$name=$value');
      if (lines.isEmpty) {
        out.remove(domain);
      } else {
        out[domain] = lines.join('\n');
      }
    }
    return out;
  }

  /// 拼请求头：域名按「越具体越靠后」排，后出现的同名项覆盖前面的。
  static String header(Map<String, String> cookies, String host) {
    if (cookies.isEmpty) return '';
    final matched = cookies.keys.where((d) => matches(d, host)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final merged = <String, String>{};
    for (final domain in matched) {
      for (final line in (cookies[domain] ?? '').split('\n')) {
        final index = line.indexOf('=');
        if (index <= 0) continue;
        merged[line.substring(0, index).trim()] = line.substring(index + 1).trim();
      }
    }
    return joinHeader(merged.entries.map((e) => '${e.key}=${e.value}'));
  }

  /// 认证用请求头：按 host 拼，缺 `SUB` / `SUBP` 再从表里其它微博域补上。
  static String authHeader(Map<String, String> cookies, String host) {
    if (cookies.isEmpty) return '';
    final merged = <String, String>{};
    void absorbLines(String domain) {
      for (final line in (cookies[domain] ?? '').split('\n')) {
        final index = line.indexOf('=');
        if (index <= 0) continue;
        merged[line.substring(0, index).trim()] = line.substring(index + 1).trim();
      }
    }

    final matched = cookies.keys.where((d) => matches(d, host)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final domain in matched) {
      absorbLines(domain);
    }
    for (final name in const ['SUB', 'SUBP']) {
      if ((merged[name] ?? '').isNotEmpty) continue;
      final candidates = cookies.keys
          .where((d) => isWeibo(d) && !matches(d, host))
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final domain in candidates) {
        final has = (cookies[domain] ?? '').split('\n').any((line) {
          final index = line.indexOf('=');
          if (index <= 0) return false;
          return line.substring(0, index).trim() == name &&
              line.substring(index + 1).trim().isNotEmpty;
        });
        if (has) {
          absorbLines(domain);
          break;
        }
      }
    }
    return joinHeader(merged.entries.map((e) => '${e.key}=${e.value}'));
  }

  /// 桌面端请求头：保留目标域自身的 cookie，仅在缺 `SUB` / `SUBP` / `ALF` 时补。
  static String desktopAuthHeader(Map<String, String> cookies, String host) {
    if (cookies.isEmpty) return '';
    final merged = <String, String>{};
    void absorbDomain(String domain, [Set<String>? onlyIfMissing]) {
      for (final line in (cookies[domain] ?? '').split('\n')) {
        final index = line.indexOf('=');
        if (index <= 0) continue;
        final key = line.substring(0, index).trim();
        final value = line.substring(index + 1).trim();
        if (onlyIfMissing != null &&
            (!onlyIfMissing.contains(key) || (merged[key] ?? '').isNotEmpty)) {
          continue;
        }
        merged[key] = value;
      }
    }

    final matched = cookies.keys.where((d) => matches(d, host)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final domain in matched) {
      absorbDomain(domain);
    }
    const authKeys = {'SUB', 'SUBP', 'ALF'};
    final others = cookies.keys
        .where((d) => isWeibo(d) && !matches(d, host))
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final domain in others) {
      absorbDomain(domain, authKeys);
    }
    return joinHeader(merged.entries.map((e) => '${e.key}=${e.value}'));
  }

  /// 读取指定 host 下某个 cookie 的当前值。
  static String? cookieValue(
    Map<String, String> cookies,
    String host,
    String name,
  ) {
    if (cookies.isEmpty) return null;
    String? found;
    final matched = cookies.keys.where((d) => matches(d, host)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final domain in matched) {
      for (final line in (cookies[domain] ?? '').split('\n')) {
        final index = line.indexOf('=');
        if (index <= 0) continue;
        if (line.substring(0, index).trim().toLowerCase() ==
            name.toLowerCase()) {
          final value = line.substring(index + 1).trim();
          found = value.isEmpty ? null : value;
        }
      }
    }
    return found;
  }

  static bool matches(String domain, String host) {
    final bare = domain.replaceFirst(RegExp(r'^\.+'), '');
    return host.toLowerCase() == bare.toLowerCase() ||
        host.toLowerCase().endsWith(domain.toLowerCase());
  }

  /// 整表灌进 WebView：先清空再逐条设置。原生侧是系统 CookieManager，与 WebView 共用。
  static Future<void> inject(Map<String, String> cookies) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('inject', {'cookies': cookies});
    } on PlatformException {
      // 没有原生实现（桌面调试）时静默跳过。
    }
  }

  /// 不动现有 cookie，只把表里的补进去：新建 WebView 时用，避免抹掉登录页刚种下的 SSO cookie。
  static Future<void> plant(Map<String, String> cookies) => inject(cookies);

  /// 按域名把 WebView 现有 cookie 读成表。网页登录完成时落一次。
  static Future<Map<String, String>> readDomains() async {
    if (!Platform.isAndroid) return const {};
    try {
      final result = await _channel.invokeMapMethod<String, String>('read');
      if (result == null) return const {};
      return {
        for (final entry in result.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      };
    } on PlatformException {
      return const {};
    }
  }

  static Future<void> clearWebViewCookies() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } on PlatformException {
      // 同上。
    }
  }
}
