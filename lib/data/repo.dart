/// 业务数据层：时间线、详情、评论、互动、发布、私信、用户、搜索、超话、投票。
///
/// 一对一翻译自 Kotlin 版 `data/Repo.kt`。接口地址、参数、分页游标、容错规则都保持一致；
/// 唯一的原则性差异是这里的「登录态续命」靠响应里的 `Set-Cookie`，不再有客户端容器登录。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'composer_models.dart';
import 'cookie_vault.dart';
import 'emotions.dart';
import 'follow_tags.dart';
import 'json.dart';
import 'like_gate.dart';
import 'links.dart';
import 'models.dart';
import 'settings.dart';
import 'store.dart';
import 'super_topic.dart';
import 'super_topic_id.dart';

const _stTtlMs = 10 * 60 * 1000;
const _webHeartbeatMs = 6 * 60 * 60 * 1000;
const _likeCooldownMs = 1500;
const _specialUidsTtlMs = 5 * 60 * 1000;
const _followGroupsTtlMs = 10 * 60 * 1000;
const _groupFeedPageSize = 25;
const _relationPageSize = 20;
const _specialScanPages = 4;
const _specialPageSize = 12;
const _specialDirectUsers = 5;
const _specialRefreshBudgetMs = 15000;
const _visitorRetryMs = 60000;
const _tagFeedConcurrency = 4;
const _tagFeedPageSize = 20;
const _tagFeedCatchupRounds = 3;
const _tagCursorEnd = '';

const _guestBlocked = '纯本地模式看不了这里，登录后可用';
const _loginRequired = '纯本地模式不能这样操作，登录后可用';

/// 收藏的写接口在 weibo.com 的 ajax 上，不在 m.weibo.cn：
/// `m.weibo.cn/api/favorites/create|destroy` 一律 404（Cobo 1.1.19 当年撞的就是这堵墙）。
/// `destoryFavorites` 的拼写是微博自己写错的，改成「正确」的反而 404。
const _favoriteCreateUrl = 'https://weibo.com/ajax/statuses/createFavorites';
const _favoriteDestroyUrl = 'https://weibo.com/ajax/statuses/destoryFavorites';

/// 这两个接口按来源页校验，`weibo.com/` 不够，必须是收藏页。
const _favoriteReferer = 'https://weibo.com/fav';

/// m.weibo.cn「我的收藏」容器：网页版 / 官方客户端里真正收藏过的微博。
/// 收藏列表：`containerid=230267` 实测只回「这里还没有内容」，现在走 weibo.com 的 ajax。
const _favoriteListUrl = 'https://weibo.com/ajax/favorites/all_fav';

/// 收藏夹一页固定 20 条，拿满就说明后面还有。
const _favoritePageSize = 20;

/// 「收藏」按钮的结果：[favorited] 是本地状态，[syncError] 非空说明微博收藏夹那次没写成功。
class FavoriteToggle {
  const FavoriteToggle(this.favorited, [this.syncError]);

  final bool favorited;
  final String? syncError;
}

/// 微博搜索结果的排序：综合 `type=1`、实时 `type=61`、热门 `type=60`。
enum SearchSort {
  comprehensive('综合', 1),
  latest('最新', 61),
  hot('最热', 60);

  const SearchSort(this.label, this.type);

  final String label;
  final int type;
}

/// 话题详情页顶部分类标签，对应搜索频道 `100103type=X`。
enum TopicChannel {
  comprehensive('综合', 1),
  latest('实时', 61),
  pictures('图片', 63),
  videos('视频', 64),
  following('关注', 62),
  hot('热门', 60);

  const TopicChannel(this.label, this.type);

  final String label;
  final int type;
}

/// 「本地关注」的翻页游标：uid → 这个人翻到的 since_id，空串表示没有更早的微博了。
String encodeTagCursor(Map<String, String> next) => jsonEncode(next);

Map<String, String> parseTagCursor(String? cursor) {
  if (cursor == null || cursor.isEmpty) return const {};
  try {
    final decoded = jsonDecode(cursor);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  } on Object {
    return const {};
  }
}

class Repo extends ChangeNotifier {
  Repo({
    required this.store,
    required this.settings,
    required this.followTags,
  }) {
    session = store.session();
    visitorCookie = store.visitorCookie();
    for (final status in store.favorites()) {
      localFavoriteIds[status.id] = true;
    }
    Api.cookieSink = _absorbCookies;
  }

  final Store store;
  final Settings settings;
  final FollowTags followTags;

  Session? session;
  Config? _cachedConfig;
  String? _configCookie;
  int _cachedConfigAt = 0;

  /// 访客 cookie：没登录时所有只读请求都带它。
  String? visitorCookie;
  int _visitorAt = 0;
  Future<String>? _visitorPending;

  /// 全局本地收藏状态：跨账号与纯本地模式共用，切号与登出都保留。
  final Map<String, bool> localFavoriteIds = {};
  int favoritesVersion = 0;

  /// 微博收藏夹那一侧的版本号：每写成功一次 +1，收藏页据此强制重拉。
  int onlineFavoritesVersion = 0;

  final Map<String, bool> deletedStatusIds = {};
  int deletedVersion = 0;

  String? _avatarCacheKey;
  String _avatarCache = '';

  List<EmojiSection> _cachedEmotionSections = const [];
  String? _cachedEmotionCookie;
  List<User> _cachedMentionFriends = const [];
  String? _cachedMentionUid;
  List<TopicSuggestion> _cachedHotspotTopics = const [];

  List<FollowGroup> _cachedFollowGroups = const [];
  int _cachedFollowGroupsAt = 0;
  Set<String> _specialUids = const {};
  int _specialUidsAt = 0;

  final Map<String, VoteInfo> _voteCache = {};
  final Map<String, String> _statusVoteIdCache = {};
  final Map<String, String> _uidByNameCache = {};
  final Map<String, int> _likeBusy = {};

  /// 点赞被服务端限流后的退避闸门，见 [LikeGate]。
  final _likeGate = LikeGate();

  /// 刚被微博限流过、还在冷却期。界面据此直接提示，不再走「先点亮再回弹」。
  bool get likeBlocked => _likeGate.blocked;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    Api.cookieSink = null;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 读数据用的 cookie：登录了就是账号的，纯本地模式下是访客的。
  String? cookie() => session?.cookie ?? visitorCookie;

  bool hasSession() => session?.loggedIn == true;

  /// 纯本地模式：没有登录账号，只读浏览。
  bool get guest => !hasSession();

  bool isFavorited(String id) => id.isNotEmpty && localFavoriteIds[id] == true;

  bool isDeleted(String id) => id.isNotEmpty && deletedStatusIds[id] == true;

  bool toggleLocalFavorite(Status status) {
    final nowFavorited = store.toggleFavorite(status);
    if (nowFavorited) {
      localFavoriteIds[status.id] = true;
    } else {
      localFavoriteIds.remove(status.id);
    }
    favoritesVersion++;
    _notify();
    return nowFavorited;
  }

  String _loginCookie() {
    final active = session;
    if (active == null || !active.loggedIn) throw ApiException(_loginRequired);
    return active.cookie;
  }

  /// 只读请求的统一入口：纯本地模式下换访客 cookie，被拒（HTTP 432 / `ok:-100`）重领一次。
  Future<Map<String, dynamic>> _get(
    String url,
    String? cookie, {
    bool force = false,
  }) async {
    final active = session;
    if (active != null || (cookie != null && cookie != visitorCookie)) {
      return Api.get(url, cookie, force: force);
    }
    final first = cookie ?? await _visitorFor(null);
    Map<String, dynamic>? root;
    try {
      root = await Api.get(url, first, force: force);
    } on ApiHttpException catch (e) {
      if (e.code != 432) rethrow;
      root = null;
    }
    if (root != null && root.intOf('ok', 1) != -100) return root;
    final fresh = await _visitorFor(first);
    if (fresh == first) throw ApiException(_guestBlocked);
    final retry = await Api.get(url, fresh, force: true);
    if (retry.intOf('ok', 1) == -100) throw ApiException(_guestBlocked);
    return retry;
  }

  Future<String> _visitorFor(String? stale) {
    final pending = _visitorPending;
    if (pending != null) return pending;
    final current = visitorCookie;
    if (current != null && current != stale) return Future.value(current);
    if (current != null &&
        DateTime.now().millisecondsSinceEpoch - _visitorAt < _visitorRetryMs) {
      return Future.value(current);
    }
    final future = () async {
      try {
        final fresh = await Api.genVisitor();
        store.saveVisitorCookie(fresh);
        visitorCookie = fresh;
        _visitorAt = DateTime.now().millisecondsSinceEpoch;
        return fresh;
      } finally {
        _visitorPending = null;
      }
    }();
    _visitorPending = future;
    return future;
  }

  /// 把响应里的 `Set-Cookie` 合进当前会话；纯本地模式下落到访客 cookie 上。
  void _absorbCookies(Uri url, List<String> setCookies) {
    if (setCookies.isEmpty) return;
    final active = session;
    if (active == null) {
      final seed = CookieVault.seed(visitorCookie ?? '', '.${url.host}');
      final merged = CookieVault.absorb(seed, url, setCookies);
      final header = CookieVault.header(merged, 'm.weibo.cn');
      if (header.isEmpty || header == visitorCookie) return;
      visitorCookie = header;
      store.saveVisitorCookie(header);
      return;
    }
    final base = active.cookies.isEmpty
        ? CookieVault.seed(active.cookie)
        : active.cookies;
    final merged = CookieVault.absorb(base, url, setCookies);
    if (mapEquals(merged, base)) return;
    store.updateCookies(merged);
    final header = CookieVault.header(merged, 'm.weibo.cn');
    if (!header.contains('SUB=')) {
      // 服务端把 SUB 删了就是这个账号被登出了，内存里也立刻降级。
      session = null;
      _notify();
      return;
    }
    session = active.copyWith(
      cookies: merged,
      cookie: header.isEmpty ? active.cookie : header,
    );
    _clearAccountScopedCaches();
    _notify();
  }

  Future<void> injectCookies([Map<String, String>? cookies]) async {
    final table = cookies ?? session?.cookies ?? const <String, String>{};
    if (table.isEmpty) return;
    await CookieVault.inject(table);
  }

  void _clearAccountScopedCaches() {
    _cachedConfig = null;
    _configCookie = null;
    _cachedConfigAt = 0;
    _cachedEmotionSections = const [];
    _cachedEmotionCookie = null;
    _cachedMentionFriends = const [];
    _cachedMentionUid = null;
    _cachedHotspotTopics = const [];
  }

