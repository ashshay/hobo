/// 微博接口的数据模型与卡片解析。
///
/// 一对一翻译自 Kotlin 版 `data/Models.kt`：字段容错规则、推广博过滤、图片/视频/
/// 转发/投票的拆解方式都保持一致，UI 只消费这里的结果。
library;

import 'html_text.dart';
import 'json.dart';
import 'links.dart';
import 'super_topic_id.dart';

enum Membership { none, vip, svip }

/// 主页上的两种关系列表：关注了谁、谁在关注。
enum RelationKind { following, followers }

class User {
  const User({
    required this.id,
    required this.name,
    this.avatar = '',
    this.verified = false,
    this.following = false,
    this.description = '',
    this.followers = 0,
    this.friends = 0,
    this.statuses = 0,
    this.covers = const [],
    this.specialFollow = false,
    this.mbtype = 0,
    this.mbrank = 0,
    this.svip = false,
  });

  final String id;
  final String name;
  final String avatar;
  final bool verified;
  final bool following;
  final String description;
  final int followers;
  final int friends;
  final int statuses;

  /// 主页封面原图；官方号常配好几张轮播，接口里用 `;` 拼在一起。
  final List<String> covers;

  /// 当前登录者是否把这个用户设成了「特别关注」。
  final bool specialFollow;
  final int mbtype;
  final int mbrank;
  final bool svip;

  Membership get membership {
    if (mbtype <= 2 || mbrank <= 0) return Membership.none;
    return svip ? Membership.svip : Membership.vip;
  }

  User copyWith({
    String? name,
    String? avatar,
    bool? verified,
    bool? following,
    String? description,
    int? followers,
    int? friends,
    int? statuses,
    List<String>? covers,
    bool? specialFollow,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      verified: verified ?? this.verified,
      following: following ?? this.following,
      description: description ?? this.description,
      followers: followers ?? this.followers,
      friends: friends ?? this.friends,
      statuses: statuses ?? this.statuses,
      covers: covers ?? this.covers,
      specialFollow: specialFollow ?? this.specialFollow,
      mbtype: mbtype,
      mbrank: mbrank,
      svip: svip,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'screen_name': name,
    'avatar_large': avatar,
    'verified': verified,
    'following': following,
    'description': description,
    'followers_count': followers,
    'follow_count': friends,
    'statuses_count': statuses,
    'special_follow': specialFollow,
    'mbtype': mbtype,
    'mbrank': mbrank,
    'svip': svip ? 1 : 0,
  };

  static User? from(Map<String, dynamic>? o) {
    if (o == null) return null;
    final id = o.str('id');
    if (id.isEmpty) return null;
    return User(
      id: id,
      name: o.str('screen_name'),
      avatar: firstNonEmpty([
        o.str('avatar_hd'),
        o.str('avatar_large'),
        o.str('profile_image_url'),
        o.str('avatar'),
      ]),
      verified: o.boolean('verified'),
      following: o.boolean('following'),
      description: o.str('description'),
      followers: o.count('followers_count', o.count('followers_count_str')),
      friends: o.intOf(
        'follow_count',
        o.intOf('friends_count', o.count('friends_count_str')),
      ),
      statuses: o.count('statuses_count'),
      covers: coverUrls(o.str('cover_image_phone')),
      specialFollow: o.boolean('special_follow'),
      mbtype: o.intOf('mbtype'),
      mbrank: o.intOf('mbrank'),
      svip: o.intOf('svip') > 0,
    );
  }
}

String firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) return value;
  }
  return '';
}

final _coverCrop = RegExp(r'^(https?://[^/]+)/crop\.[^/]+/(.+)$');

/// `cover_image_phone` 给的是 640 方图的裁剪地址，拆开后把裁剪段换成 `large` 拿原图。
List<String> coverUrls(String raw) {
  if (raw.trim().isEmpty) return const [];
  final out = <String>[];
  for (final part in raw.split(';')) {
    final url = part.trim();
    if (!url.startsWith('http')) continue;
    final replaced = url.replaceFirstMapped(
      _coverCrop,
      (m) => '${m[1]}/large/${m[2]}',
    );
    if (!out.contains(replaced)) out.add(replaced);
  }
  return out;
}

class Pic {
  const Pic({
    required this.thumb,
    required this.large,
    this.width = 0,
    this.height = 0,
    this.live = '',
  });

  final String thumb;
  final String large;
  final int width;
  final int height;

  /// 实况图（`type=livephoto`）附带的短视频；静图、GIF 都是空串。
  final String live;

  bool get isLive => live.isNotEmpty;
}

/// 实况视频地址：m.weibo.cn 放在 videoSrc，weibo.com 的 pic_infos 放在 video。
String liveVideoUrl(Map<String, dynamic> pic) {
  if (pic.str('type').toLowerCase() != 'livephoto') return '';
  final raw = firstNonEmpty([
    pic.str('videoSrc'),
    pic.str('video'),
    pic.str('video_hd'),
  ]);
  return livePlayUrl(raw);
}

/// 裸 mov 直接请求 403，要先走 video.weibo.com 的播放页拿签名地址。已签名的原样返回。
String livePlayUrl(String raw) {
  if (raw.isEmpty) return '';
  if (raw.contains('livephoto=') ||
      raw.contains('Expires=') ||
      raw.contains('ssig=')) {
    return raw;
  }
  final absolute = raw.startsWith('//') ? 'https:$raw' : raw;
  final path = absolute.split('?').first;
  if (!absolute.contains('sinaimg.cn') || !path.endsWith('.mov')) {
    return absolute;
  }
  return 'https://video.weibo.com/media/play?livephoto=${Uri.encodeComponent(absolute)}';
}

/// 一条微博 / 一条评论的配图。
///
/// 微博在不同接口里给图的字段不一样，按可信度依次尝试：
///
/// 1. `pics[]` —— 正文与部分评论用的数组。**注意**：评论里的 `pics` 有时只放一条
///    视频占位（`url` 是 `https://ss1.sinaimg.cn/orj360/&690`，请求 404），
///    真正的图在 `pic` 里，所以这里要跳过占位项，不能见到 `pics` 就返回；
/// 2. `pic` —— 单张图评论（`m.weibo.cn/comments/hotflow` 的图片评论就是这个结构）；
/// 3. `pic_ids` + `pic_infos` —— weibo.com 那套，`pic_infos` 缺项时按 id 拼地址兜底。
///
/// 最后按 `large` 去重：同一条评论可能同时给出 `pic` 与 `pics`，别渲染成两张。
List<Pic> picsOf(Map<String, dynamic> o) {
  final out = <Pic>[];
  final seen = <String>{};

  void add(Pic? pic) {
    if (pic == null) return;
    final key = pic.large.isNotEmpty ? pic.large : pic.thumb;
    if (key.isEmpty || !seen.add(key)) return;
    out.add(pic);
  }

  final arr = o.arr('pics');
  if (arr != null) {
    for (final item in arr) {
      final map = jObj(item);
      if (map == null || _isPlaceholderPic(map)) continue;
      add(_picOf(map));
    }
  }

  add(_picOf(o.obj('pic')));

  final ids = o.arr('pic_ids');
  if (ids != null) {
    final infos = o.obj('pic_infos');
    for (final item in ids) {
      final id = jStr(item);
      if (id.isEmpty) continue;
      final parsed = _picOf(infos?.obj(id));
      if (parsed != null) {
        add(parsed);
      } else {
        add(
          Pic(
            thumb: 'https://wx1.sinaimg.cn/orj360/$id.jpg',
            large: 'https://wx1.sinaimg.cn/large/$id.jpg',
          ),
        );
      }
    }
  }
  return out;
}

