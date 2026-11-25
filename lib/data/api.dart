/// 微博接口层：dio + 统一请求头 + `Set-Cookie` 回收 + GET 磁盘缓存。
///
/// 对应 Kotlin 版 `data/Api.kt`（OkHttp）。签名、UA、Referer、XSRF 令牌的用法逐项照抄，
/// 这些是微博接口最容易「莫名其妙 403」的地方。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'cache_store.dart';
import 'cookie_vault.dart';

class ApiException implements Exception {
  ApiException(this.message, [this.errno]);

  final String message;
  final String? errno;

  @override
  String toString() => message;
}

/// 非 2xx 响应。微博的 CSRF 校验失败就是 `HTTP 403` + `errno:100006 请求非法`，
/// 调用方要据此判断是否该刷新 st 重试。
class ApiHttpException implements Exception {
  ApiHttpException(this.code, this.body);

  final int code;
  final String body;

  @override
  String toString() => 'HTTP $code';
}

class Api {
  Api._();

  static const webUa =
      'Mozilla/5.0 (Linux; Android 13; MI 9) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  static const desktopUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// 每收到一次微博响应，就把里面的 `Set-Cookie` 交出去，由 [Repo] 收进 cookie 表。
  static void Function(Uri url, List<String> setCookies)? cookieSink;

  static CacheStore? cache;

  static final Dio _dio = _build(followRedirects: true);
  static final Dio _noRedirect = _build(followRedirects: false);

