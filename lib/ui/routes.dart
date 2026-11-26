import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/follow_tags.dart';
import '../data/links.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../data/store.dart';
import '../data/super_topic_id.dart';
import 'nav.dart';
import 'pages/chat_page.dart' as chat;
import 'pages/compose_page.dart';
import 'pages/detail_page.dart';
import 'pages/dock_glass_settings_page.dart';
import 'pages/edit_history_page.dart';
import 'pages/font_settings_page.dart';
import 'pages/image_viewer_page.dart';
import 'pages/library_pages.dart';
import 'pages/login_page.dart';
import 'pages/messages_page.dart';
import 'pages/nearby_page.dart';
import 'pages/profile_page.dart';
import 'pages/relations_page.dart';
import 'pages/replies_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/super_topic_hub_page.dart';
import 'pages/super_topic_page.dart';
import 'pages/video_page.dart';
import 'pages/vote_page.dart';
import 'pages/web_page.dart';
import 'widgets/common.dart';

void openStatus(BuildContext context, Status status) {
  openStatusById(context, status.id, status.mid, status: status);
}

void openStatusById(
  BuildContext context,
  String id,
  String mid, {
  Status? status,
}) {
  if (id.isEmpty) return;
  // 详情页自己会回源，所以这里只带 id/mid。
  status;
  pushPage(context, DetailPage(statusId: id, mid: mid));
}

void openUser(BuildContext context, User user) {
  if (user.id.isEmpty) return;
  openUserById(context, user.id);
}

void openUserById(BuildContext context, String uid) {
  if (uid.isEmpty) return;
  pushPage(context, ProfilePage(uid: uid));
}

void openImages(
  BuildContext context, {
  required List<Pic> pics,
  int index = 0,
  double sourceCornerRadius = AppCorner.md,
}) {
  if (pics.isEmpty) return;
  Navigator.of(context).push<void>(
    ImageViewerRoute(
      pics: pics,
      initialIndex: index.clamp(0, pics.length - 1),
      sourceCornerRadius: sourceCornerRadius,
    ),
  );
}

void openVideo(BuildContext context, VideoInfo video) {
  if (video.url.isEmpty) return;
  pushPage(context, VideoPage(video: video));
}

void openSearch(BuildContext context, {String query = ''}) {
  pushPage(context, SearchPage(initialQuery: query));
}

void openTopic(BuildContext context, String query) {
  pushPage(context, TopicPage(query: query));
}

Future<void> openSuperTopic(BuildContext context, String containerId) {
  final id = normalizedSuperTopicId(containerId) ?? containerId;
  return pushPage(context, SuperTopicScreen(containerId: id));
}

void openSuperTopicHub(BuildContext context) {
  pushPage(context, const SuperTopicHubPage());
}

void openVote(BuildContext context, String voteId, {Status? status}) {
  pushPage(context, VotePage(voteId: voteId, status: status));
}

void openWeb(BuildContext context, String url, {String title = '网页'}) {
  if (url.isEmpty) return;
  pushPage(context, WebPage(url: url, title: title));
}

void openLogin(BuildContext context, {bool addAccount = false}) {
  pushPage(context, LoginPage(addAccount: addAccount));
}

Future<bool?> openCompose(BuildContext context, {String initialText = ''}) {
  final repo = context.read<Repo>();
  if (!repo.hasSession()) {
    showHoboToast(context, '纯本地模式不能发微博，登录后可用', level: BannerLevel.warning);
    openLogin(context);
    return Future<bool?>.value();
  }
  return pushPage<bool>(context, ComposePage(initialText: initialText));
}

void openSettings(BuildContext context) {
  pushPage(context, SettingsPage());
}

void openFontSettings(BuildContext context) {
  pushPage(context, const FontSettingsPage());
}

void openDockGlassSettings(BuildContext context) {
  pushPage(context, const DockGlassSettingsPage(), dragBack: false);
}

void openAccounts(BuildContext context) {
  pushPage(context, AccountsPage());
}

void openFavorites(BuildContext context) {
  pushPage(context, FavoritesPage());
}

void openHistory(BuildContext context) {
  pushPage(context, HistoryPage());
}

void openDrafts(BuildContext context) {
  pushPage(context, DraftsPage());
}

void openAbout(BuildContext context) {
  pushPage(context, AboutPage());
}

void openNearby(BuildContext context) {
  pushPage(context, NearbyPage());
}

void openNearbyCities(BuildContext context) {
  pushPage(context, NearbyCitiesPage());
}

void openChat(
  BuildContext context, {
  required String uid,
  required String gid,
  required String name,
  String avatar = '',
}) {
  pushPage(
    context,
    chat.ChatPage(uid: uid, gid: gid, name: name, avatar: avatar),
  );
}

void openMessages(BuildContext context) {
  pushPage(context, MessagesPage());
}

void openRelations(
  BuildContext context, {
  required String uid,
  required String name,
  required RelationKind kind,
}) {
  pushPage(
    context,
    RelationsPage(uid: uid, name: name, kind: kind),
  );
}