/// 视频 / 实况占位：`url` 里没有真实文件名，只有 `&690` 这类占位串，请求必 404。
/// 这类条目交给视频播放器，不该进图片网格。
bool _isPlaceholderPic(Map<String, dynamic> p) {
  final url = firstNonEmpty([
    p.str('url'),
    p.obj('large')?.str('url') ?? '',
  ]);
  if (url.isEmpty) return true;
  final path = Uri.tryParse(url)?.path ?? url;
  final name = path.split('/').last;
  // 正常图片名形如 `0092j2IYgy1ij7ljfblb3j30j60tr7e4.jpg`；
  // 占位项是 `&690`，没有扩展名也没有 id。
  return !name.contains('.') || name.startsWith('&');
}

Pic? _picOf(Map<String, dynamic>? p) {
  if (p == null) return null;
  final large = p.obj('large') ?? p.obj('largest');
  final url = firstNonEmpty([p.str('url'), large?.str('url') ?? '']);
  if (url.isEmpty && large == null) return null;
  final geo = large?.obj('geo') ?? p.obj('geo');
  return Pic(
    thumb: firstNonEmpty([url, large?.str('url') ?? '']),
    large: firstNonEmpty([large?.str('url') ?? '', url]),
    width: geo?.intOf('width') ?? large?.intOf('width') ?? p.intOf('width'),
    height: geo?.intOf('height') ?? large?.intOf('height') ?? p.intOf('height'),
    live: liveVideoUrl(p),
  );
}

/// 视频的一档清晰度。微博的 `media_info` 与 `playback_list` 里同一段视频会给出
/// 好几条地址，这里统一成「标签 + 直链 + 分辨率」。
class VideoQuality {
  const VideoQuality({
    required this.label,
    required this.url,
    this.width = 0,
    this.height = 0,
    this.size = 0,
  });

  final String label;
  final String url;
  final int width;
  final int height;
  final int size;

  /// 选择器里的副标题：`1280×720 · 12.3 MB`。
  String get detail => [
    if (width > 0 && height > 0) '$width×$height',
    if (size > 0) '${(size / (1024 * 1024)).toStringAsFixed(1)} MB',
  ].join(' · ');
}

class VideoInfo {
  const VideoInfo({
    required this.title,
    required this.cover,
    required this.url,
    this.qualities = const [],
  });

  final String title;
  final String cover;
  final String url;

  /// 可选清晰度，从高到低；[url] 是默认那一档。只有一档时播放页不显示切换。
  final List<VideoQuality> qualities;

  /// [url] 对应的那一档；对不上时退回第一档。
  VideoQuality? get current {
    for (final quality in qualities) {
      if (quality.url == url) return quality;
    }
    return qualities.isEmpty ? null : qualities.first;
  }
}

class BigPicInfo {
  const BigPicInfo({required this.url, this.scheme = ''});

  final String url;
  final String scheme;
}

class VoteOption {
  const VoteOption({
    required this.id,
    required this.title,
    this.pic = '',
    this.partNum = '',
    this.partRatio = 0,
    this.selected = false,
  });

  final String id;
  final String title;
  final String pic;
  final String partNum;
  final double partRatio;
  final bool selected;

  /// 保留一位小数，整数比例不带 `.0`。
  String get ratioLabel {
    final tenths = (partRatio * 10).round();
    return tenths % 10 == 0
        ? '${tenths ~/ 10}%'
        : '${tenths ~/ 10}.${tenths % 10}%';
  }
}

class VoteInfo {
  const VoteInfo({
    required this.id,
    required this.title,
    this.sk = '',
    this.status = 1,
    this.isMultiSelect = false,
    this.maxSelect = 1,
    this.endTimeStr = '',
    this.partNum = 0,
    this.parted = false,
    this.options = const [],
    this.author,
  });

  final String id;
  final String title;
  final String sk;
  final int status;
  final bool isMultiSelect;
  final int maxSelect;
  final String endTimeStr;
  final int partNum;
  final bool parted;
  final List<VoteOption> options;
  final User? author;

  bool get isExpired => status == 0;

  /// 接口的截止文案自带「截止时间」前缀；其它形式原样展示。
  String get deadlineLabel {
    final text = endTimeStr.trim();
    if (text.startsWith('截止时间')) {
      return '${text.substring('截止时间'.length).trim()} 截止';
    }
    return text;
  }

  bool get hasVoted => parted || options.any((o) => o.selected);
}

String? extractVoteId(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final byQuery = RegExp(r'vote_id=([0-9a-zA-Z_\-]+)').firstMatch(text);
  if (byQuery != null) return byQuery[1];
  final byPage = RegExp(r'231716([0-9a-zA-Z_\-]+)').firstMatch(text);
  if (byPage != null) return byPage[1];
  return null;
}

String? extractVoteIdFromUrlStruct(List<dynamic>? arr) {
  if (arr == null) return null;
  for (final item in arr) {
    final o = jObj(item);
    if (o == null) continue;
    for (final field in const [
      'ori_url',
      'long_url',
      'h5_target_url',
      'page_id',
    ]) {
      final id = extractVoteId(o.str(field));
      if (id != null) return id;
    }
  }
  return null;
}

