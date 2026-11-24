/// 本地存储：会话、多账号、草稿、浏览历史、收藏、关注标记、私信已读位置。
///
/// 对应 Kotlin 版 `data/Store.kt`：每个领域一个 JSON 文件，写入先落临时文件再改名，
/// 免得进程被杀时留下半截 JSON。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cookie_vault.dart';
import 'follow_tags.dart';
import 'models.dart';
import 'super_topic.dart';

class Store {
  Store._(this._dir);

  static Future<Store> open(Directory dir) async {
    final store = Store._(dir);
    await dir.create(recursive: true);
    return store;
  }

  final Directory _dir;

  File _file(String name) => File(p.join(_dir.path, name));

  Object? _readJson(String name) {
    final file = _file(name);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync());
    } on Object {
      return null;
    }
  }

  void _write(String name, Object value) {
    try {
      final file = _file(name);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(value));
      if (file.existsSync()) file.deleteSync();
      tmp.renameSync(file.path);
    } on Object {
      // 落盘失败只影响下次启动，不阻塞当前操作。
    }
  }

  List<Map<String, dynamic>> _readArray(String name) {
    final raw = _readJson(name);
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add({for (final e in item.entries) e.key.toString(): e.value});
      }
    }
    return out;
  }

  Map<String, dynamic> _readObject(String name) {
    final raw = _readJson(name);
    if (raw is! Map) return <String, dynamic>{};
    return {for (final e in raw.entries) e.key.toString(): e.value};
  }

  // ---- 会话 ----

  Session? session() {
    final o = _readObject('session.json');
    if (o.isEmpty) return null;
    final cookies = _cookieMap(o['cookies']);
    var cookie = o['cookie']?.toString() ?? '';
    if (cookie.isEmpty) {
      cookie = CookieVault.header(cookies, 'm.weibo.cn');
    }
    // 只有 SUB 在才算登录：服务端删掉 SUB 以后剩下的都是空壳。
    if (!cookie.contains('SUB=')) return null;
    return Session(
      cookie: cookie,
      uid: o['uid']?.toString() ?? '',
      savedAt: _toInt(o['savedAt']),
      gsid: o['gsid']?.toString() ?? '',
      gsidAt: _toInt(o['gsidAt']),
      accessToken: o['accessToken']?.toString() ?? '',
      expires: _toInt(o['expires']),
      source: o['source']?.toString() ?? 'web',
      loginType: o.containsKey('loginType')
          ? _toInt(o['loginType'])
          : ((o['gsid']?.toString() ?? '').isNotEmpty ? 4 : 1),
      cookies: cookies,
    );
  }

  void saveSession(String cookie, {
    String uid = '',
    Map<String, String>? cookies,
  }) {
    _write('session.json', {
      'source': 'web',
      'cookie': cookie,
      'uid': uid,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'loginType': 1,
      'cookies': cookies ?? CookieVault.seed(cookie),
    });
  }

  void saveClientSession({
    required String uid,
    required String gsid,
    required String cookie,
    required String accessToken,
    required int expires,
    Map<String, String>? cookies,
    int? gsidAt,
  }) {
    _write('session.json', {
      'source': 'client',
      'cookie': cookie,
      'uid': uid,
      'gsid': gsid,
      'gsidAt': gsidAt ?? DateTime.now().millisecondsSinceEpoch,
      'accessToken': accessToken,
      'expires': expires,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'loginType': 4,
      'cookies': cookies ?? CookieVault.seed(cookie),
    });
  }

  void updateClientSession({
    required String gsid,
    required String cookie,
    required String accessToken,
    required int expires,
    Map<String, String>? cookies,
  }) {
    final o = _readObject('session.json');
    if (o.isEmpty) return;
    o['source'] = 'client';
    o['cookie'] = cookie;
    o['cookies'] = cookies ?? CookieVault.seed(cookie);
    o['loginType'] = 4;
    if (gsid.isNotEmpty) o['gsid'] = gsid;
    o['gsidAt'] = DateTime.now().millisecondsSinceEpoch;
    if (accessToken.isNotEmpty) o['accessToken'] = accessToken;
    if (expires > 0) o['expires'] = expires;
    _write('session.json', o);
  }

  /// 只更新 cookie 表：网页端每次响应都可能滚动下发 `SUB` / `ALF`，收到就落盘。
  void updateCookies(Map<String, String> cookies) {
    final o = _readObject('session.json');
    if (o.isEmpty) return;
    final merged = <String, String>{..._cookieMap(o['cookies']), ...cookies};
    o['cookies'] = merged;
    o['cookie'] = CookieVault.header(merged, 'm.weibo.cn');
    o['savedAt'] = DateTime.now().millisecondsSinceEpoch;
    _write('session.json', o);
  }

  void clearSession() {
    final file = _file('session.json');
    if (file.existsSync()) file.deleteSync();
  }

  /// 容器接口的 `i` 参数：15 位设备号，第一次生成后一直复用。
  String deviceId() {
    final saved = _readObject('device.json')['i']?.toString() ?? '';
    if (saved.isNotEmpty) return saved;
    final suffix = 1000000000000 + (DateTime.now().microsecondsSinceEpoch % 8999999999999);
    final id = '86$suffix';
    _write('device.json', {'i': id});
    return id;
  }

  // ---- 访客身份 ----

  String? visitorCookie() {
    final cookie = _readObject('visitor.json')['cookie']?.toString() ?? '';
    return cookie.isEmpty ? null : cookie;
  }

  void saveVisitorCookie(String cookie) {
    _write('visitor.json', {
      'cookie': cookie,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---- 多账号 ----

  List<Account> accounts() {
    final out = <Account>[];
    for (final o in _readArray('accounts.json')) {
      final cookie = o['cookie']?.toString() ?? '';
      if (cookie.isEmpty) continue;
      out.add(
        Account(
          uid: o['uid']?.toString() ?? '',
          name: o['name']?.toString() ?? '',
          avatar: o['avatar']?.toString() ?? '',
          cookie: cookie,
          gsid: o['gsid']?.toString() ?? '',
          gsidAt: _toInt(o['gsidAt']),
        ),
      );
    }
    return out;
  }

  void saveAccount(Account account) {
    final existing = _readArray('accounts.json');
    final out = <Map<String, dynamic>>[
      {
        'uid': account.uid,
        'name': account.name,
        'avatar': account.avatar,
        'cookie': account.cookie,
        'gsid': account.gsid,
        'gsidAt': account.gsidAt,
      },
    ];
    for (final old in existing) {
      if (out.length >= 10) break;
      if (old['uid']?.toString() == account.uid) continue;
      out.add(old);
    }
    _write('accounts.json', out);
  }

  void removeAccount(String uid) {
    _write('accounts.json', [
      for (final o in _readArray('accounts.json'))
        if (o['uid']?.toString() != uid) o,
    ]);
  }

  // ---- 草稿 ----

  List<Draft> drafts() => [
    for (final o in _readArray('drafts.json'))
      Draft(o['text']?.toString() ?? '', _toInt(o['time'])),
  ];

  void addDraft(String text) {
    if (text.trim().isEmpty) return;
    final existing = _readArray('drafts.json');
    final out = <Map<String, dynamic>>[
      {'text': text, 'time': DateTime.now().millisecondsSinceEpoch},
    ];
    for (final o in existing) {
      if (out.length >= 50) break;
      if (o['text']?.toString() == text) continue;
      out.add(o);
    }
    _write('drafts.json', out);
  }

  void removeDraft(int time) {
    _write('drafts.json', [
      for (final o in _readArray('drafts.json'))
        if (_toInt(o['time']) != time) o,
    ]);
  }

  void clearDrafts() => _write('drafts.json', const <Object>[]);

  // ---- 浏览历史 ----

  List<HistoryItem> history() => [
    for (final o in _readArray('history.json'))
      HistoryItem(
        id: o['id']?.toString() ?? '',
        mid: o['mid']?.toString() ?? '',
        text: o['text']?.toString() ?? '',
        user: o['user']?.toString() ?? '',
        time: _toInt(o['time']),
        html: o['html']?.toString() ?? '',
      ),
  ];

  /// 记一条「点开过」的微博：正文用纯文本，html 留给详情页还原表情与链接。
  void addStatusHistory(Status status) {
    addHistory(
      HistoryItem(
        id: status.id,
        mid: status.mid,
        text: status.plainText,
        user: status.user?.name ?? '',
        time: DateTime.now().millisecondsSinceEpoch,
        html: status.textHtml,
      ),
    );
  }

  void addHistory(HistoryItem item) {
    final existing = _readArray('history.json');
    final out = <Map<String, dynamic>>[
      {
        'id': item.id,
        'mid': item.mid,
        'text': item.text,
        'user': item.user,
        'html': item.html,
        'time': DateTime.now().millisecondsSinceEpoch,
      },
    ];
    for (final o in existing) {
      if (out.length >= 100) break;
      if (o['id']?.toString() == item.id) continue;
      out.add(o);
    }
    _write('history.json', out);
  }

  void removeHistory(String id) {
    _write('history.json', [
      for (final o in _readArray('history.json'))
        if (o['id']?.toString() != id) o,
    ]);
  }

  void clearHistory() => _write('history.json', const <Object>[]);

  // ---- 收藏（全局一份，跨账号保留） ----

  List<Status> favorites() {
    final out = <Status>[];
    for (final o in _readArray('favorites.json')) {
      final status = Status.from(o);
      if (status == null) continue;
      out.add(status.favorited ? status : status.copyWith(favorited: true));
    }
    return out;
  }

  bool isFavorite(String id) {
    if (id.isEmpty) return false;
    return _readArray('favorites.json').any((o) => o['id']?.toString() == id);
  }

  void addFavorite(Status status) {
    if (status.id.isEmpty) return;
    final existing = _readArray('favorites.json');
    final out = <Map<String, dynamic>>[
      (status.favorited ? status : status.copyWith(favorited: true)).toJson(),
    ];
    for (final o in existing) {
      if (out.length >= 500) break;
      if (o['id']?.toString() == status.id) continue;
      out.add(o);
    }
    _write('favorites.json', out);
  }

  void removeFavorite(String id) {
    if (id.isEmpty) return;
    _write('favorites.json', [
      for (final o in _readArray('favorites.json'))
        if (o['id']?.toString() != id) o,
    ]);
  }

  bool toggleFavorite(Status status) {
    if (isFavorite(status.id)) {
      removeFavorite(status.id);
      return false;
    }
    addFavorite(status);
    return true;
  }

  // ---- 关注标记 ----

  Map<String, dynamic> _readFollowTags() => _readObject('follows.json');

  bool hasFollowTag(String uid) => _readFollowTags().containsKey(uid);

  FollowTag? followTag(String uid) =>
      FollowTag.of(_readFollowTags()[uid]?.toString());

  Map<String, FollowTag> followTags() {
    final out = <String, FollowTag>{};
    for (final entry in _readFollowTags().entries) {
      final tag = FollowTag.of(entry.value?.toString());
      if (tag != null) out[entry.key] = tag;
    }
    return out;
  }

  void setFollowTag(String uid, FollowTag? tag) {
    final o = _readFollowTags();
    o[uid] = tag?.key ?? '';
    _write('follows.json', o);
  }

  // ---- 最近访问的超话 ----

  List<SuperTopicSummary> recentSuperTopics() {
    final out = <SuperTopicSummary>[];
    for (final o in _readArray('super_topics.json')) {
      final item = SuperTopicSummary.fromJson(o);
      if (item != null) out.add(item);
    }
    return out;
  }

  void addRecentSuperTopic(SuperTopicSummary topic) {
    if (topic.containerId.isEmpty || topic.title.isEmpty) return;
    final existing = _readArray('super_topics.json');
    final out = <Map<String, dynamic>>[topic.toJson()];
    for (final o in existing) {
      if (out.length >= 30) break;
      if (o['containerId']?.toString().toLowerCase() ==
          topic.containerId.toLowerCase()) {
        continue;
      }
      out.add(o);
    }
    _write('super_topics.json', out);
  }

  void removeRecentSuperTopic(String containerId) {
    final lower = containerId.toLowerCase();
    _write('super_topics.json', [
      for (final o in _readArray('super_topics.json'))
        if (o['containerId']?.toString().toLowerCase() != lower) o,
    ]);
  }

  void clearRecentSuperTopics() => _write('super_topics.json', const <Object>[]);

  // ---- 私信已读 ----

  String chatSeen(String uid) => _readObject('chat-seen.json')[uid]?.toString() ?? '';

  void markChatSeen(String uid, String token) {
    if (uid.isEmpty || token.isEmpty) return;
    final o = _readObject('chat-seen.json');
    if (o[uid]?.toString() == token) return;
    o[uid] = token;
    _write('chat-seen.json', o);
  }

  static Map<String, String> _cookieMap(Object? raw) {
    if (raw is! Map) return <String, String>{};
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value?.toString() ?? '';
      if (value.isNotEmpty) out[entry.key.toString()] = value;
    }
    return out;
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
