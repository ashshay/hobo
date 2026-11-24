/// 超话：身份、栏目、页面解析。
///
/// 超话的响应里 `pageInfo.containerid` 必须和期望的容器 id 对上，否则说明拿到的是别的
/// 话题的页面（微博偶尔这么回）。这里照 Kotlin 版逐条校验，校验失败直接抛错而不是显示错内容。
library;

import 'api.dart';
import 'html_text.dart';
import 'json.dart';
import 'models.dart';
import 'super_topic_id.dart';

enum SuperTopicTabKind {
  feed,
  sortTime,
  recommend,
  soul,
  official,
  album,
  video,
  detail,
  tag,
}

class SuperTopicTab {
  const SuperTopicTab({
    required this.id,
    required this.label,
    required this.containerId,
    required this.kind,
  });

  final String id;
  final String label;
  final String containerId;
  final SuperTopicTabKind kind;
}

class SuperTopicInfo {
  const SuperTopicInfo({
    required this.containerId,
    required this.title,
    this.description = '',
    this.avatar = '',
    this.readCount = '',
    this.postCount = '',
    this.fanCount = '',
  });

  final String containerId;
  final String title;
  final String description;
  final String avatar;
  final String readCount;
  final String postCount;
  final String fanCount;
}

class SuperTopicPage {
  const SuperTopicPage({
    required this.info,
    required this.items,
    this.nextCursor,
    this.tabs = const [],
  });

  final SuperTopicInfo info;
  final List<Status> items;
  final String? nextCursor;
  final List<SuperTopicTab> tabs;
}

/// 超话列表项：用于「我的超话」「超话广场」「最近访问」。
class SuperTopicSummary {
  const SuperTopicSummary({
    required this.containerId,
    required this.title,
    this.avatar = '',
    this.desc1 = '',
    this.desc2 = '',
    this.scheme = '',
  });

  final String containerId;
  final String title;
  final String avatar;
  final String desc1;
  final String desc2;
  final String scheme;

  Map<String, dynamic> toJson() => {
    'containerId': containerId,
    'title': title,
    'avatar': avatar,
    'desc1': desc1,
    'desc2': desc2,
    'scheme': scheme,
  };

  static SuperTopicSummary? fromJson(Map<String, dynamic>? o) {
    if (o == null) return null;
    final id = normalizedSuperTopicId(o.str('containerId'));
    final title = o.str('title').trim();
    if (id == null || title.isEmpty) return null;
    return SuperTopicSummary(
      containerId: id,
      title: title,
      avatar: o.str('avatar'),
      desc1: o.str('desc1'),
      desc2: o.str('desc2'),
      scheme: o.str('scheme'),
    );
  }
}

/// 超话列表的一页。
class SuperTopicListPage {
  const SuperTopicListPage({required this.items, this.nextCursor});

  final List<SuperTopicSummary> items;
  final String? nextCursor;
}

final _superTopicCount = RegExp(
  r'(阅读|帖子|粉丝)([0-9]+(?:\.[0-9]+)?[万亿千]?\+?)(?=阅读|帖子|粉丝|$)',
);
final _superTopicVideoMid = RegExp(r'(?:mid=|status/)([0-9]+)');

List<SuperTopicTab> defaultSuperTopicTabs(String baseContainerId) {
  final id =
      normalizedSuperTopicId(baseContainerId.trim()) ??
      baseContainerId.trim().toLowerCase();
  return [
    SuperTopicTab(
      id: 'feed',
      label: '最新评论',
      containerId: '${id}_-_feed',
      kind: SuperTopicTabKind.feed,
    ),
    SuperTopicTab(
      id: 'sort_time',
      label: '最新发帖',
      containerId: '${id}_-_sort_time',
      kind: SuperTopicTabKind.sortTime,
    ),
    SuperTopicTab(
      id: 'recommend',
      label: '热门',
      containerId: '${id}_-_recommend',
      kind: SuperTopicTabKind.recommend,
    ),
    SuperTopicTab(
      id: 'soul',
      label: '精华',
      containerId: '${id}_-_soul',
      kind: SuperTopicTabKind.soul,
    ),
  ];
}