VoteInfo parseVoteInfoJson(
  String voteId,
  String sk,
  Map<String, dynamic> vi, {
  User? fallbackAuthor,
}) {
  User? author = fallbackAuthor;
  final authorObj = vi.obj('launch_userinfo');
  if (authorObj != null) {
    author = User(
      id: authorObj.str('uid'),
      name: authorObj.str('name'),
      avatar: firstNonEmpty([
        authorObj.str('avatar_large'),
        authorObj.str('avatar'),
      ]),
      svip:
          authorObj.str('logo').contains('gold') ||
          authorObj.str('logo').contains('vip'),
    );
  }

  final options = <VoteOption>[];
  final optArr = vi.arr('option_list') ?? vi.arr('vote_list');
  if (optArr != null) {
    for (final item in optArr) {
      final opt = jObj(item);
      if (opt == null) continue;
      final ratio = opt.dbl('part_ratio') ?? 0;
      final normalized = ratio >= 0 && ratio <= 1 ? ratio * 100 : ratio;
      options.add(
        VoteOption(
          id: opt.str('id'),
          title: firstNonEmpty([opt.str('title'), opt.str('content')]),
          pic: opt.str('pic'),
          partNum: opt.str('part_num'),
          partRatio: normalized,
          selected: opt.intOf('selected') > 0,
        ),
      );
    }
  }

  final limited = vi.intOf('limited', vi.intOf('maximum', 1));
  return VoteInfo(
    id: firstNonEmpty([vi.str('id'), voteId]),
    title: firstNonEmpty([vi.str('title'), vi.str('content')]),
    sk: sk,
    status: vi.intOf('status', vi.intOf('state', 1)),
    isMultiSelect: limited > 1 || vi.intOf('is_multi_select') > 0,
    maxSelect: limited,
    endTimeStr: firstNonEmpty([vi.str('end_time_str'), vi.str('show_str')]),
    partNum: vi.intOf('part_num', vi.intOf('part_info')),
    parted: vi.intOf('parted') > 0,
    options: options,
    author: author,
  );
}

/// 微博发布/可见范围：0 公开、1 仅自己、2 密友、3 指定分组、6 仅好友、10 仅粉丝。
class StatusVisibility {
  const StatusVisibility({
    required this.type,
    required this.label,
    this.listId = '',
  });

  final int type;
  final String label;
  final String listId;

  bool get isPublic => type == 0;
}

bool _isVisibilityTitle(String title) {
  return title == '公开' ||
      title == '好友圈' ||
      title == '私密' ||
      title.contains('可见') ||
      title.contains('好友') ||
      title.contains('自己') ||
      title.contains('粉丝') ||
      title.contains('密友') ||
      title.contains('分组');
}

String defaultVisibilityLabel(int type, [String hint = '']) {
  const defaults = {
    0: '公开',
    1: '仅自己可见',
    2: '密友可见',
    3: '指定分组可见',
    6: '仅好友可见',
    10: '仅粉丝可见',
  };
  if (type == 0) return '公开';
  final value = defaults[type] ?? '部分可见';
  return hint.isEmpty ? value : hint;
}

StatusVisibility? parseStatusVisibility(Map<String, dynamic> o) {
  final visObj = o.obj('visible');
  final rawTitle = (o.obj('title')?.str('text') ?? '').trim();
  final visibilityTitle =
      rawTitle.isNotEmpty && _isVisibilityTitle(rawTitle) ? rawTitle : '';

  if (visObj == null) {
    if (visibilityTitle.isEmpty) return null;
    return switch (visibilityTitle) {
      '公开' => const StatusVisibility(type: 0, label: '公开'),
      '仅自己可见' || '私密' => const StatusVisibility(type: 1, label: '仅自己可见'),
      '仅好友可见' || '好友圈' => StatusVisibility(
        type: 6,
        label: visibilityTitle,
      ),
      _ => StatusVisibility(type: -1, label: visibilityTitle),
    };
  }

  final type = visObj.intOf('type');
  final rawListId = firstNonEmpty([
    visObj.str('list_idstr'),
    visObj.str('list_id'),
  ]);
  final listId = rawListId.isNotEmpty && rawListId != '0' ? rawListId : '';
  return StatusVisibility(
    type: type,
    label: defaultVisibilityLabel(type, visibilityTitle),
    listId: listId,
  );
}

class Status {
  const Status({
    required this.id,
    required this.mid,
    required this.textHtml,
    required this.createdAt,
    required this.source,
    this.user,
    this.pics = const [],
    this.video,
    this.bigPic,
    this.retweeted,
    this.reposts = 0,
    this.comments = 0,
    this.attitudes = 0,
    this.liked = false,
    this.favorited = false,
    this.region = '',
    this.editCount = 0,
    this.isVote = false,
    this.voteId,
    this.visibility,
  });

  final String id;
  final String mid;
  final String textHtml;
  final String createdAt;
  final String source;
  final User? user;
  final List<Pic> pics;
  final VideoInfo? video;
  final BigPicInfo? bigPic;
  final Status? retweeted;
  final int reposts;
  final int comments;
  final int attitudes;
  final bool liked;
  final bool favorited;
  final String region;
  final int editCount;
  final bool isVote;
  final String? voteId;
  final StatusVisibility? visibility;

  String get plainText => stripHtml(textHtml);

  Status copyWith({
    bool? liked,
    bool? favorited,
    int? attitudes,
    int? comments,
    int? reposts,
    User? user,
  }) {
    return Status(
      id: id,
      mid: mid,
      textHtml: textHtml,
      createdAt: createdAt,
      source: source,
      user: user ?? this.user,
      pics: pics,
      video: video,
      bigPic: bigPic,
      retweeted: retweeted,
      reposts: reposts ?? this.reposts,
      comments: comments ?? this.comments,
      attitudes: attitudes ?? this.attitudes,
      liked: liked ?? this.liked,
      favorited: favorited ?? this.favorited,
      region: region,
      editCount: editCount,
      isVote: isVote,
      voteId: voteId,
      visibility: visibility,
    );
  }

  Map<String, dynamic> toJson() {
    final pageInfo = <String, dynamic>{
      if (video != null) ...{
        'type': 'video',
        'page_title': video!.title,
        'page_pic': {'url': video!.cover},
        'media_info': {'stream_url_hd': video!.url},
      } else if (bigPic != null) ...{
        'type': 'bigPic',
        'page_pic': {'url': bigPic!.url, 'scheme': bigPic!.scheme},
      },
    };
    return {
      'id': id,
      'mid': mid,
      'text': textHtml,
      'created_at': createdAt,
      'source': source,
      'user': user?.toJson(),
      'pics': [
        for (final pic in pics)
          {
            'url': pic.thumb,
            'large': {'url': pic.large},
            'width': pic.width,
            'height': pic.height,
            if (pic.live.isNotEmpty) 'videoSrc': pic.live,
            if (pic.live.isNotEmpty) 'type': 'livephoto',
          },
      ],
      if (pageInfo.isNotEmpty) 'page_info': pageInfo,
      if (retweeted != null) 'retweeted_status': retweeted!.toJson(),
      'reposts_count': reposts,
      'comments_count': comments,
      'attitudes_count': attitudes,
      'liked': liked,
      'favorited': favorited,
      'region_name': region,
      'edit_count': editCount,
      'is_vote': isVote ? 1 : 0,
      'vote_id': voteId,
    };
  }