  Future<Config> _configFor(String cookie, {bool force = false}) async {
    final fresh =
        DateTime.now().millisecondsSinceEpoch - _cachedConfigAt < _stTtlMs;
    final cached = _cachedConfig;
    if (!force && fresh && cached != null && _configCookie == cookie) {
      return cached;
    }
    final root = await Api.get(
      'https://m.weibo.cn/api/config',
      cookie,
      force: true,
    );
    final data = root.obj('data');
    final config = Config(
      data?.str('uid') ?? '',
      data?.str('st') ?? '',
      data?.boolean('login') == true || (data?.str('uid') ?? '').isNotEmpty,
    );
    _cachedConfig = config;
    _configCookie = cookie;
    _cachedConfigAt = DateTime.now().millisecondsSinceEpoch;
    return config;
  }

  Future<Config> config({bool force = false}) async {
    final cookie = session?.cookie;
    if (cookie == null) return Config.empty;
    return _configFor(cookie, force: force);
  }

  Future<String> st() async => (await config()).st;

  Future<Account?> loginWithCookie(
    String cookie, {
    Map<String, String>? cookies,
  }) async {
    final cfg = await _configFor(cookie, force: true);
    if (!cfg.loggedIn || cfg.uid.isEmpty) return null;
    User? user;
    try {
      user = await profileFor(cookie, cfg.uid, force: true);
    } on Object {
      user = null;
    }
    await resetAccountCaches();
    settings.applyLocalMode(false);
    store.saveSession(cookie, uid: cfg.uid, cookies: cookies);
    final saved = CookieVault.seed(cookie);
    store.saveSession(
      cookie,
      uid: cfg.uid,
      cookies: cookies ?? saved,
    );
    session = store.session();
    _cachedConfig = cfg;
    _configCookie = cookie;
    _cachedConfigAt = DateTime.now().millisecondsSinceEpoch;
    await injectCookies(session?.cookies);
    final account = Account(
      uid: cfg.uid,
      name: user?.name ?? '',
      avatar: user?.avatar ?? '',
      cookie: cookie,
    );
    store.saveAccount(account);
    _notify();
    return account;
  }

  /// 冷启动时顺手续一次网页登录态：像浏览器一样真的打开一次页面，让微博重发 `SUB`。
  Future<void> refreshSessionIfStale() async {
    final active = session;
    if (active == null) return;
    if (active.loggedIn &&
        DateTime.now().millisecondsSinceEpoch - active.savedAt >
            _webHeartbeatMs) {
      try {
        await Api.getHtml('https://m.weibo.cn/', active.cookie);
      } on Object {
        // 心跳失败不影响使用。
      }
    }
    await injectCookies(session?.cookies);
  }

  Future<void> enterLocalMode() async {
    settings.applyLocalMode(true);
    await visitorForStartup();
  }

  /// 纯本地模式下尽量先领一个访客身份，首页才不会一路 432。
  Future<void> visitorForStartup() async {
    try {
      await _visitorFor(null);
    } on Object {
      // 领不到就等首次请求时再试。
    }
  }

  Future<void> resetAccountCaches({
    bool clearSnapshotsAndScrolls = false,
  }) async {
    Api.cache?.clear();
    if (clearSnapshotsAndScrolls) {
      settings.clearFeedScrolls();
    }
    settings.clearGroupFeedTab();
    _avatarCacheKey = null;
    _avatarCache = '';
    _cachedFollowGroups = const [];
    _cachedFollowGroupsAt = 0;
    _specialUids = const {};
    _specialUidsAt = 0;
    _cachedConfig = null;
    _configCookie = null;
    _cachedConfigAt = 0;
    _cachedEmotionSections = const [];
    _cachedEmotionCookie = null;
    _cachedMentionFriends = const [];
    _cachedMentionUid = null;
    _cachedHotspotTopics = const [];
    _voteCache.clear();
    _statusVoteIdCache.clear();
  }

  Future<void> updateSession(String cookie, String uid) async {
    await resetAccountCaches();
    settings.applyLocalMode(false);
    store.saveSession(cookie, uid: uid);
    session = store.session();
    _notify();
  }

  Future<void> switchAccount(Account account) async {
    await resetAccountCaches();
    settings.applyLocalMode(false);
    store.saveSession(account.cookie, uid: account.uid);
    session = store.session();
    _notify();
  }

  Future<void> logout() async {
    await resetAccountCaches(clearSnapshotsAndScrolls: true);
    store.clearSession();
    session = null;
    _notify();
  }

  // ---- 时间线 ----

  Future<FeedPage> container(
    String cid, {
    String? sinceId,
    Map<String, String> extra = const {},
    bool force = false,
    String? cookie,
  }) async {
    final params = <String, String?>{
      'containerid': cid,
      if (sinceId != null && sinceId.isNotEmpty) 'since_id': sinceId,
      ...extra,
    };
    final root = await _get(
      Api.url('https://m.weibo.cn/api/container/getIndex', params),
      cookie ?? this.cookie(),
      force: force,
    );
    final page = parseCards(root);
    if (page.items.isEmpty && root.intOf('ok', 1) != 1) {
      final message = root.str('msg', '加载失败');
      if (message.contains('还没有内容') || message.contains('暂无')) {
        return const FeedPage([], null);
      }
      throw ApiException(message);
    }
    return page;
  }

  /// 「关注」流：走 `/feed/friends`，游标是 `max_id`。
  Future<FeedPage> friends({String? maxId, bool force = false}) =>
      _statusFeed('https://m.weibo.cn/feed/friends', maxId, force);

  Future<FeedPage> circle({String? maxId, bool force = false}) =>
      _statusFeed('https://m.weibo.cn/feed/circle', maxId, force);

  Future<FeedPage> special({String? maxId, bool force = false}) async {
    final uids = <String>{
      ...await _specialFollowUids(force),
      ...followTags.uids(FollowTag.special),
    };
    return _byUsers(uids, maxId, force);
  }

  Future<FeedPage> secret({String? maxId, bool force = false}) =>
      _byUsers(followTags.uids(FollowTag.secret).toSet(), maxId, force);

  Future<FeedPage> _statusFeed(
    String base,
    String? maxId,
    bool force, {
    String? cookie,
    Map<String, String?> extra = const {},
  }) async {
    final params = <String, String?>{
      if (maxId != null && maxId.isNotEmpty) 'max_id': maxId,
      ...extra,
    };
    final root = await _get(
      Api.url(base, params),
      cookie ?? this.cookie(),
      force: force,
    );
    final data = root.obj('data');
    if (data == null) {
      if (root.intOf('ok', 1) == 1) return const FeedPage([], null);
      final message = root.str('msg', '加载失败');
      if (message.contains('还没有内容') || message.contains('暂无')) {
        return const FeedPage([], null);
      }
      throw ApiException(message);
    }
    final arr = data.arr('statuses');
    final items = statusesOf(arr);
    final next = _firstNonEmpty([data.str('max_id'), data.str('since_id')]);
    return FeedPage(items, next.isEmpty ? null : next);
  }

  /// 账号里的自建关注分组（网页版 `ajax/feed/allGroups`）。
  Future<List<FollowGroup>> followGroups({bool force = false}) async {
    if (guest) return const [];
    final fresh =
        DateTime.now().millisecondsSinceEpoch - _cachedFollowGroupsAt <
        _followGroupsTtlMs;
    if (!force && fresh) return _cachedFollowGroups;
    final root = await Api.getDesktop(
      Api.url(
        'https://weibo.com/ajax/feed/allGroups',
        const {'is_new_segment': '1', 'fetch_hot': '1'},
      ),
      cookie(),
    );
    final groups = parseFollowGroups(root);
    _cachedFollowGroups = groups;
    _cachedFollowGroupsAt = DateTime.now().millisecondsSinceEpoch;
    return groups;
  }

  /// 某个关注分组的时间线（网页版 `ajax/feed/groupstimeline`）。
  Future<FeedPage> groupFeed(String gid, {String? maxId}) async {
    if (gid.isEmpty) return const FeedPage([], null);
    final params = <String, String?>{
      'list_id': gid,
      'refresh': '4',
      'fast_refresh': '1',
      'count': '$_groupFeedPageSize',
      if (maxId != null && maxId.isNotEmpty) 'max_id': maxId,
    };
    final Map<String, dynamic> root;
    try {
      root = await Api.getDesktop(
        Api.url('https://weibo.com/ajax/feed/groupstimeline', params),
        cookie(),
      );
    } on ApiHttpException catch (e) {
      if (e.body.contains('列表不存在')) {
        throw ApiException('这个分组已经不存在了，在「更多」里换一个');
      }
      rethrow;
    }
    final items = statusesOf(root.arr('statuses'));
    if (items.isEmpty && root.intOf('ok', 1) != 1) {
      final message = _firstNonEmpty([
        root.str('msg'),
        root.str('message'),
        '加载失败',
      ]);
      if (message.contains('还没有') || message.contains('暂无')) {
        return const FeedPage([], null);
      }
      throw ApiException(message);
    }
    final cursor = _firstNonEmpty([
      root.str('max_id'),
      root.obj('data')?.str('since_id') ?? '',
    ]);
    return FeedPage(
      items,
      cursor.isEmpty || cursor == '0' ? null : cursor,
    );
  }