SuperTopicTabKind superTopicTabKind(String containerId, [String channelId = '']) {
  final lower = containerId.toLowerCase();
  if (lower.endsWith('_-_feed') || channelId == 'feed') {
    return SuperTopicTabKind.feed;
  }
  if (lower.endsWith('_-_sort_time')) return SuperTopicTabKind.sortTime;
  if (lower.endsWith('_-_recommend')) return SuperTopicTabKind.recommend;
  if (lower.endsWith('_-_soul')) return SuperTopicTabKind.soul;
  if (lower.endsWith('_-_official') || channelId == 'official') {
    return SuperTopicTabKind.official;
  }
  if (lower.endsWith('_-_album') || channelId == 'album') {
    return SuperTopicTabKind.album;
  }
  if (lower.endsWith('_-_video') || channelId == 'video') {
    return SuperTopicTabKind.video;
  }
  if (lower.endsWith('_-_detail') || channelId == 'detail') {
    return SuperTopicTabKind.detail;
  }
  return SuperTopicTabKind.tag;
}

SuperTopicPage parseSuperTopicPage(
  Map<String, dynamic> root,
  String expectedContainerId, {
  String? tabContainerId,
  int currentPage = 1,
}) {
  final expected = normalizedSuperTopicId(expectedContainerId);
  if (expected == null) throw ApiException('无效的超话地址');
  if (root.intOf('ok') == -100) throw ApiException('超话需要登录后查看', '-100');
  if (root.intOf('ok') != 1) throw ApiException('超话加载失败');
  final data = root.obj('data');
  if (data == null) throw ApiException('超话数据缺失');
  final page = data.obj('pageInfo');
  if (page == null) throw ApiException('超话信息缺失');
  final actualCid = page.str('containerid').trim().toLowerCase();
  final bool validIdentity;
  if (tabContainerId == null) {
    validIdentity = normalizedSuperTopicId(actualCid) == expected;
  } else {
    final expectedTab = tabContainerId.trim().toLowerCase();
    validIdentity =
        actualCid == expectedTab ||
        (expectedTab == '${expected}_-_feed' && actualCid == expected) ||
        actualCid.startsWith('${expected}_-_') ||
        actualCid.startsWith('${expected}__');
  }
  if (!validIdentity) throw ApiException('超话身份校验失败');
  final title = page.str('page_title').trim();
  if (title.isEmpty) throw ApiException('超话名称缺失');

  final items = <String, Status>{};
  _collectSuperTopicCards(data.arr('cards'), items);
  final rawSince = page.str('since_id').trim();
  final String? cursor;
  if (tabContainerId == null) {
    cursor =
        RegExp(r'^\d+$').hasMatch(rawSince) && rawSince.split('').any((c) => c != '0')
        ? rawSince
        : null;
  } else {
    cursor = _resolveTabCursor(
      rawSince,
      tabContainerId,
      items.length,
      currentPage,
    );
  }

  final counts = <String, String>{};
  final descriptions = page.arr('desc_more');
  if (descriptions != null) {
    for (final item in descriptions) {
      final text = item?.toString().replaceAll(RegExp(r'\s|\u3000'), '') ?? '';
      if (text.isEmpty) continue;
      for (final match in _superTopicCount.allMatches(text)) {
        counts.putIfAbsent(match[1]!, () => match[2]!);
      }
    }
  }

  final total = page.str('total');
  return SuperTopicPage(
    info: SuperTopicInfo(
      containerId: expected,
      title: title,
      description: page.str('desc'),
      avatar: _firstNonEmpty([page.str('portrait_hd'), page.str('portrait')]),
      readCount: counts['阅读'] ?? '',
      postCount: counts['帖子'] ??
          (RegExp(r'^\d+$').hasMatch(total) ? total : ''),
      fanCount: counts['粉丝'] ?? '',
    ),
    items: items.values.toList(),
    nextCursor: cursor,
    tabs: _extractTabs(data, page, expected),
  );
}