  static Status? from(Map<String, dynamic>? o) => _parseStatus(o, 0);
}

Status? _parseStatus(Map<String, dynamic>? o, int depth) {
  if (o == null) return null;
  final id = o.str('id');
  if (id.isEmpty) return null;
  final pics = picsOf(o);

  VideoInfo? video;
  final page = o.obj('page_info');
  if (page != null &&
      (page.str('type') == 'video' || page.str('object_type') == 'video')) {
    final media = page.obj('media_info');
    final urls = page.obj('urls');
    final directUrl = firstNonEmpty([
      media?.str('stream_url_hd') ?? '',
      media?.str('stream_url') ?? '',
      media?.str('mp4_720p_mp4') ?? '',
      media?.str('mp4_hd_url') ?? '',
      media?.str('mp4_sd_url') ?? '',
      _firstPlaybackUrl(media?.arr('playback_list')),
      urls?.str('mp4_720p_mp4') ?? '',
      urls?.str('mp4_hd_mp4') ?? '',
      urls?.str('mp4_ld_mp4') ?? '',
      urls?.str('hevc_mp4_hd') ?? '',
      urls?.str('stream_url_hd') ?? '',
      urls?.str('stream_url') ?? '',
    ]);
    final fallbackPageUrl = firstNonEmpty([
      media?.str('h5_url') ?? '',
      page.str('page_url'),
      page.obj('page_pic')?.str('scheme') ?? '',
      page.str('object_id').isNotEmpty
          ? 'https://video.weibo.com/show?fid=${page.str('object_id')}'
          : '',
    ]);
    final resolvedUrl = directUrl.isNotEmpty
        ? directUrl
        : (unwrapSinaUrl(fallbackPageUrl) ?? fallbackPageUrl);
    final cover = page.obj('page_pic')?.str('url') ?? '';
    video = VideoInfo(
      title: firstNonEmpty([page.str('page_title'), page.str('content1')]),
      cover: firstNonEmpty([cover, pics.isNotEmpty ? pics.first.thumb : '']),
      url: resolvedUrl,
      qualities: _videoQualities(media, urls),
    );
  } else if (page != null && pics.isEmpty) {
    final pageUrlRaw = firstNonEmpty([
      page.str('page_url'),
      page.obj('page_pic')?.str('scheme') ?? '',
    ]);
    final pageUrl = unwrapSinaUrl(pageUrlRaw) ?? pageUrlRaw;
    final resolvedTarget = resolveWeiboLink(pageUrl) ?? pageUrl;
    if (isVideoLink(resolvedTarget)) {
      video = VideoInfo(
        title: firstNonEmpty([page.str('page_title'), page.str('content1')]),
        cover: page.obj('page_pic')?.str('url') ?? '',
        url: resolvedTarget,
      );
    }
  }

  BigPicInfo? bigPic;
  if (page != null &&
      (page.str('type') == 'bigPic' || page.str('object_type') == 'bigPic')) {
    final pagePic = page.obj('page_pic');
    final picUrl = firstNonEmpty([
      pagePic?.str('url') ?? '',
      page.str('page_pic'),
    ]);
    if (picUrl.isNotEmpty) {
      bigPic = BigPicInfo(
        url: picUrl,
        scheme: firstNonEmpty([
          pagePic?.str('scheme') ?? '',
          page.str('page_url'),
        ]),
      );
    }
  }

  final retweeted = depth < 2
      ? _parseStatus(o.obj('retweeted_status'), depth + 1)
      : null;

  String? voteId;
  if (page != null) {
    final cardInfo = page.obj('card_info');
    final voteObj = cardInfo?.obj('vote_object');
    final rawId = voteObj?.str('id') ?? '';
    voteId = rawId.isEmpty ? null : rawId;
    voteId ??= extractVoteId(page.str('page_url'));
  }
  voteId ??= extractVoteIdFromUrlStruct(o.arr('url_struct'));
  voteId ??= extractVoteId(o.str('text'));

  final isVote =
      o.intOf('is_vote') == 1 ||
      page?.str('object_type') == 'hudongvote' ||
      page?.str('type') == '23' ||
      voteId != null;

  return Status(
    id: id,
    mid: firstNonEmpty([o.str('mid'), id]),
    textHtml: o.str('text'),
    createdAt: normalizeWeiboTime(o.str('created_at')),
    source: stripHtml(o.str('source')),
    user: User.from(o.obj('user')),
    pics: pics,
    video: video,
    bigPic: bigPic,
    retweeted: retweeted,
    reposts: o.intOf('reposts_count'),
    comments: o.intOf('comments_count'),
    attitudes: o.intOf('attitudes_count'),
    liked: o.boolean('liked'),
    favorited: o.boolean('favorited'),
    region: o.str('region_name'),
    editCount: o.intOf('edit_count'),
    isVote: isVote,
    voteId: voteId,
    visibility: parseStatusVisibility(o),
  );
}

String _firstPlaybackUrl(List<dynamic>? arr) {
  if (arr == null) return '';
  var fallback = '';
  for (final item in arr) {
    final play = jObj(item)?.obj('play_info');
    if (play == null) continue;
    final url = play.str('url');
    if (url.isEmpty) continue;
    if (fallback.isEmpty) fallback = url;
    final mime = play.str('mime');
    if (mime.toLowerCase().contains('mp4') || url.contains('.mp4')) {
      return url;
    }
  }
  return fallback;
}

/// 同一段视频的几档地址：`playback_list` 带标签与分辨率，`media_info` 的
/// `mp4_*` / `stream_url*` 只有档位名，按 URL 去重后从高到低排。
List<VideoQuality> _videoQualities(
  Map<String, dynamic>? media,
  Map<String, dynamic>? urls,
) {
  final out = <VideoQuality>[];

  void add(
    String label,
    String url, {
    int width = 0,
    int height = 0,
    int size = 0,
  }) {
    final value = url.trim();
    if (value.isEmpty || out.any((quality) => quality.url == value)) return;
    out.add(
      VideoQuality(
        label: label,
        url: value,
        width: width,
        height: height,
        size: size,
      ),
    );
  }

  final playback = media?.arr('playback_list');
  if (playback != null) {
    for (final item in playback) {
      final play = jObj(item)?.obj('play_info');
      if (play == null) continue;
      final height = play.intOf('height');
      add(
        firstNonEmpty([
          play.str('label'),
          play.str('quality_label'),
          _qualityLabelOf(height),
        ]),
        play.str('url'),
        width: play.intOf('width'),
        height: height,
        size: play.intOf('size'),
      );
    }
  }

  String pick(String key) => firstNonEmpty([
    media?.str(key) ?? '',
    urls?.str(key) ?? '',
  ]);

  add('超清', pick('mp4_1080p_mp4'));
  add(
    '高清',
    firstNonEmpty([
      pick('mp4_720p_mp4'),
      pick('stream_url_hd'),
      pick('mp4_hd_url'),
      pick('mp4_hd_mp4'),
      pick('hevc_mp4_hd'),
    ]),
  );
  add(
    '标清',
    firstNonEmpty([pick('mp4_sd_url'), pick('mp4_ld_mp4'), pick('stream_url')]),
  );

  // 有分辨率的按高度排，其余保持接口顺序（接口本身是从高到低给的）。
  final ranked = out.where((quality) => quality.height > 0).toList()
    ..sort((a, b) => b.height.compareTo(a.height));
  final rest = out.where((quality) => quality.height <= 0).toList();
  return [...ranked, ...rest];
}