  /// 「本地关注」：把本机打了「本地」标记的人的主页时间线合并成一条能一直往下翻的流。
  Future<FeedPage> localFollows({String? maxId, bool force = false}) async {
    final uids = followTags.uids(FollowTag.local);
    if (uids.isEmpty) return const FeedPage([], null);
    final activeCookie = _localFollowCookie();
    final positions = parseTagCursor(maxId);
    final deadline = DateTime.now().millisecondsSinceEpoch +
        _specialRefreshBudgetMs;
    final fetched = <String, List<Status>>{};
    final pending = <String, String?>{};
    final done = <String>{};
    for (final uid in uids) {
      if (positions[uid] == _tagCursorEnd) {
        done.add(uid);
      } else {
        pending[uid] = positions[uid];
      }
    }

    Future<void> pull(List<String> targets) async {
      for (var i = 0; i < targets.length; i += _tagFeedConcurrency) {
        if (DateTime.now().millisecondsSinceEpoch > deadline) break;
        final slice = targets.skip(i).take(_tagFeedConcurrency).toList();
        await Future.wait([
          for (final uid in slice)
            () async {
              final since = pending[uid];
              FeedPage page;
              try {
                page = await container(
                  '107603$uid',
                  sinceId: since,
                  force: force,
                  cookie: activeCookie,
                );
              } on Object {
                return;
              }
              final cutoff = int.tryParse(since ?? '');
              final items = cutoff == null
                  ? page.items
                  : page.items
                        .where(
                          (s) =>
                              (int.tryParse(s.id) ?? -9223372036854775808) <
                              cutoff,
                        )
                        .toList();
              fetched.putIfAbsent(uid, () => []).addAll(items);
              if (page.sinceId == null || page.sinceId!.isEmpty) {
                done.add(uid);
                pending.remove(uid);
              } else {
                pending[uid] = page.sinceId;
              }
            }(),
        ]);
      }
    }

    final alive = uids.where((uid) => !done.contains(uid)).toList();
    await pull(alive);
    for (var round = 1; round < _tagFeedCatchupRounds; round++) {
      final cut = _tagFeedCut(fetched, _tagFeedPageSize);
      if (cut == null) break;
      final behind = alive.where((uid) {
        if (done.contains(uid)) return false;
        final oldest = _oldestStatusId(fetched[uid]) ?? 9223372036854775807;
        return oldest > cut;
      }).toList();
      if (behind.isEmpty) break;
      await pull(behind);
    }

    final merged = <String, (Status, String)>{};
    for (final entry in fetched.entries) {
      for (final status in entry.value) {
        merged.putIfAbsent(status.id, () => (status, entry.key));
      }
    }
    final ordered = merged.values.toList()
      ..sort(
        (a, b) =>
            (int.tryParse(b.$1.id) ?? 0).compareTo(int.tryParse(a.$1.id) ?? 0),
      );
    final page = ordered.take(_tagFeedPageSize).toList();
    if (page.isEmpty) return const FeedPage([], null);

    final emittedOldest = <String, String>{};
    final emittedCount = <String, int>{};
    for (final (status, uid) in page) {
      emittedOldest[uid] = status.id;
      emittedCount[uid] = (emittedCount[uid] ?? 0) + 1;
    }
    final cursor = <String, String>{};
    for (final uid in uids) {
      final total = fetched[uid]?.length ?? 0;
      final sent = emittedCount[uid] ?? 0;
      final oldest = emittedOldest[uid];
      final old = positions[uid];
      if (done.contains(uid) && sent == total) {
        cursor[uid] = _tagCursorEnd;
      } else if (oldest != null) {
        cursor[uid] = oldest;
      } else if (old != null) {
        cursor[uid] = old;
      }
    }
    return FeedPage(
      page.map((entry) => entry.$1).toList(),
      encodeTagCursor(cursor),
    );
  }

  String? _localFollowCookie() {
    if (guest) return cookie();
    final selected = settings.localFollowUid;
    if (selected.isEmpty) return cookie();
    for (final account in store.accounts()) {
      if (account.uid == selected && account.cookie.isNotEmpty) {
        return account.cookie;
      }
    }
    return cookie();
  }

  /// 把一组人的微博拼成一条流：先扫关注流，再补各自的主页时间线。
  Future<FeedPage> _byUsers(
    Set<String> uids,
    String? maxId,
    bool force, {
    String? cookie,
  }) async {
    if (uids.isEmpty) return const FeedPage([], null);
    final kept = <String, Status>{};
    var cursor = maxId;
    var scanned = 0;
    final deadline = DateTime.now().millisecondsSinceEpoch +
        _specialRefreshBudgetMs;
    while (scanned < _specialScanPages && kept.length < _specialPageSize) {
      if (scanned > 0 && DateTime.now().millisecondsSinceEpoch > deadline) {
        break;
      }
      final page = await _statusFeed(
        'https://m.weibo.cn/feed/friends',
        cursor,
        force,
        cookie: cookie ?? this.cookie(),
      );
      scanned++;
      for (final status in page.items) {
        final user = status.user;
        if (user == null) continue;
        if (uids.contains(user.id)) kept[status.id] = status;
      }
      cursor = page.sinceId;
      if (cursor == null || cursor.isEmpty) break;
    }
    if (kept.length < _specialPageSize) {
      for (final uid in uids.take(_specialDirectUsers)) {
        if (DateTime.now().millisecondsSinceEpoch > deadline) break;
        try {
          final page = await container(
            '107603$uid',
            force: force,
            cookie: cookie ?? this.cookie(),
          );
          for (final status in page.items) {
            kept.putIfAbsent(status.id, () => status);
          }
        } on Object {
          continue;
        }
      }
    }
    final items = kept.values.toList()
      ..sort(
        (a, b) =>
            (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0),
      );
    return FeedPage(items.take(_specialPageSize * 2).toList(), null);
  }

  /// 特别关注名单：weibo.com 分组表里「特别关注」那一组。
  Future<Set<String>> _specialFollowUids(bool force) async {
    final fresh =
        DateTime.now().millisecondsSinceEpoch - _specialUidsAt <
        _specialUidsTtlMs;
    if (!force && fresh) return _specialUids;
    final ids = <String>{};
    String? gid;
    try {
      gid = await _specialGroupId();
    } on Object {
      gid = null;
    }
    if (gid != null && gid.isNotEmpty) {
      try {
        final root = await _get(
          Api.url(
            'https://m.weibo.cn/api/container/getIndex',
            {'containerid': '231093_-_selfgroupfollow_-_$gid', 'page': '1'},
          ),
          cookie(),
          force: force,
        );
        _collectUserIds(root, ids);
      } on Object {
        // 名单接口挂了还有下面的兜底。
      }
      if (ids.isEmpty) {
        try {
          final root = await Api.getDesktop(
            'https://weibo.com/ajax/feed/groupstimeline?list_id=$gid',
            cookie(),
          );
          for (final item in root.arr('statuses') ?? const []) {
            final uid = jObj(item)?.obj('user')?.str('id') ?? '';
            if (uid.isNotEmpty) ids.add(uid);
          }
        } on Object {
          // 同上。
        }
      }
    }
    _specialUids = ids;
    _specialUidsAt = DateTime.now().millisecondsSinceEpoch;
    return ids;
  }

  Future<String?> _specialGroupId() async {
    final root = await Api.getDesktop(
      'https://weibo.com/ajax/feed/allGroups',
      cookie(),
    );
    for (final category in root.arr('groups') ?? const []) {
      final items = jObj(category)?.arr('group');
      if (items == null) continue;
      for (final item in items) {
        final o = jObj(item);
        if (o == null) continue;
        if (o.str('title') == '特别关注') {
          final gid = o.str('gid');
          if (gid.isNotEmpty) return gid;
        }
      }
    }
    return null;
  }

  void _collectUserIds(Object? node, Set<String> into) {
    if (node is Map) {
      final o = jObj(node);
      if (o != null) {
        final uid = o.obj('user')?.str('id') ?? '';
        if (uid.isNotEmpty) into.add(uid);
        for (final entry in o.entries) {
          if (entry.key == 'user') continue;
          _collectUserIds(entry.value, into);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _collectUserIds(item, into);
      }
    }
  }

  Future<List<HotItem>> hot({
    HotBoard board = HotBoard.realtime,
    bool force = false,
  }) async {
    final cid =
        '106003type=25&t=3&disable_hot=1&filter_type=${board.filterType}';
    final root = await _get(
      Api.url(
        'https://m.weibo.cn/api/container/getIndex',
        {'containerid': cid},
      ),
      cookie(),
      force: force,
    );
    return parseHotItems(root);
  }

  /// 搜索联想词：接口要 `X-XSRF-TOKEN` 与 cookie 配套，不带令牌只会回「请求失败」。
  Future<List<String>> suggest(String keyword) async {
    final url = Api.url(
      'https://m.weibo.cn/api/search/suggest',
      {'keyword': keyword},
    );
    var activeCookie = cookie();
    if (activeCookie == null) return const [];
    var st = (await _configFor(activeCookie)).st;
    Map<String, dynamic>? data;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      try {
        data = (await Api.getWithSt(url, activeCookie, st)).obj('data');
        if (data != null) break;
      } on ApiHttpException catch (e) {
        if (e.code != 432 || session != null) return const [];
        activeCookie = await _visitorFor(activeCookie);
        st = (await _configFor(activeCookie, force: true)).st;
      }
    }
    final arr = data?.arr('suggestion');
    if (arr == null) return const [];
    final out = <String>[];
    for (final item in arr) {
      final text = jObj(item)?.str('suggestion') ?? '';
      if (text.isNotEmpty && !out.contains(text)) out.add(text);
    }
    return out;
  }

  Future<SuperTopicPage> superTopic(
    String containerId, {
    String? sinceId,
  }) async {
    final id = superTopicId(containerId);
    if (id == null) throw ApiException('无效的超话地址');
    final cursor = (sinceId ?? '').isEmpty ? null : sinceId;
    if (cursor != null && !RegExp(r'^\d+$').hasMatch(cursor)) {
      throw ApiException('无效的超话翻页参数');
    }
    return superTopicTab(id, '${id}_-_feed', cursor: cursor);
  }

  Future<SuperTopicPage> superTopicTab(
    String baseContainerId,
    String tabContainerId, {
    String? cursor,
  }) async {
    final id = superTopicId(baseContainerId);
    if (id == null) throw ApiException('无效的超话地址');
    if (!hasSession()) throw ApiException('超话需要登录后查看', '-100');
    final trimmed = tabContainerId.trim();
    final tabId = trimmed.toLowerCase().startsWith(id)
        ? trimmed
        : '${id}_-_feed';
    final pageCursor = (cursor ?? '').isEmpty ? null : cursor;
    final int? pageNumber;
    if (pageCursor != null && pageCursor.startsWith('page:')) {
      final parsed = int.tryParse(pageCursor.substring(5));
      pageNumber = (parsed ?? 1) < 2 ? 2 : parsed;
      if (parsed == null) throw ApiException('无效的超话翻页参数');
    } else {
      pageNumber = null;
    }
    final params = <String, String?>{
      'containerid': tabId,
      if (pageNumber != null) 'page': '$pageNumber' else 'since_id': pageCursor,
    };
    final Map<String, dynamic> root;
    try {
      root = await _get(
        Api.url('https://m.weibo.cn/api/container/getIndex', params),
        _loginCookie(),
        force: true,
      );
    } on ApiHttpException catch (e) {
      if (e.code == 432) throw ApiException('超话需要登录后查看', '432');
      throw ApiException('超话加载失败（HTTP ${e.code}）');
    } on ApiException catch (e) {
      if (e.errno == '-100' || e.message == _guestBlocked) {
        throw ApiException('超话需要登录后查看', '-100');
      }
      throw ApiException('超话加载失败');
    }
    final page = tabId.toLowerCase() == '${id}_-_feed'
        ? parseSuperTopicPage(root, id)
        : parseSuperTopicPage(
            root,
            id,
            tabContainerId: tabId,
            currentPage: pageNumber ?? 1,
          );
    if (tabId.toLowerCase().endsWith('_-_video') && page.items.isNotEmpty) {
      return _hydrateSuperTopicVideos(page);
    }
    return page;
  }