String? _resolveTabCursor(
  String rawSince,
  String tabContainerId,
  int itemCount,
  int currentPage,
) {
  if (itemCount <= 0) return null;
  final lower = rawSince.toLowerCase();
  if (rawSince.isEmpty || lower == 'null' || rawSince.startsWith('-')) {
    return null;
  }
  if (rawSince.split('').every((c) => c == '0')) return null;
  if (tabContainerId.toLowerCase().endsWith('_-_recommend') &&
      rawSince == '1') {
    return 'page:${currentPage + 1}';
  }
  return rawSince;
}

List<SuperTopicTab> _extractTabs(
  Map<String, dynamic> data,
  Map<String, dynamic> page,
  String expectedContainerId,
) {
  final result = <String, SuperTopicTab>{};
  void addTab(String id, String name, String containerId) {
    final label = name.trim();
    final cid = containerId.trim();
    final lower = cid.toLowerCase();
    if (label.isEmpty || cid.isEmpty) return;
    if (!lower.startsWith(expectedContainerId)) return;
    result.putIfAbsent(
      lower,
      () => SuperTopicTab(
        id: id.isEmpty ? cid : id,
        label: label,
        containerId: cid,
        kind: superTopicTabKind(lower, id),
      ),
    );
  }

  final cards = data.arr('cards');
  if (cards != null) {
    for (final card in cards) {
      final group = jObj(card)?.arr('card_group');
      if (group == null) continue;
      for (final item in group) {
        final sub = jObj(item);
        if (sub == null) continue;
        if (sub.str('itemid') != 'page_feed_child_tab' &&
            sub.str('card_type') != '121') {
          continue;
        }
        final filters = sub.arr('filter_group');
        if (filters == null) continue;
        for (final filter in filters) {
          final f = jObj(filter);
          if (f == null) continue;
          final cid = f.str('containerid');
          final at = cid.indexOf('_-_');
          addTab(
            at < 0 ? 'feed' : cid.substring(at + 3),
            f.str('name'),
            cid,
          );
        }
      }
    }
  }

  if (result.isEmpty) {
    for (final tab in defaultSuperTopicTabs(expectedContainerId)) {
      result.putIfAbsent(tab.containerId.toLowerCase(), () => tab);
    }
  }

  final headCards = page.arr('cardlist_head_cards');
  if (headCards != null) {
    for (final head in headCards) {
      final channels = jObj(head)?.arr('channel_list');
      if (channels == null) continue;
      for (final channel in channels) {
        final ch = jObj(channel);
        if (ch == null) continue;
        final chId = ch.str('id');
        final cid = ch.str('containerid');
        if (chId == 'feed' ||
            cid.toLowerCase() == '${expectedContainerId}_-_feed') {
          continue;
        }
        addTab(chId, ch.str('name'), cid);
      }
    }
  }
  return result.values.toList();
}

void _collectSuperTopicCards(
  List<dynamic>? cards,
  Map<String, Status> items,
) {
  if (cards == null) return;
  void add(Map<String, dynamic>? o) {
    if (o == null || isPromotedStatus(o)) return;
    final status = Status.from(o);
    if (status != null) items.putIfAbsent(status.id, () => status);
  }

  for (final card in cards) {
    final o = jObj(card);
    if (o == null) continue;
    add(o.obj('mblog'));
    final cardType = o.str('card_type');
    if (cardType == '47') {
      final pics = o.arr('pics');
      if (pics != null) {
        for (final pic in pics) {
          add(jObj(pic)?.obj('mblog'));
        }
      }
    } else if (cardType == '52') {
      final videoItems = o.arr('items');
      if (videoItems != null) {
        for (final item in videoItems) {
          final status = _videoStatus(jObj(item));
          if (status != null) items.putIfAbsent(status.id, () => status);
        }
      }
    }
    _collectSuperTopicCards(o.arr('card_group'), items);
  }
}