String _qualityLabelOf(int height) => switch (height) {
  >= 1080 => '超清',
  >= 720 => '高清',
  >= 480 => '标清',
  > 0 => '流畅',
  _ => '视频',
};

class EditVersion {
  const EditVersion({
    required this.createdAt,
    this.textHtml = '',
    this.pics = const [],
    this.note = '',
  });

  final String createdAt;
  final String textHtml;
  final List<String> pics;

  /// 只改了可见范围的编辑记录没有正文，这里放一行说明。
  final String note;

  static EditVersion? from(Map<String, dynamic>? o) {
    if (o == null) return null;
    final note = o.has('history_type') ? stripHtml(o.str('text')) : '';
    final text = note.isEmpty ? o.str('text') : '';
    final ids = o.arr('pic_ids');
    final pics = <String>[];
    if (ids != null) {
      for (final id in ids) {
        final value = jStr(id);
        if (value.isNotEmpty) pics.add('https://wx1.sinaimg.cn/large/$value.jpg');
      }
    }
    if (note.isEmpty && text.isEmpty && pics.isEmpty) return null;
    return EditVersion(
      createdAt: normalizeWeiboTime(o.str('created_at')),
      textHtml: text,
      pics: pics,
      note: note,
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    this.textHtml = '',
    this.user,
    this.createdAt = '',
    this.likes = 0,
    this.liked = false,
    this.reply,
    this.replies = const [],
    this.replyCount = 0,
    this.source = '',
    this.region = '',
    this.pics = const [],
  });

  final String id;
  final String textHtml;
  final User? user;
  final String createdAt;
  final int likes;
  final bool liked;
  final Comment? reply;

  /// 一楼层里内联展示的几条回复，按时间正序。
  final List<Comment> replies;

  /// 这一楼一共多少条回复；[replies] 只是预览。
  final int replyCount;

  /// 评论来源（「来自 湖北」「来自 iPhone客户端」这类），去掉 HTML 后的纯文本。
  final String source;

  /// 评论 IP 属地。
  final String region;

  /// 评论附带的配图。微博的图片评论走 `pic_ids` + `pic_infos`，和正文同一套结构。
  final List<Pic> pics;

  String get plainText => stripHtml(textHtml);

  Comment copyWith({
    bool? liked,
    int? likes,
    List<Comment>? replies,
    int? replyCount,
    List<Pic>? pics,
  }) {
    return Comment(
      id: id,
      textHtml: textHtml,
      user: user,
      createdAt: createdAt,
      likes: likes ?? this.likes,
      liked: liked ?? this.liked,
      reply: reply,
      replies: replies ?? this.replies,
      replyCount: replyCount ?? this.replyCount,
      source: source,
      region: region,
      pics: pics ?? this.pics,
    );
  }

  static Comment? from(Map<String, dynamic>? o, {int depth = 0}) {
    if (o == null) return null;
    final id = o.str('id');
    if (id.isEmpty) return null;
    final children = depth < 1 ? o.arr('comments') : null;
    final replies = <Comment>[];
    if (children != null) {
      for (final child in children) {
        final parsed = from(jObj(child), depth: depth + 1);
        if (parsed != null) replies.add(parsed);
      }
    }
    return Comment(
      id: id,
      textHtml: o.str('text'),
      user: User.from(o.obj('user')),
      createdAt: normalizeWeiboTime(o.str('created_at')),
      likes: o.has('like_count')
          ? o.intOf('like_count')
          : o.intOf('like_counts'),
      liked: o.boolean('liked'),
      reply: depth < 1 ? from(o.obj('reply'), depth: depth + 1) : null,
      replies: replies,
      replyCount: o.intOf('total_number', replies.length),
      source: stripHtml(o.str('source')),
      region: o.str('region_name'),
      pics: picsOf(o),
    );
  }
}

class FeedPage {
  const FeedPage(this.items, this.sinceId);

  final List<Status> items;
  final String? sinceId;

  bool get isEmpty => items.isEmpty;
}

/// 评论排序：热门榜（游标翻页）与按时间（页码翻页）。
enum CommentSort { hot, time }

class CommentPage {
  const CommentPage(this.items, this.maxId, this.maxIdType, [this.nextPage = 0]);

  final List<Comment> items;
  final String maxId;
  final int maxIdType;
  final int nextPage;
}

class HotItem {
  const HotItem({
    required this.title,
    this.scheme = '',
    this.label = '',
    this.rank = 0,
  });

  final String title;
  final String scheme;
  final String label;
  final int rank;
}

/// 热搜的榜单，`filterType` 就是容器认的 `filter_type`。
enum HotBoard {
  realtime('全部热搜', 'realtimehot'),
  fun('文娱', 'fun'),
  social('社会', 'social'),
  life('生活', 'lifenav'),
  mine('个性化', 'mineband');

  const HotBoard(this.label, this.filterType);

  final String label;
  final String filterType;

  String get singleTitle =>
      label.endsWith('热搜') ? label : '$label热搜';

  static HotBoard? fromFilterType(String key) {
    for (final board in values) {
      if (board.filterType == key) return board;
    }
    return null;
  }
}

class TopicItem {
  const TopicItem({
    required this.title,
    this.desc1 = '',
    this.desc2 = '',
    this.scheme = '',
    this.containerId,
  });

  final String title;
  final String desc1;
  final String desc2;
  final String scheme;
  final String? containerId;
}

class MessageItem {
  const MessageItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.user,
    this.unread = 0,
    this.scheme = '',
    this.gid = '',
  });

  final String id;
  final String text;
  final String createdAt;
  final User? user;
  final int unread;
  final String scheme;

  /// 群聊会话的 gid；一对一私信为空串。
  final String gid;
}