  static Dio _build({required bool followRedirects}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
        sendTimeout: const Duration(seconds: 60),
        followRedirects: followRedirects,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: const {'Accept-Encoding': 'gzip'},
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()..idleTimeout = const Duration(seconds: 30);
        return client;
      },
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          final request = response.requestOptions;
          final setCookies = response.headers['set-cookie'] ?? const <String>[];
          final host = Uri.tryParse(request.uri.toString())?.host ?? '';
          final sink = cookieSink;
          if (setCookies.isNotEmpty && sink != null && CookieVault.isWeibo(host)) {
            final uri = Uri.tryParse(request.uri.toString());
            if (uri != null) {
              try {
                sink(uri, setCookies);
              } on Object {
                // 回收失败不影响这次请求。
              }
            }
          }
          handler.next(response);
        },
      ),
    );
    return dio;
  }

  static String url(String base, [Map<String, String?> params = const {}]) {
    final uri = Uri.parse(base);
    final merged = <String, String>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value != null) merged[entry.key] = value;
    }
    return uri.replace(queryParameters: merged.isEmpty ? null : merged).toString();
  }

  static Future<Map<String, dynamic>> get(
    String target,
    String? cookie, {
    bool force = false,
  }) async {
    final store = cache;
    if (!force) {
      final cached = store?.read(target, cookie);
      if (cached != null) return cached;
    }
    final json = await _request(
      target,
      cookie: cookie,
      headers: _weiboHeaders(cookie),
    );
    store?.write(target, cookie, json);
    return json;
  }

  /// 带 XSRF 令牌的读请求，且不进缓存（搜索联想这类结果随输入变化）。
  static Future<Map<String, dynamic>> getWithSt(
    String target,
    String? cookie,
    String? st,
  ) {
    return _request(target, cookie: cookie, headers: _weiboHeaders(cookie, st));
  }

  /// 部分 weibo.com 的 ajax 接口拒绝移动端 Referer，这里按桌面浏览器的方式签名。
  static Future<Map<String, dynamic>> getDesktop(
    String target,
    String? cookie,
  ) {
    return _request(
      target,
      cookie: cookie,
      headers: {
        'User-Agent': desktopUa,
        'Accept': 'application/json, text/plain, */*',
        'Referer': 'https://weibo.com/',
        'X-Requested-With': 'XMLHttpRequest',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      },
    );
  }

  static Future<Map<String, dynamic>> postDesktopJson(
    String target,
    String body, {
    String? cookie,
    String? xsrfToken,
  }) {
    return _request(
      target,
      method: 'POST',
      cookie: cookie,
      body: body,
      headers: {
        'User-Agent': desktopUa,
        'Accept': 'application/json, text/plain, */*',
        'Referer': 'https://weibo.com/',
        'Origin': 'https://weibo.com',
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/json; charset=utf-8',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        if (xsrfToken != null && xsrfToken.isNotEmpty) 'X-XSRF-TOKEN': xsrfToken,
      },
    );
  }

  static Future<Map<String, dynamic>> post(
    String target,
    Map<String, String> form, {
    String? cookie,
    String? st,
  }) {
    return _request(
      target,
      method: 'POST',
      cookie: cookie,
      form: form,
      // Dio 对 Map 会做 urlEncode，但不会自动补 Content-Type；不写这一行时
      // `comment/like` 这类接口会直接回 `{"ok":0}`（正文当成空表单）。
      headers: {
        ..._weiboHeaders(cookie, st),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      },
    );
  }

  static Future<Map<String, dynamic>> postVote(
    String target,
    Map<String, String> form, {
    String? cookie,
    required String referer,
  }) {
    return _request(
      target,
      method: 'POST',
      cookie: cookie,
      form: form,
      headers: {
        'User-Agent': webUa,
        'Referer': referer,
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      },
    );
  }

  static Future<String> getHtml(String target, String? cookie) async {
    final response = await _send(
      target,
      headers: {
        'User-Agent': webUa,
        'Referer': 'https://m.weibo.cn/',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      },
    );
    final body = response.data?.toString() ?? '';
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw ApiHttpException(response.statusCode ?? 0, body);
    }
    return body;
  }

  /// 下载图片这类小文件：微博 CDN 只认带 Referer 的请求，不带就是 403。
  static Future<List<int>> downloadBytes(
    String target, {
    String? cookie,
    String referer = 'https://m.weibo.cn/',
  }) async {
    final response = await _send(
      target,
      headers: _mediaHeaders(cookie, referer),
      responseType: ResponseType.bytes,
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiHttpException(status, '');
    }
    final data = response.data;
    if (data is List<int>) return data;
    if (data is List) return data.cast<int>();
    throw ApiException('下载失败');
  }

  /// 下载视频到本地临时文件：大文件走流式写盘，不整段进内存。
  static Future<int> downloadToFile(
    String target,
    File file, {
    String? cookie,
    String referer = 'https://m.weibo.cn/',
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _dio.download(
      target,
      file.path,
      options: Options(headers: _mediaHeaders(cookie, referer)),
      onReceiveProgress: onProgress,
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      if (file.existsSync()) file.deleteSync();
      throw ApiHttpException(status, '');
    }
    return file.existsSync() ? file.lengthSync() : 0;
  }

  static Map<String, String> _mediaHeaders(String? cookie, String referer) => {
    'User-Agent': webUa,
    'Referer': referer,
    if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
  };

  static Future<String> resolveRedirect(String target, String? cookie) async {    var current = unwrapSinaUrlStatic(target) ?? target;
    for (var hop = 0; hop < 6; hop++) {
      if (!current.toLowerCase().startsWith('http://') &&
          !current.toLowerCase().startsWith('https://')) {
        return current;
      }
      try {
        final uri = Uri.parse(current);
        final response = await _send(
          current,
          headers: {
            'User-Agent': webUa,
            if (cookie != null &&
                cookie.isNotEmpty &&
                CookieVault.isWeibo(uri.host))
              'Cookie': cookie,
          },
          noRedirect: true,
        );
        final location = response.headers.value('location')?.trim() ?? '';
        if (location.isEmpty) return current;
        final resolved = location.toLowerCase().startsWith('http://') ||
                location.toLowerCase().startsWith('https://') ||
                location.contains('://')
            ? location
            : uri.resolve(location).toString();
        final next = unwrapSinaUrlStatic(resolved) ?? resolved;
        if (next == current) return current;
        current = next;
      } on Object {
        return current;
      }
    }
    return current;
  }

  /// 上传图片。发微博图字段是 `pic`，私信图是 `file`。
  static Future<Map<String, dynamic>> upload(
    String target, {
    required List<int> bytes,
    required String fileName,
    required String mime,
    String? cookie,
    String? st,
    String field = 'pic',
    Map<String, String> extra = const {},
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('st', st ?? ''));
    for (final entry in extra.entries) {
      form.fields.add(MapEntry(entry.key, entry.value));
    }
    form.files.add(
      MapEntry(field, MultipartFile.fromBytes(bytes, filename: fileName)),
    );
    return _request(
      target,
      method: 'POST',
      cookie: cookie,
      formData: form,
      headers: _weiboHeaders(cookie, st),
    );
  }

  /// 向微博领一个访客身份，返回可直接塞进 `Cookie` 头的 `SUB=…; SUBP=…`。
  /// m.weibo.cn 的只读接口不带 cookie 一律 HTTP 432，带上它就能像未登录网页版一样读。
  static Future<String> genVisitor() async {
    final response = await _send(
      'https://visitor.passport.weibo.cn/visitor/genvisitor2',
      method: 'POST',
      form: {'cb': 'visitor_gray_callback', 'tid': '', 'from': 'weibo'},
      headers: {
        'User-Agent': webUa,
        'Referer': 'https://m.weibo.cn/',
      },
    );
    final text = response.data?.toString() ?? '';
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw ApiHttpException(response.statusCode ?? 0, text);
    }
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    final jsonText = open >= 0 && close > open
        ? text.substring(open + 1, close)
        : text;
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        final raw = decoded['data'];
        if (raw is Map) {
          data = {for (final e in raw.entries) e.key.toString(): e.value};
        }
      }
    } on Object {
      data = null;
    }
    final sub = data?['sub']?.toString() ?? '';
    final subp = data?['subp']?.toString() ?? '';
    if (sub.isEmpty) throw ApiException('领取访客身份失败');
    return subp.isEmpty ? 'SUB=$sub' : 'SUB=$sub; SUBP=$subp';
  }

  static Map<String, String> _weiboHeaders(
    String? cookie, [
    String? st,
  ]) {
    return {
      'User-Agent': webUa,
      'Accept': 'application/json',
      'Referer': 'https://m.weibo.cn/',
      'X-Requested-With': 'XMLHttpRequest',
      'MWeibo-Pwa': '1',
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      if (st != null && st.isNotEmpty) 'X-XSRF-TOKEN': st,
    };
  }

  static Future<Map<String, dynamic>> _request(
    String target, {
    String method = 'GET',
    String? cookie,
    Map<String, String> headers = const {},
    Map<String, String>? form,
    FormData? formData,
    String? body,
  }) async {
    final response = await _send(
      target,
      method: method,
      headers: headers,
      form: form,
      formData: formData,
      body: body,
    );
    final text = response.data?.toString() ?? '';
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ApiHttpException(status, text);
    }
    if (text.trim().isEmpty) throw ApiException('空响应');
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return {for (final e in decoded.entries) e.key.toString(): e.value};
      }
      throw ApiException('响应不是 JSON');
    } on FormatException {
      throw ApiException('响应不是 JSON');
    }
  }

  static Future<Response<dynamic>> _send(
    String target, {
    String method = 'GET',
    Map<String, String> headers = const {},
    Map<String, String>? form,
    FormData? formData,
    String? body,
    bool noRedirect = false,
    ResponseType? responseType,
  }) {
    final client = noRedirect ? _noRedirect : _dio;
    return client.request<dynamic>(
      target,
      data: formData ?? body ?? form,
      options: Options(
        method: method,
        headers: headers,
        responseType: responseType,
      ),
    );
  }

  /// 拆 `sinaurl?u=` 包装：评论配图、@ 链接都靠它拿到真实地址。
  static String? unwrapSinaUrlStatic(String raw) {
    var url = raw.trim();
    var changed = false;
    for (var i = 0; i < 3; i++) {
      final at = url.toLowerCase().indexOf('sinaurl?');
      if (at < 0) break;
      final query = url.substring(at + 'sinaurl?'.length);
      String? target;
      for (final part in query.split('&')) {
        final index = part.indexOf('=');
        final key = index < 0 ? part : part.substring(0, index);
        if (key == 'u') {
          target = index < 0 ? '' : part.substring(index + 1);
          break;
        }
      }
      if (target == null || target.isEmpty) break;
      String decoded;
      try {
        decoded = Uri.decodeComponent(target);
      } on Object {
        decoded = target;
      }
      if (decoded.trim().isEmpty || decoded == url) break;
      url = decoded;
      changed = true;
    }
    return changed ? url : null;
  }
}
