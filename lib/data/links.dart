/// 微博的各种链接：站内相对路径、`sinaweibo://` 私有 scheme、`sinaurl` 包装、
/// 短链、图片直链、视频页、超话页。点正文里的链接时统一在这里判断该进哪个页面。
library;

import 'super_topic_id.dart';

const _weiboMobile = 'https://m.weibo.cn';

String? _queryOf(String link) {
  final rest = link.contains('?') ? link.substring(link.indexOf('?') + 1) : '';
  final hash = rest.indexOf('#');
  return hash < 0 ? rest : rest.substring(0, hash);
}

String? _param(String query, String name) {
  for (final part in query.split('&')) {
    final index = part.indexOf('=');
    final key = index < 0 ? part : part.substring(0, index);
    if (key.toLowerCase() == name.toLowerCase()) {
      final value = index < 0 ? '' : part.substring(index + 1);
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

String _decode(String value) {
  try {
    return Uri.decodeComponent(value);
  } on Object {
    return value;
  }
}

/// `sinaweibo://` / `intent://` 是微博的私有 scheme：超话、视频、单条微博都靠它。
/// 这里翻成网页地址，认不出来返回 null。
String? _weiboPrivateLink(String raw) {
  final lower = raw.toLowerCase();
  if (lower.startsWith('intent://')) {
    var body = raw.substring('intent://'.length);
    final intentAt = body.indexOf('#Intent');
    if (intentAt >= 0) body = body.substring(0, intentAt);
    final path = body.split('?').first;
    final query = _queryOf(body) ?? '';
    if (path.toLowerCase().contains('video') ||
        query.toLowerCase().contains('fid=')) {
      final fid = _param(query, 'fid');
      if (fid != null) return 'https://video.weibo.com/show?fid=$fid';
      return query.isEmpty ? null : '$_weiboMobile/s/video/index?$query';
    }
    if (path.toLowerCase().contains('pageinfo')) {
      return query.isEmpty ? null : '$_weiboMobile/p/index?$query';
    }
    return null;
  }
  if (!lower.startsWith('sinaweibo://')) return null;
  final body = raw.substring('sinaweibo://'.length);
  final path = body.split('?').first;
  final query = _queryOf(body) ?? '';
  if (path.startsWith('pageinfo') ||
      query.toLowerCase().contains('containerid=100808')) {
    return query.isEmpty ? null : '$_weiboMobile/p/index?$query';
  }
  if (path.startsWith('video')) {
    final fid = _param(query, 'fid');
    if (fid != null) return 'https://video.weibo.com/show?fid=$fid';
    return query.isEmpty ? null : '$_weiboMobile/s/video/index?$query';
  }
  if (path.startsWith('detail') || path.startsWith('status')) {
    final id = _param(query, 'mblogid') ?? _param(query, 'id');
    if (id != null && RegExp(r'^\d+$').hasMatch(id)) {
      return '$_weiboMobile/detail/$id';
    }
    return null;
  }
  if (path.startsWith('userinfo')) {
    final uid = _param(query, 'uid');
    if (uid != null && RegExp(r'^\d+$').hasMatch(uid)) {
      return '$_weiboMobile/u/$uid';
    }
    final nick = _param(query, 'nick');
    if (nick != null && nick.isNotEmpty) {
      return '$_weiboMobile/n/$nick';
    }
    return null;
  }
  return null;
}

/// 正文里的链接先翻成绝对地址：站内相对路径交给 WebView 会解析到 `file:///` 而失败。
String? resolveWeiboLink(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return null;
  final private = _weiboPrivateLink(url);
  if (private != null) return private;
  final lower = url.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) return url;
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return '$_weiboMobile$url';
  if (url.contains('://')) return null;
  return '$_weiboMobile/$url';
}

/// 微博把「评论配图」这类链接包成 `https://weibo.cn/sinaurl?u=<真实地址>`。
String? unwrapSinaUrl(String? raw) {
  if (raw == null) return null;
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
    final decoded = _decode(target);
    if (decoded.trim().isEmpty || decoded == url) break;
    url = decoded;
    changed = true;
  }
  return changed ? url : null;
}

/// `m.weibo.cn/n/<昵称>`、`/n/<昵称>` → 昵称（已解码）。
String? weiboMentionName(String raw) {
  var path = raw.trim().replaceAll('?', '\u0000');
  path = path.split('\u0000').first;
  final hash = path.indexOf('#');
  if (hash >= 0) path = path.substring(0, hash);
  final at = path.indexOf('/n/');
  if (at < 0) return null;
  final name = path.substring(at + 3).replaceAll(RegExp(r'^/+|/+$'), '');
  if (name.isEmpty || name.contains('/')) return null;
  return _decode(name);
}

/// `/u/<uid>`、`/profile/<uid>`、`m.weibo.cn/u/<uid>` → uid。
String? weiboUserId(String raw) {
  var path = raw.trim().split('?').first.split('#').first;
  for (final prefix in const ['/u/', '/profile/']) {
    final at = path.indexOf(prefix);
    if (at < 0) continue;
    final rest = path.substring(at + prefix.length);
    final id = rest.split('/').first;
    if (id.isNotEmpty && RegExp(r'^\d+$').hasMatch(id)) return id;
  }
  return null;
}

/// 图片直链（sinaimg 的 large/orj360/bmiddle 等），点了应该开图而不是开网页。
bool isImageLink(String raw) {
  var path = raw.trim().split('?').first.split('#').first.toLowerCase();
  if (!path.startsWith('http')) return false;
  return const ['.jpg', '.jpeg', '.png', '.gif', '.webp'].any(path.endsWith);
}

const _externalVideoHosts = <String>[
  'iqiyi.com',
  'v.qq.com',
  'bilibili.com',
  'b23.tv',
  'youku.com',
  'mgtv.com',
  'ixigua.com',
  'miaopai.com',
  'pearvideo.com',
  'acfun.cn',
  'le.com',
  'tv.sohu.com',
];

/// 视频直链、微博视频页或主流第三方视频官链。
bool isVideoLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('sinaweibo://video') ||
      lower.startsWith('intent://gotovideo')) {
    return true;
  }
  var path = lower.split('?').first.split('#').first;
  if (const ['.mp4', '.m4v', '.mov', '.webm', '.m3u8'].any(path.endsWith)) {
    return true;
  }
  final uri = Uri.tryParse(trimmed);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) return false;
  final uriPath = uri?.path.toLowerCase() ?? '';
  if (host == 'video.weibo.com' || host == 'h5.video.weibo.com') return true;
  if ((host == 'weibo.com' || host == 'www.weibo.com') &&
      uriPath.startsWith('/tv/')) {
    return true;
  }
  if (host == 'm.weibo.cn' &&
      (uriPath.startsWith('/s/video/') || uriPath.startsWith('/z/video/'))) {
    return true;
  }
  return _externalVideoHosts.any(
    (domain) => host == domain || host.endsWith('.$domain'),
  );
}