/// 会话 scheme 里的群聊 id：一对一私信是 `/message/chat?uid=`，群聊是 `?gid=`。
String chatGidOf(String scheme) {
  final questionAt = scheme.indexOf('?');
  if (questionAt < 0) return '';
  final query = scheme.substring(questionAt + 1);
  for (final part in query.split('&')) {
    if (part.startsWith('gid=')) {
      final value = part.substring(4);
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    this.text = '',
    this.senderId = '',
    this.recipientId = '',
    this.createdAt = '',
    this.mediaType = 0,
    this.dmType = 0,
    this.imageUrl = '',
    this.thumbUrl = '',
    this.width = 0,
    this.height = 0,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String text;
  final String senderId;
  final String recipientId;
  final String createdAt;
  final int mediaType;
  final int dmType;
  final String imageUrl;
  final String thumbUrl;
  final int width;
  final int height;

  /// 本地乐观发送的那条：服务端回来的消息两者都是 false。
  final bool pending;
  final bool failed;

  bool get isImage =>
      mediaType == 1 && (imageUrl.isNotEmpty || thumbUrl.isNotEmpty);

  bool get isNotice => dmType == 9;

  ChatMessage copyWith({bool? pending, bool? failed}) {
    return ChatMessage(
      id: id,
      text: text,
      senderId: senderId,
      recipientId: recipientId,
      createdAt: createdAt,
      mediaType: mediaType,
      dmType: dmType,
      imageUrl: imageUrl,
      thumbUrl: thumbUrl,
      width: width,
      height: height,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
    );
  }

  static ChatMessage? from(Map<String, dynamic>? o) {
    if (o == null) return null;
    final id = o.str('id');
    if (id.isEmpty) return null;
    final attachment = o.obj('attachment');
    final original = attachment?.obj('original_image');
    final fromUser = o.obj('from_user');
    return ChatMessage(
      id: id,
      text: o.str('text'),
      senderId: firstNonEmpty([o.str('sender_id'), fromUser?.str('id') ?? '']),
      recipientId: o.str('recipient_id'),
      createdAt: normalizeWeiboTime(o.str('created_at')),
      mediaType: o.intOf('media_type'),
      dmType: o.intOf('dm_type'),
      imageUrl: original?.str('url') ?? '',
      thumbUrl: attachment?.obj('thumbnail')?.str('url') ?? '',
      width: original?.intOf('width') ?? 0,
      height: original?.intOf('height') ?? 0,
    );
  }
}

class ChatPage {
  const ChatPage({
    required this.messages,
    required this.users,
    required this.title,
    required this.total,
  });

  final List<ChatMessage> messages;
  final Map<String, User> users;
  final String title;
  final int total;

  static const empty = ChatPage(messages: [], users: {}, title: '', total: 0);

  /// 群聊接口返回旧→新，这里统一翻成最新在前，界面只认一种顺序。
  static ChatPage parse(Map<String, dynamic> data, {required bool isGroup}) {
    final messages = <ChatMessage>[];
    final arr = data.arr('msgs');
    if (arr != null) {
      for (final item in arr) {
        final message = ChatMessage.from(jObj(item));
        if (message != null) messages.add(message);
      }
    }
    if (isGroup) {
      final reversed = messages.reversed.toList();
      messages
        ..clear()
        ..addAll(reversed);
    }
    final users = <String, User>{};
    final userObj = data.obj('users');
    if (userObj != null) {
      for (final entry in userObj.entries) {
        final user = User.from(jObj(entry.value));
        if (user != null) users[entry.key] = user;
      }
    }
    return ChatPage(
      messages: messages,
      users: users,
      title: data.str('title'),
      total: data.intOf('total_number'),
    );
  }
}

class FollowGroup {
  const FollowGroup(this.gid, this.title);

  final String gid;
  final String title;
}

class Account {
  const Account({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.cookie,
    this.gsid = '',
    this.gsidAt = 0,
  });

  final String uid;
  final String name;
  final String avatar;
  final String cookie;

  /// 客户端登录拿到的会话 id；网页登录的账号为空。
  final String gsid;
  final int gsidAt;
}

class Draft {
  const Draft(this.text, this.time);

  final String text;
  final int time;
}

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.mid,
    required this.text,
    required this.user,
    required this.time,
    this.html = '',
  });

  final String id;
  final String mid;
  final String text;
  final String user;
  final int time;

  /// 详情页正文的原始 HTML，历史列表靠它还原表情与链接。
  final String html;
}

/// 登录态。[cookies] 是「域名 → 该域名下的 cookie」表。
class Session {
  const Session({
    required this.cookie,
    required this.uid,
    required this.savedAt,
    this.gsid = '',
    this.gsidAt = 0,
    this.accessToken = '',
    this.expires = 0,
    this.source = 'web',
    this.loginType = 0,
    this.cookies = const {},
  });

  final String cookie;
  final String uid;
  final int savedAt;
  final String gsid;
  final int gsidAt;
  final String accessToken;
  final int expires;
  final String source;
  final int loginType;
  final Map<String, String> cookies;

  /// 有没有 `SUB` 才是真的登录了。
  bool get loggedIn => cookie.contains('SUB=');

  Session copyWith({String? cookie, Map<String, String>? cookies}) {
    return Session(
      cookie: cookie ?? this.cookie,
      uid: uid,
      savedAt: savedAt,
      gsid: gsid,
      gsidAt: gsidAt,
      accessToken: accessToken,
      expires: expires,
      source: source,
      loginType: loginType,
      cookies: cookies ?? this.cookies,
    );
  }
}

class Config {
  const Config(this.uid, this.st, this.loggedIn);

  final String uid;
  final String st;
  final bool loggedIn;

  static const empty = Config('', '', false);
}

/// 服务端塞进时间线的推广博：`mark` 里带 `reallog_mark_ad` / `WeiboAD`。
bool isPromotedStatus(Map<String, dynamic> o) {
  final mark = o.str('mark');
  return mark.contains('reallog_mark_ad') || mark.contains('WeiboAD');
}

List<Status> statusesOf(List<dynamic>? arr) {
  if (arr == null) return const [];
  final items = <Status>[];
  for (final item in arr) {
    final o = jObj(item);
    if (o == null || isPromotedStatus(o)) continue;
    final status = Status.from(o);
    if (status != null) items.add(status);
  }
  return items;
}

/// 热搜榜条目：广告位的 `itemid` 带 `is_ad_pos`，整条跳过，排名自然顺延。
List<HotItem> parseHotItems(Map<String, dynamic>? root) {
  final cards = root?.obj('data')?.arr('cards');
  if (cards == null) return const [];
  final out = <HotItem>[];
  for (final card in cards) {
    final group = jObj(card)?.arr('card_group');
    if (group == null) continue;
    for (final item in group) {
      final g = jObj(item);
      if (g == null) continue;
      if (g.str('itemid').contains('is_ad_pos')) continue;
      final title = firstNonEmpty([g.str('desc'), g.str('title_sub')]);
      if (title.isEmpty) continue;
      out.add(
        HotItem(
          title: title,
          scheme: g.str('scheme'),
          label: g.str('card_type_name'),
          rank: out.length + 1,
        ),
      );
    }
  }
  return out;
}