void openEditHistory(BuildContext context, String mid) {
  if (mid.isEmpty) return;
  pushPage(context, EditHistoryPage(mid: mid));
}

/// 「共 N 条回复」：展开这一层的全部回复。
void openReplies(
  BuildContext context, {
  required String statusId,
  required String mid,
  required Comment comment,
  String authorId = '',
}) {
  pushPage(
    context,
    RepliesPage(
      statusId: statusId,
      mid: mid,
      comment: comment,
      authorId: authorId,
    ),
  );
}

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  showHoboToast(context, '已复制');
}

/// 正文里的链接最终该进哪个页面。
Future<void> handleLink(BuildContext context, String raw) async {
  var url = raw.trim();
  if (url.isEmpty) return;
  url = unwrapSinaUrl(url) ?? url;
  final resolved = resolveWeiboLink(url) ?? url;
  final repo = context.read<Repo>();

  final superTopic = superTopicId(resolved);
  if (superTopic != null) {
    openSuperTopic(context, superTopic);
    return;
  }
  final statusId = weiboStatusId(resolved);
  if (statusId != null) {
    openStatusById(context, statusId, statusId);
    return;
  }
  final uid = weiboUserId(resolved);
  if (uid != null) {
    openUserById(context, uid);
    return;
  }
  final mention =
      weiboMentionName(resolved) ??
      (url.startsWith('@') && url.length > 1 ? url.substring(1).trim() : null);
  if (mention != null && mention.isNotEmpty) {
    String? found;
    try {
      found = await repo.uidForName(mention);
    } on Object {
      found = null;
    }
    if (context.mounted) {
      if (found != null && found.isNotEmpty) {
        openUserById(context, found);
      } else {
        openSearch(context, query: '@$mention');
      }
    }
    return;
  }
  final topic = weiboTopicQuery(resolved);
  if (topic != null) {
    openTopic(context, topic);
    return;
  }
  final voteId = extractVoteId(resolved);
  if (voteId != null) {
    openVote(context, voteId);
    return;
  }
  if (isImageLink(resolved)) {
    openImages(
      context,
      pics: [Pic(thumb: resolved, large: resolved)],
    );
    return;
  }
  if (isVideoLink(resolved)) {
    openVideo(context, VideoInfo(title: '', cover: '', url: resolved));
    return;
  }
  if (isWeiboShortLink(resolved)) {
    final target = await repo.resolveShortUrl(resolved);
    if (context.mounted) {
      if (target != resolved) {
        await handleLink(context, target);
      } else {
        openWeb(context, resolved);
      }
    }
    return;
  }
  if (context.mounted) openWeb(context, resolved);
}

/// 微博卡片的「更多」：收藏、复制、编辑记录、标记、删除。
Future<void> showStatusActions(BuildContext context, Status status) async {
  final repo = context.read<Repo>();
  final tags = context.read<FollowTags>();
  final store = context.read<Store>();
  final favorited = repo.isFavorited(status.id) || status.favorited;
  final own = repo.session?.uid.isNotEmpty == true &&
      repo.session?.uid == status.user?.id;
  final tag = tags.tagOf(status.user?.id ?? '');
  final actions = <(String, VoidCallback)>[
    (
      favorited ? '取消收藏' : '收藏',
      () async {
        try {
          await repo.favorite(status.id, favorited: favorited);
          if (context.mounted) {
            showHoboToast(context, favorited ? '已取消收藏' : '已收藏');
          }
        } on Object catch (e) {
          if (context.mounted) {
            showHoboToast(context, e.toString(), level: BannerLevel.error);
          }
        }
      },
    ),
    (
      '复制正文',
      () => copyText(context, status.plainText),
    ),
    (
      '复制链接',
      () => copyText(context, 'https://m.weibo.cn/detail/${status.id}'),
    ),
    if (status.editCount > 0)
      (
        '编辑记录',
        () => openEditHistory(context, status.mid),
      ),
    if (status.user != null && status.user!.id.isNotEmpty)
      (
        tag == FollowTag.special ? '取消特别关注' : '标记特别关注',
        () {
          tags.set(
            status.user!.id,
            tag == FollowTag.special ? null : FollowTag.special,
          );
          showHoboToast(
            context,
            tag == FollowTag.special ? '已取消特别关注' : '已标记特别关注',
          );
        },
      ),
    if (own)
      (
        '删除这条微博',
        () async {
          final ok = await showHoboConfirm(
            context,
            title: '删除这条微博？',
            destructive: true,
            confirmText: '删除',
          );
          if (ok != true) return;
          if (!context.mounted) return;
          try {
            await repo.deleteStatus(status.id, mid: status.mid);
            if (context.mounted) showHoboToast(context, '已删除');
          } on Object catch (e) {
            if (context.mounted) {
              showHoboToast(context, e.toString(), level: BannerLevel.error);
            }
          }
        },
      ),
    if (store.isFavorite(status.id))
      ('移出本地收藏', () {
        store.removeFavorite(status.id);
        showHoboToast(context, '已移出收藏');
      }),
  ];
  await showHoboActionSheet(context, title: '更多操作', actions: actions);
}