  /// 超话「视频」流的卡片缺头图与可播放地址，按 mid 并发补全完整微博。
  Future<SuperTopicPage> _hydrateSuperTopicVideos(SuperTopicPage page) async {
    final hydrated = <Status>[];
    for (var i = 0; i < page.items.length; i += 6) {
      final slice = page.items.skip(i).take(6);
      final results = await Future.wait([
        for (final item in slice)
          () async {
            if (item.video != null && (item.user?.avatar ?? '').isNotEmpty) {
              return item;
            }
            try {
              return await detail(item.id) ?? item;
            } on Object {
              return item;
            }
          }(),
      ]);
      hydrated.addAll(results);
    }
    return SuperTopicPage(
      info: page.info,
      items: hydrated,
      nextCursor: page.nextCursor,
      tabs: page.tabs,
    );
  }

  /// 我关注的超话列表：优先 m.weibo.cn 容器 `100803_-_followsuper`，
  /// 首页为空或失败时回退到桌面端 `ajax/profile/topicContent`。
  Future<SuperTopicListPage> followedSuperTopics({
    String? cursor,
    bool force = false,
  }) async {
    if (!hasSession()) throw ApiException('超话需要登录后查看', '-100');
    final trimmed = (cursor ?? '').trim();
    if (trimmed.startsWith('desktop:')) {
      final page = int.tryParse(trimmed.substring('desktop:'.length)) ?? 2;
      return _followedSuperTopicsDesktop(page: page);
    }
    final int? pageNumber = trimmed.startsWith('page:')
        ? (int.tryParse(trimmed.substring('page:'.length)) ?? 2)
        : null;
    final params = <String, String?>{
      'containerid': '100803_-_followsuper',
      if (pageNumber != null)
        'page': '$pageNumber'
      else if (trimmed.isNotEmpty)
        'since_id': trimmed,
    };
    try {
      final root = await _get(
        Api.url('https://m.weibo.cn/api/container/getIndex', params),
        _loginCookie(),
        force: force,
      );
      final parsed = parseSuperTopicList(root, currentPage: pageNumber ?? 1);
      if (parsed.items.isNotEmpty || trimmed.isNotEmpty) return parsed;
    } on ApiException catch (e) {
      if (e.errno == '-100' || e.errno == '432') rethrow;
      if (trimmed.isNotEmpty) rethrow;
    } on Object {
      if (trimmed.isNotEmpty) rethrow;
    }
    return _followedSuperTopicsDesktop(page: 1);
  }

  Future<SuperTopicListPage> _followedSuperTopicsDesktop({
    required int page,
  }) async {
    final root = await Api.getDesktop(
      Api.url('https://weibo.com/ajax/profile/topicContent', {
        'tabid': '231093_-_chaohua',
        'page': '$page',
      }),
      _loginCookie(),
    );
    final parsed = parseSuperTopicList(root, currentPage: page);
    final next = parsed.nextCursor != null ? 'desktop:${page + 1}' : null;
    return SuperTopicListPage(items: parsed.items, nextCursor: next);
  }

  /// 超话广场 / 热门超话。
  Future<SuperTopicListPage> hotSuperTopics({
    String? cursor,
    bool force = false,
  }) async {
    final trimmed = (cursor ?? '').trim();
    final int? pageNumber = trimmed.startsWith('page:')
        ? (int.tryParse(trimmed.substring('page:'.length)) ?? 2)
        : null;
    const candidates = ['100803_-_page_hot_list', '100803'];
    Object? lastError;
    for (final cid in candidates) {
      final params = <String, String?>{
        'containerid': cid,
        if (pageNumber != null)
          'page': '$pageNumber'
        else if (trimmed.isNotEmpty)
          'since_id': trimmed,
      };
      try {
        final root = await _get(
          Api.url('https://m.weibo.cn/api/container/getIndex', params),
          cookie(),
          force: force,
        );
        final parsed = parseSuperTopicList(root, currentPage: pageNumber ?? 1);
        if (parsed.items.isNotEmpty) return parsed;
      } on Object catch (e) {
        lastError = e;
      }
      if (trimmed.isNotEmpty) break;
    }
    if (lastError != null) throw lastError;
    return const SuperTopicListPage(items: []);
  }

  Future<List<TopicItem>> searchSuperTopics(String query) async {
    if (!hasSession()) throw ApiException('超话需要登录后查看', '-100');
    try {
      final topics = await _searchIndex(
        '100103type=1&q=$query',
        page: 1,
        force: true,
        parse: parseSuperTopicSearch,
      );
      final out = <TopicItem>[];
      for (final topic in topics) {
        if (topic.title == '超话') {
          final id = topic.containerId;
          if (id == null) throw ApiException('超话身份缺失');
          final page = await superTopic(id);
          out.add(
            TopicItem(
              title: page.info.title,
              desc1: topic.desc1,
              desc2: topic.desc2,
              scheme: topic.scheme,
              containerId: topic.containerId,
              avatar: topic.avatar.isNotEmpty ? topic.avatar : page.info.avatar,
            ),
          );
        } else {
          out.add(topic);
        }
      }
      return out;
    } on ApiHttpException catch (e) {
      if (e.code == 432) throw ApiException('超话需要登录后查看', '432');
      throw ApiException('超话搜索失败（HTTP ${e.code}）');
    } on ApiException catch (e) {
      if (e.errno == '432') throw ApiException('超话需要登录后查看', '432');
      if (e.errno == '-100' || e.message == _guestBlocked) {
        throw ApiException('超话需要登录后查看', '-100');
      }
      throw ApiException('超话搜索失败');
    }
  }

  Future<FeedPage> search(
    String query, {
    int page = 1,
    bool force = true,
    SearchSort sort = SearchSort.comprehensive,
  }) {
    final cid = '100103type=${sort.type}&q=$query';
    return container(
      cid,
      extra: page > 1 ? {'page': '$page'} : const {},
      force: force,
    );
  }

  Future<FeedPage> topicChannelFeed(
    String query,
    TopicChannel channel, {
    String? cursor,
    bool force = false,
  }) async {
    final page = math.max(1, int.tryParse(cursor ?? '') ?? 1);
    final cid = '100103type=${channel.type}&q=$query';
    final res = await container(
      cid,
      extra: page > 1 ? {'page': '$page'} : const {},
      force: force,
    );
    return FeedPage(res.items, res.items.isNotEmpty ? '${page + 1}' : null);
  }

  Future<List<User>> searchUsers(
    String query, {
    int page = 1,
    bool force = true,
  }) => _searchIndex(
    '100103type=3&q=$query&t=0',
    page: page,
    force: force,
    parse: parseUserCards,
  );

  Future<List<TopicItem>> searchTopics(
    String query, {
    int page = 1,
    bool force = true,
  }) => _searchIndex(
    '100103type=38&q=$query&t=0',
    page: page,
    force: force,
    parse: parseTopicCards,
  );

  Future<List<T>> _searchIndex<T>(
    String cid, {
    required int page,
    required bool force,
    required List<T> Function(Map<String, dynamic>?) parse,
  }) async {
    final root = await _get(
      Api.url(
        'https://m.weibo.cn/api/container/getIndex',
        {
          'containerid': cid,
          'page_type': 'searchall',
          'page': '${math.max(1, page)}',
        },
      ),
      cookie(),
      force: force,
    );
    final items = parse(root);
    if (items.isEmpty && root.intOf('ok', 1) != 1) {
      final message = root.str('msg', '搜索失败');
      if (message.contains('还没有内容') || message.contains('暂无')) {
        return const [];
      }
      throw ApiException(message);
    }
    return items;
  }

  Future<Status?> detail(String id, {bool force = false}) async {
    final root = await _get(
      Api.url('https://m.weibo.cn/statuses/show', {'id': id}),
      cookie(),
      force: force,
    );
    final parsed = Status.from(root.obj('data'));
    if (parsed == null) return null;
    final favorited = isFavorited(id);
    return parsed.favorited == favorited
        ? parsed
        : parsed.copyWith(favorited: favorited);
  }

  Future<List<EditVersion>> editHistory(String mid, {int page = 1}) async {
    if (mid.isEmpty) return const [];
    final root = await Api.getDesktop(
      Api.url(
        'https://weibo.com/ajax/statuses/editHistory',
        {'mid': mid, 'page': '${math.max(1, page)}'},
      ),
      cookie(),
    );
    final arr = root.arr('statuses');
    if (arr == null) return const [];
    final out = <EditVersion>[];
    for (final item in arr) {
      final version = EditVersion.from(jObj(item));
      if (version != null) out.add(version);
    }
    return out;
  }

  Future<String> resolveShortUrl(String url) async {
    try {
      return await Api.resolveRedirect(url, cookie());
    } on Object {
      return url;
    }
  }

  Future<String?> resolveStatusVoteId(String statusId, String textHtml) async {
    final cached = _statusVoteIdCache[statusId];
    if (cached != null) return cached;
    final short = RegExp(r'https?://t\.cn/[a-zA-Z0-9]+').firstMatch(textHtml);
    if (short != null) {
      final redirected = await resolveShortUrl(short.group(0)!);
      final vid = extractVoteId(redirected);
      if (vid != null) {
        _statusVoteIdCache[statusId] = vid;
        return vid;
      }
    }
    String? resolved;
    try {
      final root = await Api.getDesktop(
        'https://weibo.com/ajax/statuses/show?id=$statusId',
        cookie(),
      );
      final page = root.obj('page_info');
      final voteObj = page?.obj('card_info')?.obj('vote_object');
      resolved = voteObj?.str('id') ?? extractVoteId(page?.str('page_url'));
      resolved ??= extractVoteIdFromUrlStruct(root.arr('url_struct'));
      if (resolved != null && resolved.isEmpty) resolved = null;
    } on Object {
      resolved = null;
    }
    if (resolved != null) _statusVoteIdCache[statusId] = resolved;
    return resolved;
  }