/// 时间线卡片 → 微博列表（`cards[].mblog` 与 `card_group[].mblog` 都认）。
FeedPage parseCards(Map<String, dynamic>? root) {
  final data = root?.obj('data');
  final items = <Status>[];
  final cards = data?.arr('cards');
  if (cards != null) {
    for (final card in cards) {
      final o = jObj(card);
      if (o == null) continue;
      final mblog = o.obj('mblog');
      if (mblog != null && !isPromotedStatus(mblog)) {
        final status = Status.from(mblog);
        if (status != null) items.add(status);
      }
      final group = o.arr('card_group');
      if (group != null) {
        for (final item in group) {
          final inner = jObj(item)?.obj('mblog');
          if (inner == null || isPromotedStatus(inner)) continue;
          final status = Status.from(inner);
          if (status != null) items.add(status);
        }
      }
    }
  }
  final since = data?.obj('cardlistInfo')?.str('since_id') ?? '';
  return FeedPage(items, since.isEmpty ? null : since);
}

/// 用户搜索结果：用户挂在 `cards[].card_group[].user`，简介/粉丝数可能只在 desc 上。
List<User> parseUserCards(Map<String, dynamic>? root) {
  final data = root?.obj('data');
  if (data == null) return const [];
  final users = <String, User>{};
  final cards = data.arr('cards');
  if (cards == null) return const [];

  User? searchUserOf(Map<String, dynamic> item) {
    final user = User.from(item.obj('user'));
    if (user == null) return null;
    final description = firstNonEmpty([item.str('desc1'), user.description]);
    var followers = user.followers;
    if (followers <= 0) {
      final raw = item.str('desc2');
      final at = raw.indexOf('粉丝');
      final value = at >= 0 ? raw.substring(at + 2) : '';
      followers = parseCount(value.replaceAll(RegExp(r'^[：:\s]+'), '')) ?? 0;
    }
    return user.copyWith(description: description, followers: followers);
  }

  for (final card in cards) {
    final o = jObj(card);
    if (o == null) continue;
    final single = searchUserOf(o);
    if (single != null) users.putIfAbsent(single.id, () => single);
    final group = o.arr('card_group');
    if (group == null) continue;
    for (final item in group) {
      final inner = jObj(item);
      if (inner == null) continue;
      final user = searchUserOf(inner);
      if (user != null) users.putIfAbsent(user.id, () => user);
    }
  }
  return users.values.toList();
}

/// 关注 / 粉丝列表：只认 `card_type` 11 且没有 `card_style` 的那几张。
List<User> parseRelationUsers(Map<String, dynamic>? root) {
  final data = root?.obj('data');
  if (data == null) return const [];
  final cards = data.arr('cards');
  if (cards == null) return const [];
  final users = <String, User>{};
  for (final card in cards) {
    final o = jObj(card);
    if (o == null) continue;
    if (o.intOf('card_type') != 11 ||
        (o.has('card_style') && o.opt('card_style') != null)) {
      continue;
    }
    final single = User.from(o.obj('user'));
    if (single != null) users.putIfAbsent(single.id, () => single);
    final group = o.arr('card_group');
    if (group == null) continue;
    for (final item in group) {
      final inner = jObj(item);
      if (inner == null) continue;
      final user = User.from(inner.obj('user'));
      if (user == null) continue;
      users.putIfAbsent(
        user.id,
        () => user.copyWith(
          description: firstNonEmpty([inner.str('desc1'), user.description]),
        ),
      );
    }
  }
  return users.values.toList();
}

/// 话题搜索结果：`card_group` 里 `title_sub` 是 `#话题#`，desc 是阅读与讨论数。
List<TopicItem> parseTopicCards(Map<String, dynamic>? root) {
  final data = root?.obj('data');
  if (data == null) return const [];
  final cards = data.arr('cards');
  if (cards == null) return const [];
  final topics = <String, TopicItem>{};
  for (final card in cards) {
    final o = jObj(card);
    if (o == null) continue;
    final group = o.arr('card_group');
    if (group == null) continue;
    for (final item in group) {
      final inner = jObj(item);
      if (inner == null) continue;
      final title = inner
          .str('title_sub')
          .replaceAll(RegExp(r'^#+|#+$'), '')
          .replaceAll('\u00a0', ' ')
          .trim();
      if (title.isEmpty) continue;
      final scheme = inner.str('scheme');
      final containerId =
          superTopicId(inner.str('containerid')) ?? superTopicId(scheme);
      final key = containerId ?? (scheme.isEmpty ? title : scheme);
      if (topics.containsKey(key)) continue;
      topics[key] = TopicItem(
        title: title,
        desc1: inner.str('desc1'),
        desc2: inner.str('desc2'),
        scheme: scheme,
        containerId: containerId,
      );
    }
  }
  return topics.values.toList();
}

/// 关注分组表：只认「我的分组」下的项，固定组（特别关注等）另有入口。
List<FollowGroup> parseFollowGroups(Map<String, dynamic>? root) {
  final categories = root?.arr('groups');
  if (categories == null) return const [];
  final groups = <String, FollowGroup>{};
  for (final category in categories) {
    final o = jObj(category);
    if (o == null || o.str('title') != '我的分组') continue;
    final items = o.arr('group');
    if (items == null) continue;
    for (final item in items) {
      final g = jObj(item);
      if (g == null) continue;
      final gid = firstNonEmpty([g.str('gid'), g.str('id')]);
      final title = g.str('title');
      if (gid.isEmpty || title.isEmpty) continue;
      if (title == '特别关注' || title == '互相关注' || title == '悄悄关注') {
        continue;
      }
      groups.putIfAbsent(gid, () => FollowGroup(gid, title));
    }
  }
  return groups.values.toList();
}

class NearbyPlace {
  const NearbyPlace(this.name, this.lat, this.lon);

  final String name;
  final double lat;
  final double lon;
}

final _nearbyScheme = RegExp(r'qiehuan_\d+_([\d.]+)_([\d.]+)');