Status? _videoStatus(Map<String, dynamic>? item) {
  if (item == null) return null;
  final rawScheme = _firstNonEmpty([item.str('scheme'), item.str('pic_scheme')]);
  String decodedScheme;
  try {
    decodedScheme = Uri.decodeComponent(rawScheme);
  } on Object {
    decodedScheme = rawScheme;
  }
  final mid = _superTopicVideoMid.firstMatch(decodedScheme)?[1] ?? '';
  if (mid.isEmpty) return null;
  final title = _firstNonEmpty([item.str('title'), '超话视频']);
  final author = _firstNonEmpty([item.str('desc1'), '超话视频']);
  final pic = item.str('pic');
  final duration = item.dbl('video_duration') ?? 0;
  final durationLabel = duration > 0
      ? '${(duration ~/ 60).toString().padLeft(2, '0')}:'
            '${(duration.toInt() % 60).toString().padLeft(2, '0')}'
      : '';
  return Status(
    id: mid,
    mid: mid,
    textHtml: title,
    createdAt: durationLabel,
    source: '超话视频',
    user: User(id: '', name: author, avatar: ''),
    pics: pic.isEmpty ? const [] : [Pic(thumb: pic, large: pic)],
  );
}

/// 解析「我关注的超话」或「超话广场」返回：
/// 兼容 `m.weibo.cn/api/container/getIndex`（`data.cards` / `card_group`）
/// 与 `weibo.com/ajax/profile/topicContent`（`data.list`）。
SuperTopicListPage parseSuperTopicList(
  Map<String, dynamic>? root, {
  int currentPage = 1,
}) {
  if (root == null) return const SuperTopicListPage(items: []);
  if (root.intOf('ok', 1) == -100) {
    throw ApiException('超话需要登录后查看', '-100');
  }
  final data = root.obj('data') ?? root;
  final topics = <String, SuperTopicSummary>{};

  // 格式 B：weibo.com/ajax/profile/topicContent?tabid=231093_-_chaohua
  final list = data.arr('list');
  if (list != null) {
    for (final entry in list) {
      final o = jObj(entry);
      if (o == null) continue;
      final cid =
          superTopicId(o.str('oid')) ??
          superTopicId(o.str('containerid')) ??
          superTopicId(o.str('link')) ??
          superTopicId(o.str('scheme'));
      final title = _cleanTopicTitle(_firstNonEmpty([
        o.str('title'),
        o.str('title_sub'),
        o.str('topic_name'),
      ]));
      if (cid == null || title.isEmpty) continue;
      topics.putIfAbsent(
        cid,
        () => SuperTopicSummary(
          containerId: cid,
          title: title,
          avatar: _normalizePicUrl(_firstNonEmpty([
            o.str('pic'),
            o.str('portrait_hd'),
            o.str('portrait'),
            o.str('icon'),
          ])),
          desc1: stripHtml(_firstNonEmpty([
            o.str('content1'),
            o.str('desc1'),
            o.str('desc'),
          ])).trim(),
          desc2: stripHtml(_firstNonEmpty([
            o.str('content2'),
            o.str('desc2'),
            o.str('sub_title'),
          ])).trim(),
          scheme: _firstNonEmpty([o.str('link'), o.str('scheme')]),
        ),
      );
    }
    final maxPage = data.intOf('max_page');
    final hasMore = maxPage > 0
        ? currentPage < maxPage
        : topics.isNotEmpty && data.str('next_cursor').isNotEmpty;
    return SuperTopicListPage(
      items: topics.values.toList(),
      nextCursor: hasMore ? 'page:${currentPage + 1}' : null,
    );
  }

  // 格式 A：m.weibo.cn/api/container/getIndex?containerid=100803...
  _collectSuperTopicListCards(data.arr('cards'), topics);
  final info = data.obj('cardlistInfo') ?? data.obj('pageInfo');
  final rawSince = info?.str('since_id').trim() ?? '';
  String? nextCursor;
  if (topics.isNotEmpty &&
      rawSince.isNotEmpty &&
      rawSince.toLowerCase() != 'null' &&
      !rawSince.split('').every((c) => c == '0')) {
    nextCursor = rawSince;
  } else {
    final nextPage = info?.intOf('page') ?? 0;
    if (topics.isNotEmpty && nextPage > currentPage) {
      nextCursor = 'page:$nextPage';
    }
  }
  return SuperTopicListPage(
    items: topics.values.toList(),
    nextCursor: nextCursor,
  );
}

