/// 超话身份：只有 `100808` + 32 位十六进制才是超话容器，普通话题不要误判。
library;

final _superTopicContainer = RegExp(r'^100808[0-9a-fA-F]{32}$');

/// `100808..._-_feed` 这类带栏目标记的地址或 `1022:100808...` 形式的 oid 先剥掉前后缀再校验。
String? normalizedSuperTopicId(String value) {
  var base = value.trim();
  if (base.startsWith('1022:')) {
    base = base.substring('1022:'.length);
  }
  final split = base.indexOf('_-_');
  if (split > 0) {
    base = base.substring(0, split);
  }
  return _superTopicContainer.hasMatch(base) ? base.toLowerCase() : null;
}

/// 只认超话链接：容器串、`m.weibo.cn/p/index?containerid=`、`weibo.com/page/`、
/// `weibo.com/p/`、`sinaweibo://pageinfo`、`intent://pageinfo`。认不出来返回 null。
String? superTopicId(String raw) {
  final value = raw.trim();
  final direct = normalizedSuperTopicId(value);
  if (direct != null) return direct;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final path = uri.path;
  final desktopPage =
      (scheme == 'https' || scheme == 'http') &&
      (host == 'weibo.com' || host == 'www.weibo.com');
  String? desktopId;
  if (desktopPage) {
    if (path.startsWith('/page/')) {
      desktopId = normalizedSuperTopicId(path.substring('/page/'.length));
    } else if (path.startsWith('/p/')) {
      final tail = path.substring('/p/'.length).split('/').first;
      desktopId = normalizedSuperTopicId(tail);
    } else {
      return null;
    }
    if (desktopId == null) return null;
  }
  switch (scheme) {
    case 'https' || 'http':
      if (uri.hasFragment) return null;
      if (!desktopPage && (host != 'm.weibo.cn' || path != '/p/index')) {
        return null;
      }
    case 'sinaweibo':
      if (host != 'pageinfo' || path.isNotEmpty || uri.hasFragment) return null;
    case 'intent':
      if (host != 'pageinfo' || path.isNotEmpty) return null;
      final fragment = uri.hasFragment ? uri.fragment : null;
      if (fragment == null) return null;
      final parts = fragment.split(';');
      if (parts.isEmpty ||
          parts.first != 'Intent' ||
          parts.last != 'end' ||
          parts.where((p) => p == 'scheme=sinaweibo').length != 1 ||
          parts.any((p) => p.startsWith('scheme=') && p != 'scheme=sinaweibo')) {
        return null;
      }
    default:
      return null;
  }
  final ids = <String>[];
  for (final part in uri.query.split('&')) {
    if (part.isEmpty) continue;
    final index = part.indexOf('=');
    final key = index < 0 ? part : part.substring(0, index);
    final value = index < 0 ? '' : part.substring(index + 1);
    String decode(String text) {
      try {
        return Uri.decodeComponent(text);
      } on Object {
        return text;
      }
    }

    if (decode(key) == 'containerid') ids.add(decode(value));
  }
  if (desktopId != null) {
    if (ids.length > 1) return null;
    if (ids.isNotEmpty && normalizedSuperTopicId(ids.single) != desktopId) {
      return null;
    }
    return desktopId;
  }
  if (ids.length != 1) return null;
  return normalizedSuperTopicId(ids.single);
}