/// 城市链接里的坐标：`qiehuan_<id>_<经度>_<纬度>`。
List<NearbyPlace> parseNearbyPlaces(Map<String, dynamic>? root) {
  final cards = root?.obj('data')?.arr('cards');
  if (cards == null) return const [];
  final places = <String, NearbyPlace>{};

  void add(String? name, String? scheme) {
    if (name == null || scheme == null || name.isEmpty || scheme.isEmpty) {
      return;
    }
    String decoded;
    try {
      decoded = Uri.decodeComponent(scheme);
    } on Object {
      decoded = scheme;
    }
    final match = _nearbyScheme.firstMatch(decoded);
    if (match == null) return;
    final lon = double.tryParse(match[1]!);
    final lat = double.tryParse(match[2]!);
    if (lon == null || lat == null) return;
    if (lon == 0 && lat == 0) return;
    final label = name.trim();
    places.putIfAbsent(label, () => NearbyPlace(label, lat, lon));
  }

  for (final card in cards) {
    final groups = jObj(card)?.arr('card_group');
    if (groups == null) continue;
    for (final group in groups) {
      final o = jObj(group);
      if (o == null) continue;
      final tags = o.obj('profile_tag')?.arr('tags');
      if (tags != null) {
        for (final tag in tags) {
          final t = jObj(tag);
          if (t == null) continue;
          add(t.str('display_name'), t.str('tag_scheme'));
        }
      }
      final items = o.arr('group');
      if (items == null) continue;
      for (final item in items) {
        final i = jObj(item);
        if (i == null) continue;
        add(i.str('title_sub'), i.str('scheme'));
      }
    }
  }
  return places.values.toList();
}

/// 微博时间 → 毫秒时间戳。
///
/// 认毫秒数、`EEE MMM dd HH:mm:ss Z yyyy`，以及 m.weibo.cn 那几种人读格式：
/// `刚刚` / `3分钟前` / `今天 10:23` / `昨天 10:23` / `11-19 10:23` / `2025-11-19`。
int? weiboTimeMillis(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return numeric;
  final absolute = _parseWeiboDate(text);
  if (absolute != null) return absolute.millisecondsSinceEpoch;
  return _parseRelativeWeiboDate(text)?.millisecondsSinceEpoch;
}

/// 接口给的 `created_at` 可能是「1小时前」这种相对串：解析时立刻换算成绝对时间戳，
/// 否则列表在内存里放几小时后还写着「1小时前」。
String normalizeWeiboTime(String raw) {
  final millis = weiboTimeMillis(raw);
  return millis == null ? raw : '$millis';
}

/// 微博时间 → 相对时间。
String formatWeiboTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final millis = weiboTimeMillis(raw);
  if (millis == null) return raw;
  final diff = DateTime.now().millisecondsSinceEpoch - millis;
  if (diff < 60000) return '刚刚';
  if (diff < 3600000) return '${diff ~/ 60000}分钟前';
  if (diff < 86400000) return '${diff ~/ 3600000}小时前';
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  if (date.year == now.year) return '$month-$day';
  return '${date.year}-$month-$day';
}

/// 准确发布时间：今天只给 `10:23`，今年给 `11-19 10:23`，跨年带年份。
String formatWeiboTimeExact(String? raw) {
  final millis = weiboTimeMillis(raw);
  if (millis == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final clock =
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return clock;
  }
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  if (date.year == now.year) return '$month-$day $clock';
  return '${date.year}-$month-$day $clock';
}

/// 卡片上写的是「刚刚 / N分钟前 / N小时前」这类相对时间时，才需要再补一条准确时间。
bool isRelativeWeiboTime(String? raw) {
  final millis = weiboTimeMillis(raw);
  if (millis == null) return false;
  return DateTime.now().millisecondsSinceEpoch - millis < 86400000;
}

/// `刚刚` / `N秒前` / `N分钟前` / `N小时前` / `今天 10:23` / `11-19 10:23`。
DateTime? _parseRelativeWeiboDate(String text) {
  final now = DateTime.now();
  if (text == '刚刚' || text == '现在') return now;

  final relative = RegExp(r'^(\d+)\s*(秒|分钟|小时|天)前$').firstMatch(text);
  if (relative != null) {
    final value = int.tryParse(relative[1]!) ?? 0;
    final unit = switch (relative[2]) {
      '秒' => Duration(seconds: value),
      '分钟' => Duration(minutes: value),
      '小时' => Duration(hours: value),
      _ => Duration(days: value),
    };
    return now.subtract(unit);
  }

  final day = RegExp(r'^(今天|昨天|前天)\s*(\d{1,2}):(\d{2})$').firstMatch(text);
  if (day != null) {
    final back = switch (day[1]) {
      '昨天' => 1,
      '前天' => 2,
      _ => 0,
    };
    final base = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: back));
    return DateTime(
      base.year,
      base.month,
      base.day,
      int.parse(day[2]!),
      int.parse(day[3]!),
    );
  }

  final monthDay = RegExp(
    r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?$',
  ).firstMatch(text);
  if (monthDay != null) {
    final month = int.parse(monthDay[1]!);
    final dayOfMonth = int.parse(monthDay[2]!);
    final hour = int.tryParse(monthDay[3] ?? '') ?? 0;
    final minute = int.tryParse(monthDay[4] ?? '') ?? 0;
    var date = DateTime(now.year, month, dayOfMonth, hour, minute);
    // 1 月里看到 12-31，说的是去年。
    if (date.isAfter(now.add(const Duration(days: 1)))) {
      date = DateTime(now.year - 1, month, dayOfMonth, hour, minute);
    }
    return date;
  }

  final full = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(text);
  if (full != null) {
    return DateTime(
      int.parse(full[1]!),
      int.parse(full[2]!),
      int.parse(full[3]!),
      int.tryParse(full[4] ?? '') ?? 0,
      int.tryParse(full[5] ?? '') ?? 0,
      int.tryParse(full[6] ?? '') ?? 0,
    );
  }
  return null;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

DateTime? _parseWeiboDate(String text) {
  final parts = text.split(RegExp(r'\s+'));
  if (parts.length < 6) return null;
  // Mon Nov 17 10:23:45 +0800 2025
  final month = _months[parts[1].toLowerCase()];
  final day = int.tryParse(parts[2]);
  final time = parts[3].split(':');
  if (month == null || day == null || time.length < 3) return null;
  final hour = int.tryParse(time[0]);
  final minute = int.tryParse(time[1]);
  final second = int.tryParse(time[2]);
  final year = int.tryParse(parts[5]);
  if (hour == null || minute == null || second == null || year == null) {
    return null;
  }
  var offset = Duration.zero;
  final zone = parts[4];
  if (zone.length == 5 && (zone.startsWith('+') || zone.startsWith('-'))) {
    final zoneHour = int.tryParse(zone.substring(1, 3)) ?? 0;
    final zoneMinute = int.tryParse(zone.substring(3, 5)) ?? 0;
    offset = Duration(hours: zoneHour, minutes: zoneMinute);
    if (zone.startsWith('-')) offset = -offset;
  }
  final local = DateTime.utc(year, month, day, hour, minute, second);
  return local.subtract(offset);
}