void _collectSuperTopicListCards(
  List<dynamic>? cards,
  Map<String, SuperTopicSummary> topics,
) {
  if (cards == null) return;
  for (final card in cards) {
    final o = jObj(card);
    if (o == null || o.has('mblog')) continue;
    final scheme = o.str('scheme');
    final cid =
        superTopicId(o.str('containerid')) ??
        superTopicId(scheme) ??
        superTopicId(o.str('oid'));
    final title = _cleanTopicTitle(_firstNonEmpty([
      o.str('title_sub'),
      o.str('title'),
      o.str('item_title'),
      o.str('topic_name'),
    ]));
    if (cid != null && title.isNotEmpty) {
      topics.putIfAbsent(
        cid,
        () => SuperTopicSummary(
          containerId: cid,
          title: title,
          avatar: _normalizePicUrl(_firstNonEmpty([
            o.str('pic'),
            o.str('icon'),
            o.str('portrait_hd'),
            o.str('portrait'),
          ])),
          desc1: stripHtml(_firstNonEmpty([
            o.str('desc1'),
            o.str('desc'),
            o.str('item_desc'),
            o.str('content1'),
          ])).trim(),
          desc2: stripHtml(_firstNonEmpty([
            o.str('desc2'),
            o.str('content2'),
          ])).trim(),
          scheme: scheme,
        ),
      );
    }
    _collectSuperTopicListCards(o.arr('card_group'), topics);
    _collectSuperTopicListCards(o.arr('group'), topics);
    _collectSuperTopicListCards(o.arr('items'), topics);
  }
}

String _cleanTopicTitle(String raw) => stripHtml(raw)
    .replaceAll(RegExp(r'^#+|#+$'), '')
    .replaceAll('\u00a0', ' ')
    .trim();

String _normalizePicUrl(String raw) {
  final value = raw.trim();
  if (value.startsWith('//')) return 'https:$value';
  return value;
}

/// 综合搜索里也可能夹着原生超话卡。
List<TopicItem> parseSuperTopicSearch(Map<String, dynamic>? root) {
  if (root == null) return const [];
  if (root.intOf('ok') == -100) throw ApiException('超话需要登录后查看', '-100');
  if (root.intOf('ok') != 1) return const [];
  final topics = <String, TopicItem>{};
  _collectSuperTopicSearchCards(root.obj('data')?.arr('cards'), topics);
  return topics.values.toList();
}

void _collectSuperTopicSearchCards(
  List<dynamic>? cards,
  Map<String, TopicItem> topics,
) {
  if (cards == null) return;
  for (final card in cards) {
    final o = jObj(card);
    if (o == null || o.has('mblog')) continue;
    final scheme = o.str('scheme');
    final containerId =
        superTopicId(o.str('containerid')) ?? superTopicId(scheme);
    String titleOf(String key) => _cleanTopicTitle(o.str(key));
    var title = titleOf('title_sub');
    if (title.isEmpty) title = titleOf('title');
    if (title.isEmpty) title = titleOf('item_title');
    if (containerId != null && title.isNotEmpty) {
      topics.putIfAbsent(
        containerId,
        () => TopicItem(
          title: title,
          desc1: _firstNonEmpty([o.str('desc1'), o.str('item_desc')]),
          desc2: o.str('desc2'),
          scheme: scheme,
          containerId: containerId,
          avatar: _normalizePicUrl(_firstNonEmpty([
            o.str('pic'),
            o.str('icon'),
          ])),
        ),
      );
    }
    _collectSuperTopicSearchCards(o.arr('card_group'), topics);
    _collectSuperTopicSearchCards(o.arr('group'), topics);
  }
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) return value;
  }
  return '';
}