  Future<VoteInfo> fetchVote(String voteId, {bool force = false}) async {
    if (!force) {
      final cached = _voteCache[voteId];
      if (cached != null) return cached;
    }
    final html = await Api.getHtml(
      'https://vote.weibo.com/h5/index/index?vote_id=$voteId',
      cookie(),
    );
    final match = RegExp(
      r"window\.__DATA__\s*=\s*(\{.*?\})\s*\|\|\s*''\s*;",
      dotAll: true,
    ).firstMatch(html);
    if (match == null) throw ApiException('无法解析投票页面数据');
    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(match[1]!);
      if (decoded is! Map) throw const FormatException();
      root = {for (final e in decoded.entries) e.key.toString(): e.value};
    } on Object {
      throw ApiException('投票数据格式错误');
    }
    final sk = root.str('sk');
    final vi = root.obj('vote_info');
    if (vi == null) throw ApiException('未找到投票信息');
    final parsed = parseVoteInfoJson(voteId, sk, vi);
    _voteCache[voteId] = parsed;
    return parsed;
  }

  Future<VoteInfo> castVote(
    String voteId,
    List<String> optionIds,
    String sk,
  ) async {
    if (optionIds.isEmpty) throw ApiException('请选择投票选项');
    final cookie = _loginCookie();
    final root = await Api.postVote(
      'https://vote.weibo.com/vote/h5/aj/vote/index',
      {
        'vote_id': voteId,
        'vote_optionids': optionIds.join(','),
        'sk': sk,
      },
      cookie: cookie,
      referer: 'https://vote.weibo.com/h5/index/index?vote_id=$voteId',
    );
    final code = root.intOf('code');
    if (code != 1) {
      throw ApiException(
        _firstNonEmpty([root.str('msg'), '投票失败 ($code)']),
      );
    }
    final vi = root.obj('data')?.obj('vote_info');
    if (vi != null) {
      final parsed = parseVoteInfoJson(voteId, sk, vi);
      _voteCache[voteId] = parsed;
      return parsed;
    }
    return fetchVote(voteId, force: true);
  }

  Future<VoteInfo> uncastVote(String voteId, String sk) async {
    final cookie = _loginCookie();
    final root = await Api.postVote(
      'https://vote.weibo.com/vote/h5/aj/cancelvote/index',
      {'vote_id': voteId, 'sk': sk},
      cookie: cookie,
      referer: 'https://vote.weibo.com/h5/index/index?vote_id=$voteId',
    );
    final code = root.intOf('code');
    if (code != 1) {
      throw ApiException(
        _firstNonEmpty([root.str('msg'), '取消投票失败 ($code)']),
      );
    }
    final vi = root.obj('data')?.obj('vote_info');
    if (vi != null) {
      final parsed = parseVoteInfoJson(voteId, sk, vi);
      _voteCache[voteId] = parsed;
      return parsed;
    }
    return fetchVote(voteId, force: true);
  }

  Future<CommentPage> comments(
    String id, {
    required String mid,
    CommentSort sort = CommentSort.hot,
    String? maxId,
    int maxIdType = 0,
    int page = 1,
    bool force = false,
  }) async {
    if (sort == CommentSort.time) {
      final root = await _get(
        Api.url('https://m.weibo.cn/api/comments/show', {
          'id': id,
          'page': '${math.max(1, page)}',
        }),
        cookie(),
        force: force,
      );
      final data = root.obj('data');
      if (data == null) return const CommentPage([], '', 0);
      final items = <Comment>[];
      for (final item in data.arr('data') ?? const []) {
        final comment = Comment.from(jObj(item));
        if (comment != null) items.add(comment);
      }
      final last = data.intOf('max');
      return CommentPage(
        items,
        '',
        0,
        items.isNotEmpty && page < last ? page + 1 : 0,
      );
    }
    final params = <String, String?>{
      'id': id,
      'mid': mid.isEmpty ? id : mid,
      if (maxId == null || maxId.isEmpty)
        'max_id_type': '0'
      else ...{'max_id': maxId, 'max_id_type': '$maxIdType'},
    };
    final root = await _get(
      Api.url('https://m.weibo.cn/comments/hotflow', params),
      cookie(),
      force: force,
    );
    final data = root.obj('data');
    if (data == null) return const CommentPage([], '', 0);
    final items = <Comment>[];
    for (final item in data.arr('data') ?? const []) {
      final comment = Comment.from(jObj(item));
      if (comment != null) items.add(comment);
    }
    return CommentPage(
      items,
      _nextCursor(data.str('max_id')),
      data.intOf('max_id_type'),
    );
  }

  /// 楼中楼：热门榜只内联几条预览，完整回复走 `comments/hotFlowChild`。
  Future<CommentPage> commentReplies(
    String cid, {
    String? maxId,
    int maxIdType = 0,
    bool force = false,
  }) async {
    final root = await _get(
      Api.url('https://m.weibo.cn/comments/hotFlowChild', {
        'cid': cid,
        'max_id': maxId ?? '0',
        'max_id_type': '$maxIdType',
      }),
      cookie(),
      force: force,
    );
    final items = <Comment>[];
    for (final item in root.arr('data') ?? const []) {
      final comment = Comment.from(jObj(item), depth: 1);
      if (comment != null) items.add(comment);
    }
    final total = root.intOf('total_number');
    return CommentPage(
      items,
      _nextCursor(root.str('max_id')),
      root.intOf('max_id_type'),
      total > 0 ? total : 0,
    );
  }

  /// `max_id` 回来是 `0` 就是没有下一页了：热门榜拿它当结束标记，不是游标。
  /// 当成空串交给上层，按钮才会显示「没有更多」，而不是再请求一次首页。
  static String _nextCursor(String raw) => raw == '0' ? '' : raw;

  /// 正文里的 @ 只有昵称，按可靠程度依次解析出 uid：
  /// 1. weibo.com 桌面精准昵称接口（无搜索误匹配）；
  /// 2. m.weibo.cn `/n/<昵称>` 302 跳转提取 `/u/<uid>`；
  /// 3. m.weibo.cn 用户搜索兜底（精确匹配优先）。
  Future<String?> uidForName(String name) async {
    final clean = name.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.isEmpty) return null;
    final cached = _uidByNameCache[clean];
    if (cached != null && cached.isNotEmpty) return cached;

    String? remember(String? uid) {
      if (uid != null && uid.isNotEmpty && RegExp(r'^\d+$').hasMatch(uid)) {
        _uidByNameCache[clean] = uid;
        return uid;
      }
      return null;
    }

    // 1. 桌面端按 screen_name 精准查资料。
    try {
      final root = await Api.getDesktop(
        Api.url('https://weibo.com/ajax/profile/info', {'screen_name': clean}),
        cookie(),
      );
      final user = root.obj('data')?.obj('user');
      final id = firstNonEmpty([user?.str('idstr') ?? '', user?.str('id') ?? '']);
      final hit = remember(id);
      if (hit != null) return hit;
    } on Object {
      // 访客态或接口波动时落到下一层。
    }

    // 2. `/n/<昵称>` 跳转目标里直接带 `/u/<uid>`。
    try {
      final redirected = await Api.resolveRedirect(
        'https://m.weibo.cn/n/${Uri.encodeComponent(clean)}',
        cookie(),
      );
      final hit = remember(weiboUserId(redirected));
      if (hit != null) return hit;
    } on Object {
      // 同上。
    }

    // 3. 移动端用户搜索兜底：同时扫 card.user 与 card_group[].user。
    try {
      final root = await _get(
        Api.url('https://m.weibo.cn/api/container/getIndex', {
          'containerid': '100103type=3&q=${Uri.encodeQueryComponent(clean)}',
        }),
        cookie(),
      );
      final cards = root.obj('data')?.arr('cards');
      if (cards == null) return null;
      final lowerClean = clean.toLowerCase();
      String? ciMatch;
      String? fallback;
      void inspectUser(Map<String, dynamic>? user) {
        if (user == null) return;
        final id = firstNonEmpty([user.str('idstr'), user.str('id')]);
        if (id.isEmpty) return;
        final screenName = user.str('screen_name');
        if (screenName == clean) {
          ciMatch = id;
        } else if (ciMatch == null && screenName.toLowerCase() == lowerClean) {
          ciMatch = id;
        }
        fallback ??= id;
      }

      for (final card in cards) {
        final obj = jObj(card);
        if (obj == null) continue;
        final directUser = obj.obj('user');
        if (directUser != null) {
          if (directUser.str('screen_name') == clean) {
            final hit = remember(
              firstNonEmpty([directUser.str('idstr'), directUser.str('id')]),
            );
            if (hit != null) return hit;
          }
          inspectUser(directUser);
        }
        final group = obj.arr('card_group');
        if (group == null) continue;
        for (final item in group) {
          final user = jObj(item)?.obj('user');
          if (user == null) continue;
          if (user.str('screen_name') == clean) {
            final hit = remember(
              firstNonEmpty([user.str('idstr'), user.str('id')]),
            );
            if (hit != null) return hit;
          }
          inspectUser(user);
        }
      }
      return remember(ciMatch ?? fallback);
    } on Object {
      return null;
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, String> form,
  ) async {
    final cookie = _loginCookie();
    var st = await this.st();
    Map<String, dynamic> root;
    try {
      root = await Api.post(url, {...form, 'st': st}, cookie: cookie, st: st);
    } on ApiHttpException catch (e) {
      if (!_isCsrfHttp(e)) rethrow;
      st = (await config(force: true)).st;
      root = await Api.post(url, {...form, 'st': st}, cookie: cookie, st: st);
    }
    if (root.intOf('ok', 0) != 1 &&
        (root.str('msg').toLowerCase().contains('st') || _isCsrfBody(root))) {
      st = (await config(force: true)).st;
      root = await Api.post(url, {...form, 'st': st}, cookie: cookie, st: st);
    }
    return root;
  }

  bool _isCsrfBody(Map<String, dynamic> root) =>
      root.str('errno') == '100006' || root.str('msg').contains('非法');

  bool _isCsrfHttp(ApiHttpException e) =>
      e.code == 403 || e.body.contains('100006') || e.body.contains('请求非法');

  Future<bool> _postOk(String url, Map<String, String> form) async {
    final root = await _postJson(url, form);
    if (root.intOf('ok', 0) != 1) {
      // errno 要一起带出去：调用方靠它区分「点赞太频繁」和其它失败。
      throw ApiException(root.str('msg', '操作失败'), root.str('errno'));
    }
    return true;
  }

  Future<bool> likeComment(String id, {required bool liked}) async {
    // 网页版现在走 api/likes/update|destroy（id + type=comment）。旧的
    // comment/like 在服务端是「回 ok:1 但不落库」的空实现；新接口对一部分
    // 账号会回 errno 20000（未知错误），所以两个都试，谁成功算谁的。
    try {
      final root = await _postJson(
        liked
            ? 'https://m.weibo.cn/api/likes/destroy'
            : 'https://m.weibo.cn/api/likes/update',
        {'id': id, 'type': 'comment'},
      );
      if (root.intOf('ok', 0) == 1) return true;
    } on ApiException {
      // 落到下面的旧接口。
    } on ApiHttpException {
      // 404 / 403 这类也退回旧接口。
    }
    return _postOk(
      liked
          ? 'https://m.weibo.cn/comment/dislike'
          : 'https://m.weibo.cn/comment/like',
      {'id': id},
    );
  }

  Future<bool> like(String id, {required bool liked}) async {
    // 微博被限流后会把窗口一直往后推，所以撞上以后先自己停手，
    // 而不是让用户每点一次就再去撞一次。
    if (_likeGate.blocked) {
      throw ApiException('点赞太频繁，稍后再试');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _likeBusy[id];
    if (last != null && now - last < _likeCooldownMs) {
      throw ApiException('点得太快了，稍等一下');
    }
    _likeBusy[id] = now;
    try {
      final ok = await _postOk(
        liked
            ? 'https://m.weibo.cn/api/attitudes/destroy'
            : 'https://m.weibo.cn/api/attitudes/create',
        liked ? {'id': id} : {'id': id, 'attitude': 'heart'},
      );
      Api.cache?.invalidate(
        Api.url('https://m.weibo.cn/statuses/show', {'id': id}),
        cookie(),
      );
      _likeGate.onAccepted();
      return ok;
    } on ApiException catch (e) {
      _likeBusy.remove(id);
      // 20016 = 「update weibo too fast」：服务端限流，退避。
      if (e.errno == '20016') {
        _likeGate.onRejected();
      }
      rethrow;
    } on Object {
      _likeBusy.remove(id);
      rethrow;
    }
  }

  /// 只动本机那份星标（换机恢复、纯本地模式用）；界面上的收藏按钮走 [toggleFavorite]。
  Future<bool> favorite(String id, {required bool favorited}) async {
    if (favorited) {
      store.removeFavorite(id);
      localFavoriteIds.remove(id);
      favoritesVersion++;
      _notify();
      return true;
    }
    final status = await detail(id);
    if (status == null) throw ApiException('微博不存在');
    store.addFavorite(status);
    localFavoriteIds[id] = true;
    favoritesVersion++;
    _notify();
    return true;
  }

  /// 桌面端 cookie：`XSRF-TOKEN` 只种在 `.weibo.com` 下面，所以按 weibo.com 拼。
  String _desktopCookie() {
    final active = session;
    if (active == null || !active.loggedIn) throw ApiException(_loginRequired);
    final merged = CookieVault.desktopAuthHeader(active.cookies, 'weibo.com');
    return merged.isEmpty ? active.cookie : merged;
  }

  String _desktopXsrf() {
    final active = session;
    if (active == null) return '';
    final raw =
        CookieVault.cookieValue(active.cookies, 'weibo.com', 'XSRF-TOKEN') ?? '';
    if (raw.isEmpty) return '';
    // cookie 里存的是 URL 编码过的，请求头要的是解码后的原值。
    try {
      return Uri.decodeComponent(raw);
    } on Object {
      return raw;
    }
  }

  /// weibo.com 的 `XSRF-TOKEN` 不见得种着（网页登录过的会话也常常只有 SUB/SUBP）。
  /// 缺了就先去打一次网页首页，让服务端用 `Set-Cookie` 把它发下来，[Repo._absorbCookies]
  /// 会顺手并进会话。
  Future<void> _warmDesktopXsrf(String cookie) async {
    try {
      await Api.getHtml('https://weibo.com/', cookie);
    } on Object {
      // 种不下来就让写接口自己回 403，界面会把原因带出来。
    }
  }

  /// 收藏接口失败时把服务端那句话捞出来：业务错误也是 HTTP 400 + `{"ok":0,"message":"…"}`，
  /// 直接甩一句 HTTP 400 谁也看不懂。
  String _favoriteError(Map<String, dynamic>? root, String fallback) {
    final message = root?.str('message') ?? '';
    if (message.isNotEmpty) return message;
    final msg = root?.str('msg') ?? '';
    return msg.isEmpty ? fallback : msg;
  }

  Map<String, dynamic>? _decodeBody(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return {for (final e in decoded.entries) e.key.toString(): e.value};
      }
    } on Object {
      // 不是 JSON 就算了，错误提示退回兜底文案。
    }
    return null;
  }

  Future<Map<String, dynamic>> _postFavorite(
    String id, {
    required bool favorited,
  }) {
    return Api.postDesktopJson(
      favorited ? _favoriteCreateUrl : _favoriteDestroyUrl,
      jsonEncode({'id': id}),
      cookie: _desktopCookie(),
      xsrfToken: _desktopXsrf(),
      referer: _favoriteReferer,
    );
  }

  /// 收藏 / 取消收藏一次，直接落到微博的收藏夹（不是本机那份星标）。
  ///
  /// 第一次写如果被 400/403 挡回来，先补一次 XSRF 令牌再重试一遍：网页登录留下的
  /// 会话里常常没有这个 cookie，第一次写大概率是「令牌还没种下来」。
  Future<bool> setOnlineFavorite(String id, {required bool favorited}) async {
    if (id.isEmpty) throw ApiException('微博不存在');
    var warmed = _desktopXsrf().isNotEmpty;
    if (!warmed) {
      await _warmDesktopXsrf(_desktopCookie());
      warmed = true;
    }
    while (true) {
      try {
        final root = await _postFavorite(id, favorited: favorited);
        if (root.intOf('ok', 0) == 1 || root.has('data')) {
          Api.cache?.clear();
          onlineFavoritesVersion++;
          _notify();
          return true;
        }
        throw ApiException(_favoriteError(root, '收藏失败'));
      } on ApiHttpException catch (e) {
        // 令牌缺失/过期时服务端回 400/403；补一次再试，别让用户点两下。
        if (warmed) {
          throw ApiException(_favoriteError(_decodeBody(e.body), '收藏失败'));
        }
        warmed = true;
        await _warmDesktopXsrf(_desktopCookie());
      }
    }
  }

  /// 「收藏」按钮的完整动作：先落本机（界面立刻有反馈），登录态下再写一次微博收藏夹。
  ///
  /// 写失败不回滚本机：用户点的是收藏，本机那份不该因为服务端拦了一下就丢掉；
  /// 失败原因交给界面提示，同时说明「本机已经收下了」。
  Future<FavoriteToggle> toggleFavorite(Status status) async {
    final favorited = toggleLocalFavorite(status);
    if (!_shouldSyncFavorites()) return FavoriteToggle(favorited);
    try {
      await setOnlineFavorite(status.id, favorited: favorited);
      return FavoriteToggle(favorited);
    } on Object catch (e) {
      final message = e.toString().trim();
      return FavoriteToggle(favorited, message.isEmpty ? '收藏失败' : message);
    }
  }

  /// 纯本地模式、或设置里关掉了同步时，收藏只写本机。
  bool _shouldSyncFavorites() =>
      (session?.loggedIn ?? false) && settings.favoriteSync;

  /// 微博收藏夹（在线收藏）。和 [favorites] 那份本机星标不是一回事：这里拿的是
  /// 网页版 / 官方客户端里真正收藏过的微博。
  ///
  /// 走 `weibo.com/ajax/favorites/all_fav`：m.weibo.cn 的 `containerid=230267` 实测只回
  /// 「这里还没有内容」，它已经不是收藏夹了。分页按 `page` 走，一页 20 条。
  ///
  /// 拉回来的条目顺手镜像进本机表，这样卡片上的星标和「取消收藏」对得上；
  /// 这里**不要**动 [favoritesVersion]，否则收藏页会因为自己的刷新而无限重拉。
  Future<FeedPage> onlineFavorites({String? cursor, bool force = false}) async {
    if (session?.loggedIn != true) throw ApiException(_loginRequired);
    final page = int.tryParse(cursor ?? '') ?? 1;
    final uid = await ownUid();
    final root = await Api.getDesktop(
      Api.url(_favoriteListUrl, {'uid': uid, 'page': '$page'}),
      _desktopCookie(),
      referer: _favoriteReferer,
    );
    final arr = root.arr('data');
    if (arr == null) throw ApiException(_favoriteError(root, '收藏没拉到'));
    final items = <Status>[];
    for (final entry in arr) {
      final o = jObj(entry);
      if (o == null) continue;
      final status = Status.from(o.obj('mblog') ?? o);
      if (status == null) continue;
      items.add(status.copyWith(favorited: true));
    }
    if (items.isNotEmpty) {
      store.addFavorites(items);
      // 星标读的是这张内存表，镜像完顺手填上，卡片才不至于显示成「未收藏」。
      for (final status in items) {
        localFavoriteIds[status.id] = true;
      }
    }
    return FeedPage(
      items,
      items.length >= _favoritePageSize ? '${page + 1}' : null,
    );
  }

  Future<bool> follow(String uid, {required bool follow}) async {
    final cookie = _loginCookie();
    final url = follow
        ? 'https://m.weibo.cn/api/friendships/create'
        : 'https://m.weibo.cn/api/friendships/destory';
    var st = await this.st();
    var root = await Api.post(url, {'uid': uid, 'st': st}, cookie: cookie, st: st);
    if (!root.has('data') &&
        root.intOf('ok', 0) != 1 &&
        root.str('msg').toLowerCase().contains('st')) {
      st = (await config(force: true)).st;
      root = await Api.post(
        url,
        {'uid': uid, 'st': st},
        cookie: cookie,
        st: st,
      );
    }
    final ok = root.has('data') || root.intOf('ok', 0) == 1;
    if (!ok) throw ApiException(root.str('msg', '操作失败'));
    Api.cache?.invalidate(
      Api.url(
        'https://m.weibo.cn/api/container/getIndex',
        {'type': 'uid', 'value': uid},
      ),
      cookie,
    );
    _notify();
    return true;
  }

  Future<bool> comment(String id, String mid, String text) async {
    final ok = await _postOk(
      'https://m.weibo.cn/api/comments/create',
      {'id': id, 'mid': mid.isEmpty ? id : mid, 'content': text},
    );
    Api.cache?.clear();
    return ok;
  }

  Future<Comment> replyComment(
    String id,
    String mid,
    String cid,
    String text,
  ) async {
    final root = await _postJson(
      'https://m.weibo.cn/api/comments/reply',
      {
        'id': id,
        'mid': mid.isEmpty ? id : mid,
        'cid': cid,
        'content': text,
      },
    );
    if (root.intOf('ok', 0) != 1) {
      throw ApiException(root.str('msg', '回复失败'));
    }
    Api.cache?.clear();
    final comment = Comment.from(root.obj('data'), depth: 1);
    if (comment == null) throw ApiException('回复失败');
    return comment;
  }

  Future<bool> repost(
    String id,
    String mid,
    String text, {
    int visible = 0,
  }) async {
    final form = <String, String>{
      'id': id,
      'mid': mid.isEmpty ? id : mid,
      'content': text,
      if (visible != 0) 'visible': '$visible',
    };
    final ok = await _postOk('https://m.weibo.cn/api/statuses/repost', form);
    Api.cache?.clear();
    return ok;
  }

  Future<bool> publish(
    String text,
    List<String> picIds, {
    int visible = 0,
  }) async {
    final form = <String, String>{
      'content': text,
      'visible': '$visible',
      if (picIds.isNotEmpty) 'pic_ids': picIds.join(','),
    };
    final ok = await _postOk('https://m.weibo.cn/api/statuses/update', form);
    Api.cache?.clear();
    _notify();
    return ok;
  }

  Future<bool> deleteStatus(String id, {String mid = ''}) async {
    final targetMid = mid.isEmpty ? id : mid;
    final ok = await _postOk('https://m.weibo.cn/profile/delMyblog', {
      'mid': targetMid,
    });
    store.removeFavorite(id);
    if (targetMid != id) store.removeFavorite(targetMid);
    var changed = localFavoriteIds.remove(id) != null;
    if (targetMid != id && localFavoriteIds.remove(targetMid) != null) {
      changed = true;
    }
    if (changed) favoritesVersion++;
    deletedStatusIds[id] = true;
    if (targetMid.isNotEmpty) deletedStatusIds[targetMid] = true;
    deletedVersion++;
    Api.cache?.clear();
    _notify();
    return ok;
  }

  Future<List<EmojiSection>> emotions() async {
    final activeCookie = cookie() ?? '';
    if (_cachedEmotionSections.isNotEmpty &&
        _cachedEmotionCookie == activeCookie) {
      return _cachedEmotionSections;
    }
    List<EmojiSection> sections;
    try {
      final root = await Api.getDesktop(
        'https://weibo.com/ajax/statuses/config',
        activeCookie,
      );
      sections = parseWeiboEmotions(root);
    } on Object {
      sections = const [];
    }
    if (sections.isNotEmpty) {
      _cachedEmotionSections = sections;
      _cachedEmotionCookie = activeCookie;
      return sections;
    }
    return fallbackEmojiSections;
  }

  Future<List<User>> mentionCandidates(String query) async {
    final friends = await _loadMentionFriends();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return friends.take(20).toList();
    final merged = <String, User>{};
    for (final user in friends) {
      if (user.name.toLowerCase().contains(trimmed.toLowerCase())) {
        merged.putIfAbsent(user.id, () => user);
      }
    }
    try {
      final searched = await searchUsers(trimmed, page: 1, force: false);
      for (final user in searched) {
        merged.putIfAbsent(user.id, () => user);
      }
    } on Object {
      // 搜索挂了就只用好友列表。
    }
    return merged.values.take(20).toList();
  }

  Future<List<User>> _loadMentionFriends() async {
    final uid = session?.uid ?? '';
    if (_cachedMentionFriends.isNotEmpty && _cachedMentionUid == uid) {
      return _cachedMentionFriends;
    }
    final activeCookie = cookie();
    if (activeCookie == null) return const [];
    var result = <User>[];
    try {
      final root = await _get(
        Api.url('https://m.weibo.cn/api/friendships/friends', {'page': '1'}),
        activeCookie,
        force: false,
      );
      final arr = root.obj('data')?.arr('users') ?? const [];
      result = [
        for (final item in arr)
          if (User.from(jObj(item)) case final user?) user,
      ];
    } on Object {
      result = const [];
    }
    if (result.isEmpty && uid.isNotEmpty) {
      try {
        result = await relations(uid, RelationKind.following, page: 1, force: false);
      } on Object {
        result = const [];
      }
    }
    if (result.isNotEmpty) {
      _cachedMentionFriends = result;
      _cachedMentionUid = uid;
    }
    return result;
  }

  Future<List<TopicSuggestion>> topicCandidates(String query) async {
    final trimmed = query.trim().replaceAll(RegExp(r'^#+|#+$'), '');
    final activeCookie = cookie();
    if (trimmed.isEmpty) {
      if (_cachedHotspotTopics.isNotEmpty) return _cachedHotspotTopics;
      var topics = <TopicSuggestion>[];
      try {
        final root = await _get(
          'https://m.weibo.cn/api/suggest/hotspot',
          activeCookie,
          force: false,
        );
        topics = parseHotspotTopics(root);
      } on Object {
        topics = const [];
      }
      if (topics.isEmpty) {
        try {
          final hotItems = await hot(board: HotBoard.realtime, force: false);
          topics = [
            for (final item in hotItems.take(20))
              TopicSuggestion(item.title, desc: item.label),
          ];
        } on Object {
          topics = const [];
        }
      }
      if (topics.isNotEmpty) _cachedHotspotTopics = topics;
      return topics.take(20).toList();
    }
    final out = <String, TopicSuggestion>{};
    try {
      final root = await _get(
        Api.url(
          'https://m.weibo.cn/api/suggest/shotspot',
          {'keyword': trimmed},
        ),
        activeCookie,
        force: false,
      );
      for (final topic in parseHotspotTopics(root)) {
        out.putIfAbsent(topic.title, () => topic);
      }
    } on Object {
      // 联想挂了还有搜索兜底。
    }
    if (out.isEmpty) {
      try {
        final topics = await searchTopics(trimmed, page: 1, force: false);
        for (final topic in topics) {
          final clean = topic.title.replaceAll(RegExp(r'^#+|#+$'), '');
          if (clean.isNotEmpty) {
            out.putIfAbsent(clean, () => TopicSuggestion(clean, desc: topic.desc1));
          }
        }
      } on Object {
        // 同上。
      }
    }
    out.putIfAbsent(trimmed, () => TopicSuggestion(trimmed, desc: '新话题'));
    return out.values.take(20).toList();
  }

  Future<String> uploadImage(
    List<int> bytes, {
    String mime = 'image/jpeg',
  }) async {
    final cookie = _loginCookie();
    final st = await this.st();
    final fileName = mime.contains('png')
        ? 'pic.png'
        : mime.contains('gif')
        ? 'pic.gif'
        : mime.contains('webp')
        ? 'pic.webp'
        : 'pic.jpg';
    final root = await Api.upload(
      'https://m.weibo.cn/api/statuses/uploadPic',
      bytes: bytes,
      fileName: fileName,
      mime: mime,
      cookie: cookie,
      st: st,
    );
    final id = root.str('pic_id');
    if (id.isEmpty) throw ApiException(root.str('msg', '图片上传失败'));
    return id;
  }

  Future<List<MessageItem>> messages(int page, {bool force = false}) async {
    final root = await _get(
      Api.url('https://m.weibo.cn/message/msglist', {'page': '$page'}),
      cookie(),
      force: force,
    );
    final arr = root.arr('data');
    if (arr == null) return const [];
    final out = <MessageItem>[];
    for (final item in arr) {
      final o = jObj(item);
      if (o == null) continue;
      out.add(
        MessageItem(
          id: o.str('id'),
          text: o.str('text'),
          createdAt: normalizeWeiboTime(o.str('created_at')),
          user: User.from(o.obj('user')),
          unread: o.intOf('unread'),
          scheme: o.str('scheme'),
          gid: chatGidOf(o.str('scheme')),
        ),
      );
    }
    return out;
  }

  /// 消息中心统一入口：`message/mentionsAt`、`message/mentionsCmt`、
  /// `message/cmt`、`message/attitude` 都是 `page=N` 翻页，翻到底时
  /// `data` 从数组变成 `false`（不是空数组，别按长度判断）。
  Future<NoticeBatch<T>> _notices<T>(
    String target,
    int page,
    T? Function(Map<String, dynamic>) parse, {
    bool force = false,
  }) async {
    final root = await _get(
      Api.url(target, {'page': '$page'}),
      cookie(),
      force: force,
    );
    if (root.intOf('ok', 0) != 1) {
      throw ApiException(
        firstNonEmpty([root.str('msg'), '通知加载失败']),
        root.str('errno'),
      );
    }
    final arr = root.arr('data');
    if (arr == null || arr.isEmpty) return NoticeBatch<T>(<T>[]);
    final items = <T>[];
    for (final item in arr) {
      final parsed = parse(jObj(item) ?? const {});
      if (parsed != null) items.add(parsed);
    }
    return NoticeBatch<T>(items, hasMore: items.isNotEmpty);
  }

  /// @我的微博。
  Future<NoticeBatch<Status>> atMe(int page, {bool force = false}) => _notices(
    'https://m.weibo.cn/message/mentionsAt',
    page,
    Status.from,
    force: force,
  );

  /// @我的评论：别人在评论里 @ 了你。
  Future<NoticeBatch<Comment>> atComments(int page, {bool force = false}) =>
      _notices(
        'https://m.weibo.cn/message/mentionsCmt',
        page,
        (o) => Comment.from(o, withStatus: true),
        force: force,
      );

  /// 收到的评论：别人评论了你的微博。
  Future<NoticeBatch<Comment>> commentsToMe(int page, {bool force = false}) =>
      _notices(
        'https://m.weibo.cn/message/cmt',
        page,
        (o) => Comment.from(o, withStatus: true),
        force: force,
      );

  /// 收到的赞。
  Future<NoticeBatch<LikeNotice>> likesToMe(int page, {bool force = false}) =>
      _notices(
        'https://m.weibo.cn/message/attitude',
        page,
        LikeNotice.from,
        force: force,
      );

  /// 聊天记录：接口给的是最新在前，群聊接口给的是旧→新，这里统一成最新在前。
  Future<ChatPage> chat({
    String uid = '',
    String gid = '',
    String? maxId,
    String? sinceId,
    int count = 20,
    bool force = false,
  }) async {
    final isGroup = gid.isNotEmpty;
    final params = <String, String?>{
      isGroup ? 'gid' : 'uid': isGroup ? gid : uid,
      'count': '$count',
      'max_id': maxId,
      'since_id': sinceId,
      if (sinceId != null) 'is_continuous': '1',
    };
    final root = await _get(
      Api.url(
        isGroup
            ? 'https://m.weibo.cn/api/groupchat/list'
            : 'https://m.weibo.cn/api/chat/list',
        params,
      ),
      cookie(),
      force: force,
    );
    if (root.intOf('ok', 1) == 0) {
      // errno 要带出去：20003 是对方注销，界面据此不再给「重试」。
      throw ApiException(
        root.str('msg', '聊天记录加载失败'),
        root.str('errno'),
      );
    }
    final data = root.obj('data');
    if (data == null) return ChatPage.empty;
    return ChatPage.parse(data, isGroup: isGroup);
  }

  Future<ChatMessage?> sendChat(
    String uid,
    String text, {
    String gid = '',
  }) => _sendChatForm(
    gid.isNotEmpty
        ? 'https://m.weibo.cn/api/groupchat/send'
        : 'https://m.weibo.cn/api/chat/send',
    gid.isNotEmpty
        ? {'gid': gid, 'content': text}
        : {'uid': uid, 'content': text},
  );

  Future<ChatMessage?> sendChatImage(
    String uid,
    String fids, {
    String gid = '',
  }) => _sendChatForm(
    gid.isNotEmpty
        ? 'https://m.weibo.cn/api/groupchat/send'
        : 'https://m.weibo.cn/api/chat/send',
    gid.isNotEmpty
        ? {'gid': gid, 'content': '', 'media_type': '1', 'fids': fids}
        : {'uid': uid, 'content': '', 'media_type': '1', 'fids': fids},
  );

  Future<ChatMessage?> _sendChatForm(
    String url,
    Map<String, String> form,
  ) async {
    final root = await _postJson(url, form);
    if (root.intOf('ok', 0) != 1) {
      // 关注门槛这类业务拦截，人话在 extra 里，msg 只有「出错了，未知错误」。
      throw ApiException(
        _firstNonEmpty([root.str('extra'), root.str('msg', '发送失败')]),
        root.str('errno'),
      );
    }
    final msgs = root.obj('data')?.arr('msgs');
    return ChatMessage.from(msgs == null || msgs.isEmpty ? null : jObj(msgs.first));
  }

  /// 上传私信图片，返回 `fids`。
  Future<String> uploadChatImage(
    String uid,
    List<int> bytes, {
    String gid = '',
    String mime = 'image/jpeg',
  }) async {
    final cookie = _loginCookie();
    final name = 'chat.${mime.split('/').last}';
    var st = await this.st();
    var root = await Api.upload(
      'https://m.weibo.cn/api/chat/upload',
      bytes: bytes,
      fileName: name,
      mime: mime,
      cookie: cookie,
      st: st,
      field: 'file',
      extra: gid.isNotEmpty ? {'tochatid': gid} : {'tuid': uid},
    );
    if (root.intOf('ok', 0) != 1 && _isCsrfBody(root)) {
      st = (await config(force: true)).st;
      root = await Api.upload(
        'https://m.weibo.cn/api/chat/upload',
        bytes: bytes,
        fileName: name,
        mime: mime,
        cookie: cookie,
        st: st,
        field: 'file',
        extra: gid.isNotEmpty ? {'tochatid': gid} : {'tuid': uid},
      );
    }
    final fids = root.obj('data')?.str('fids') ?? '';
    if (fids.isEmpty) {
      throw ApiException(
        root.str('msg', '图片上传失败'),
        root.str('errno'),
      );
    }
    return fids;
  }

  Future<User?> profileFor(
    String? cookie,
    String uid, {
    bool force = false,
  }) async {
    final url = Api.url(
      'https://m.weibo.cn/api/container/getIndex',
      {'type': 'uid', 'value': uid},
    );
    User? pick(Map<String, dynamic> root) =>
        User.from(root.obj('data')?.obj('userInfo'));

    final first = pick(await _get(url, cookie, force: force));
    if (first != null) return first;
    if (!force) {
      final second = pick(await _get(url, cookie, force: true));
      if (second != null) return second;
      final alt = Api.url(
        'https://m.weibo.cn/api/container/getIndex',
        {'containerid': '100505$uid'},
      );
      return pick(await _get(alt, cookie, force: true));
    }
    return null;
  }

  Future<User?> profile(String uid, {bool force = false}) =>
      profileFor(cookie(), uid, force: force);

  Future<String> ownUid() async {
    final uid = session?.uid ?? '';
    if (uid.isNotEmpty) return uid;
    return (await config()).uid;
  }

  /// 当前账号的头像地址。账号表在磁盘上，按「uid + 登录时间」缓存，
  /// 免得每个顶栏 / 底栏重建都读一次 `accounts.json`。
  String ownAvatar() {
    final active = session;
    final uid = active?.uid ?? '';
    final key = '$uid:${active?.savedAt ?? 0}';
    if (_avatarCacheKey == key) return _avatarCache;
    _avatarCacheKey = key;
    _avatarCache = '';
    if (uid.isEmpty) return _avatarCache;
    for (final account in store.accounts()) {
      if (account.uid == uid) {
        _avatarCache = account.avatar;
        break;
      }
    }
    return _avatarCache;
  }

  Future<FeedPage> userStatuses(
    String uid, {
    String? sinceId,
    bool force = false,
  }) => container('107603$uid', sinceId: sinceId, force: force);

  /// 主页「精选」：这个人的热门微博（`231002{uid}_-_HOTMBLOG`）。
  ///
  /// 接口按页码翻页，`cardlistInfo.page` 给的是下一页的页码；未登录时翻页会回
  /// `ok:-100`（要登录），这时当到底处理，不要一直重试。
  Future<FeedPage> userFeatured(
    String uid, {
    int page = 1,
    bool force = false,
  }) async {
    final root = await _get(
      Api.url('https://m.weibo.cn/api/container/getIndex', {
        'containerid': '231002${uid}_-_HOTMBLOG',
        if (page > 1) 'page': '$page',
      }),
      cookie(),
      force: force,
    );
    if (root.intOf('ok', 1) == -100) {
      return const FeedPage([], null, hasMore: false);
    }
    final result = parseCards(root);
    final next = root.obj('data')?.obj('cardlistInfo')?.intOf('page', 0) ?? 0;
    final hasMore = result.items.isNotEmpty && next > page;
    return FeedPage(result.items, result.sinceId, hasMore: hasMore);
  }

  /// 主页「视频」：只列视频微博（`231567{uid}`），游标同样是 `since_id`。
  Future<FeedPage> userVideos(
    String uid, {
    String? sinceId,
    bool force = false,
  }) => container('231567$uid', sinceId: sinceId, force: force);

  /// 主页「相册」：网页版的图片墙（`ajax/profile/getImageWall`）。
  ///
  /// 这个接口只认 `weibo.com` 的 Referer，手机端 Referer 会回 403，所以走
  /// [Api.getDesktop]。第一页带上 `has_album=true` 才会把相册封面一起带回来；
  /// 翻页游标就是响应里的 `since_id`。
  Future<AlbumPage> userPhotos(
    String uid, {
    String? sinceId,
    bool force = false,
  }) async {
    final first = sinceId == null || sinceId.isEmpty;
    final url = Api.url('https://weibo.com/ajax/profile/getImageWall', {
      'uid': uid,
      if (first) 'has_album': 'true' else 'sinceid': sinceId,
    });
    var cookie = this.cookie() ?? '';
    if (cookie.isEmpty) cookie = await _visitorFor(null);
    final Map<String, dynamic> root;
    try {
      root = await Api.getDesktop(url, cookie);
    } on ApiHttpException catch (e) {
      if (e.code == 403 || e.code == 432) {
        throw ApiException('相册打不开，登录之后再试一次');
      }
      rethrow;
    }
    final data = root.obj('data');
    if (data == null) {
      final message = _firstNonEmpty([root.str('msg'), root.str('message')]);
      if (message.contains('登录')) {
        throw ApiException('相册需要登录后查看');
      }
      return const AlbumPage([], null);
    }
    final photos = <AlbumPhoto>[];
    for (final item in data.arr('list') ?? const []) {
      final photo = AlbumPhoto.from(jObj(item));
      if (photo != null) photos.add(photo);
    }
    final next = data.str('since_id');
    return AlbumPage(photos, next.isEmpty || next == sinceId ? null : next);
  }

  /// 关注 / 粉丝列表：自己的走 `selffollowed` / `selffans`，别人的走 `231051`。
  Future<List<User>> relations(
    String uid,
    RelationKind kind, {
    required int page,
    bool force = false,
  }) async {
    final own = uid.isNotEmpty && uid == await ownUid();
    final cid = switch (kind) {
      RelationKind.following =>
        own ? '231093_-_selffollowed' : '231051_-_followers_-_$uid',
      RelationKind.followers =>
        own ? '231016_-_selffans' : '231051_-_fans_-_$uid',
    };
    final current = math.max(1, page);
    final params = <String, String?>{
      'containerid': cid,
      if (kind == RelationKind.following)
        'page': '$current'
      else
        'since_id': '${(current - 1) * _relationPageSize}',
    };
    final root = await _get(
      Api.url('https://m.weibo.cn/api/container/getIndex', params),
      cookie(),
      force: force,
    );
    return parseRelationUsers(root);
  }

  Future<FeedPage> favorites({String? cursor, bool force = false}) async =>
      FeedPage(store.favorites(), null);

  Future<FeedPage> nearby(
    String lat,
    String lon, {
    String? maxId,
    bool force = false,
  }) => _statusFeed(
    'https://m.weibo.cn/api/feed/trendtop?containerid=102803_2222',
    maxId,
    force,
    extra: {'lat': lat, 'lon': lon},
  );

  Future<List<NearbyPlace>> nearbyCities({bool force = false}) async {
    final root = await _get(
      Api.url('https://m.weibo.cn/api/container/getIndex', {
        'containerid': '2306860024_____8008631000000000000',
        'needlocation': '1',
        'extparam': 'city',
      }),
      cookie(),
      force: force,
    );
    return parseNearbyPlaces(root);
  }

  void clearLocalHistory() => store.clearHistory();
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) return value;
  }
  return '';
}

int? _oldestStatusId(List<Status>? items) {
  if (items == null || items.isEmpty) return null;
  int? oldest;
  for (final item in items) {
    final id = int.tryParse(item.id);
    if (id == null) continue;
    oldest = oldest == null ? id : math.min(oldest, id);
  }
  return oldest;
}

/// 合并后的第 [size] 条微博 id，作为这一页的时间切点。
int? _tagFeedCut(Map<String, List<Status>> fetched, int size) {
  if (size <= 0) return null;
  final ids = fetched.values
      .expand((items) => items)
      .map((s) => int.tryParse(s.id))
      .whereType<int>()
      .toList()
    ..sort((a, b) => b.compareTo(a));
  if (ids.length < size) return null;
  return ids[size - 1];
}