/// 单条微博链接里的 id：面板的「全文」和被分享的微博都靠它进详情页。
String? weiboStatusId(String raw) {
  var path = raw.trim().split('?').first.split('#').first;
  final scheme = path.indexOf('://');
  if (scheme >= 0) path = path.substring(scheme + 3);
  if (path.startsWith('//')) path = path.substring(2);
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty &&
      (segments.first.contains('.') || segments.first.contains(':'))) {
    segments.removeAt(0);
  }
  if (segments.length < 2) return null;
  final head = segments[0];
  final id = segments[1];
  if (head != 'status' && head != 'detail') return null;
  return RegExp(r'^\d+$').hasMatch(id) ? id : null;
}

/// 普通 `#话题#` 搜索链接 → 话题文本，超话（100808）返回 null。
String? weiboTopicQuery(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (superTopicId(trimmed) != null) return null;

  String wrapHash(String value) =>
      value.startsWith('#') && value.endsWith('#') ? value : '#$value#';

  final path = trimmed.split('?').first;
  final lowerPath = path.toLowerCase();

  final kIndex = lowerPath.indexOf('/k/');
  if (kIndex >= 0 &&
      (lowerPath.contains('weibo.cn') ||
          lowerPath.contains('weibo.com') ||
          lowerPath.startsWith('/k/'))) {
    final rawName = _decode(path.substring(kIndex + 3)).trim();
    if (rawName.isNotEmpty && !rawName.contains('/')) return wrapHash(rawName);
  }

  const sWeiboMarker = 's.weibo.com/weibo/';
  final sWeiboIndex = lowerPath.indexOf(sWeiboMarker);
  if (sWeiboIndex >= 0) {
    final rawSeg = _decode(
      path.substring(sWeiboIndex + sWeiboMarker.length),
    ).trim();
    if (rawSeg.isNotEmpty && !rawSeg.contains('/')) return wrapHash(rawSeg);
  }

  final questionAt = trimmed.indexOf('?');
  if (questionAt < 0) return null;
  var rawQuery = trimmed.substring(questionAt + 1);
  final intentAt = rawQuery.indexOf('#Intent');
  if (intentAt >= 0) rawQuery = rawQuery.substring(0, intentAt);
  if (rawQuery.isEmpty) return null;

  final cid = _param(rawQuery, 'containerid');
  if (cid != null) {
    final decodedCid = _decode(cid);
    if (decodedCid.startsWith('100103') || decodedCid.startsWith('231522')) {
      final cidQuery = decodedCid.contains('?')
          ? decodedCid.substring(decodedCid.indexOf('?') + 1)
          : decodedCid;
      for (final source in [cidQuery, rawQuery]) {
        for (final name in const ['q', 'extparam']) {
          final value = _param(source, name);
          if (value != null) {
            final decoded = _decode(value).trim();
            if (decoded.isNotEmpty) return decoded;
          }
        }
      }
    }
  }

  final looksLikeSearchHost =
      lowerPath.contains('/search') ||
      lowerPath.contains('s.weibo.com/weibo') ||
      lowerPath.startsWith('sinaweibo://searchall');
  if (looksLikeSearchHost) {
    for (final name in const ['q', 'extparam']) {
      final value = _param(rawQuery, name);
      if (value != null) {
        final decoded = _decode(value).trim();
        if (decoded.isNotEmpty) return decoded;
      }
    }
  }
  return null;
}

/// `http://t.cn/xxxx` 这类短链，点击时先探测目标地址再决定进哪个页面。
bool isWeiboShortLink(String raw) {
  final trimmed = raw.trim().toLowerCase();
  return trimmed.startsWith('http://t.cn/') ||
      trimmed.startsWith('https://t.cn/');
}

/// 微博小程序（wbox / 微服务）链接在网页端只会展示「打开微博客户端」引导页。
bool isWeiboWboxLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  return switch (scheme) {
    'https' || 'http' =>
      (host == 'm.weibo.cn' && (path == '/c/wbox' || path.startsWith('/c/wbox/'))) ||
          host == 'wbox.h5.weibo.cn',
    'sinaweibo' => host == 'wbox' || host == 'mpdialog',
    _ => false,
  };
}
