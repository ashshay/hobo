import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/follow_tags.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../chrome.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';
import '../widgets/profile_header.dart';

/// 用户主页：折叠资料头 + 微博流。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.uid = '', this.showBack = true});

  /// 为空表示看自己。
  final String uid;

  /// 「我」这一栏没有上一页，不摆返回箭头。
  final bool showBack;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ScrollController _scroll = ScrollController();
  User? _user;
  FeedController? _feed;
  String _uid = '';
  bool _loading = true;
  String? _error;
  bool _following = false;
  bool _localHidden = false;

  /// 「我」这一栏和底栏共用外壳的显隐；push 进来的主页只管自己。
  bool get _isTab => !widget.showBack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isTab) context.read<ChromeController>().setHidden(false);
      _load();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setHidden(bool value) {
    if (_isTab) {
      context.read<ChromeController>().setHidden(value);
    } else if (_localHidden != value) {
      setState(() => _localHidden = value);
    }
  }

  /// 和首页一样：往下翻一屏才藏底栏，往上滑或到顶就露出来。
  void _handleScroll(double delta, bool atTop) {
    if (atTop) {
      _setHidden(false);
      return;
    }
    final pixels = _scroll.hasClients ? _scroll.position.pixels : 0;
    if (delta > 0.5 && pixels > 240) {
      _setHidden(true);
    } else if (delta < -0.5) {
      _setHidden(false);
    }
  }

  /// 下拉刷新：资料和微博流一起换新。
  Future<void> _refresh() async {
    _setHidden(false);
    final repo = context.read<Repo>();
    final feed = _feed?.refresh();
    if (_uid.isNotEmpty) {
      try {
        final user = await repo.profile(_uid, force: true);
        if (mounted && user != null) {
          setState(() {
            _user = user;
            _following = user.following;
          });
        }
      } on Object {
        // 资料刷新失败不影响微博流。
      }
    }
    await feed;
  }

  Future<void> _load() async {
    final repo = context.read<Repo>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = widget.uid.isNotEmpty ? widget.uid : await repo.ownUid();
      if (uid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final user = await repo.profile(uid);
      if (!mounted) return;
      setState(() {
        _uid = uid;
        _user = user;
        _following = user?.following ?? false;
        _loading = false;
        _feed = FeedController(
          (cursor, {required force}) =>
              repo.userStatuses(uid, sinceId: cursor, force: force),
        );
      });
      _feed?.ensureLoaded();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final repo = context.read<Repo>();
    final next = !_following;
    setState(() => _following = next);
    try {
      await repo.follow(_uid, follow: next);
      if (mounted) showHoboToast(context, next ? '已关注' : '已取消关注');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _following = !next);
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final chrome = context.watch<ChromeController>();
    if (_loading || user == null) {
      return HoboPage(
        title: user?.name ?? '主页',
        leading: widget.showBack ? const HoboBackButton() : null,
        hidden: _isTab ? chrome.hidden : _localHidden,
        body: _loading
            ? const HoboLoading(label: '正在加载主页…')
            : HoboEmpty(
                title: _error ?? '找不到这个人',
                message: '可能注销了，或者触发了风控',
                action: TextButton(onPressed: _load, child: const Text('重试')),
              ),
      );
    }
    // 资料头自己带返回 / 更多按钮，所以这一页不要 prism 的浮动顶栏：
    // 给一个零高度的 bar，body 就能从屏幕最顶上开始画封面。
    return PrismScaffold(
      bar: const _ZeroBar(),
      body: _ProfileBody(
        user: user,
        feed: _feed!,
        scrollController: _scroll,
        onScroll: _handleScroll,
        onRefresh: _refresh,
        following: _following,
        isSelf: _uid == context.read<Repo>().session?.uid,
        showBack: widget.showBack,
        actions: [
          (
            glyph: HoboGlyphs.more,
            tooltip: '更多',
            onPressed: () => _showMore(user),
          ),
          if (!widget.showBack)
            (
              glyph: HoboGlyphs.wrench,
              tooltip: '设置',
              onPressed: () => openSettings(context),
            ),
        ],
        onBack: () => Navigator.of(context).maybePop(),
        onFollow: _toggleFollow,
        onMore: () => _showMore(user),
        onOpenStatus: (status) => openStatus(context, status),
        onOpenImage: (pics, index) =>
            openImages(context, pics: pics, index: index),
        onOpenVideo: (video) => openVideo(context, video),
        onOpenRelations: (kind) => openRelations(
          context,
          uid: _uid,
          name: user.name,
          kind: kind,
        ),
        onLongPressStatus: (status) => showStatusActions(context, status),
      ),
    );
  }

  Future<void> _showMore(User user) async {
    final tags = context.read<FollowTags>();
    final current = tags.tagOf(user.id);
    final actions = <(String, VoidCallback)>[];
    final self = _uid == context.read<Repo>().session?.uid;
    if (!self && user.id.isNotEmpty) {
      actions.add(('关注', () => _toggleFollow()));
      for (final tag in FollowTag.values) {
        actions.add((
          current == tag ? '取消${tag.menuLabel}' : '标记为${tag.menuLabel}',
          () => tags.set(user.id, current == tag ? null : tag),
        ));
      }
    }
    actions.addAll([
      ('复制主页链接', () => copyText(context, 'https://m.weibo.cn/u/${user.id}')),
      ('刷新主页', () => _refresh()),
    ]);
    await showHoboActionSheet(context, title: user.name, actions: actions);
  }
}

/// 个人页不用 prism 的浮动顶栏：资料头自己画返回按钮和更多按钮，
/// 给 scaffold 一个零高度的 bar，body 就能从屏幕最顶上开始画封面。
class _ZeroBar extends StatelessWidget implements PreferredSizeWidget {
  const _ZeroBar();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.user,
    required this.feed,
    required this.scrollController,
    required this.onScroll,
    required this.onRefresh,
    required this.following,
    required this.isSelf,
    required this.showBack,
    required this.actions,
    required this.onBack,
    required this.onFollow,
    required this.onMore,
    required this.onOpenStatus,
    required this.onOpenImage,
    required this.onOpenVideo,
    required this.onOpenRelations,
    required this.onLongPressStatus,
  });

  final User user;
  final FeedController feed;
  final ScrollController scrollController;
  final void Function(double delta, bool atTop) onScroll;
  final Future<void> Function() onRefresh;
  final bool following;
  final bool isSelf;
  final bool showBack;
  final List<ProfileHeaderAction> actions;
  final VoidCallback onBack;
  final VoidCallback onFollow;
  final VoidCallback onMore;
  final ValueChanged<Status> onOpenStatus;
  final void Function(List<Pic> pics, int index) onOpenImage;
  final ValueChanged<VideoInfo> onOpenVideo;
  final ValueChanged<RelationKind> onOpenRelations;
  final ValueChanged<Status> onLongPressStatus;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return StatusList(
      controller: feed,
      scrollController: scrollController,
      onScroll: onScroll,
      onRefresh: onRefresh,
      headerSliver: SliverPersistentHeader(
        pinned: true,
        delegate: ProfileHeaderDelegate(
          topInset: topInset,
          nameLine: ProfileHeaderDelegate.nameLineOf(context),
          user: user,
          showBack: showBack,
          onBack: onBack,
          actions: actions,
        ),
      ),
      // 折叠头自己顶着顶部，列表内容从它下面开始。
      padding: EdgeInsets.fromLTRB(16, 0, 16, pageBottomInset(context)),
      refreshInset:
          topInset + ProfileHeaderDelegate.barHeight + 8,
      leading: [
        _StatsRow(
          user: user,
          isSelf: isSelf,
          following: following,
          onOpenRelations: onOpenRelations,
          onFollow: onFollow,
        ),
        if (user.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            user.description,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  fontSize: 13,
                  height: 1.4,
                  color: context.colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          '微博',
          style: AppTextStyle.headline
              .of(context)
              .copyWith(fontSize: 17, color: context.colorScheme.onSurface),
        ),
        const SizedBox(height: 8),
      ],
      onOpenStatus: onOpenStatus,
      onOpenImage: onOpenImage,
      onOpenVideo: onOpenVideo,
      onLink: (url) => handleLink(context, url),
      onLongPressStatus: onLongPressStatus,
      emptyTitle: '还没有微博',
      emptyMessage: isSelf ? '发一条试试' : null,
    );
  }
}

/// 关注 / 粉丝 / 微博三条数字，右侧是非本人的关注按钮。
class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.user,
    required this.isSelf,
    required this.following,
    required this.onOpenRelations,
    required this.onFollow,
  });

  final User user;
  final bool isSelf;
  final bool following;
  final ValueChanged<RelationKind> onOpenRelations;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Stat(
          value: '${user.friends}',
          label: '关注',
          onTap: () => onOpenRelations(RelationKind.following),
        ),
        const SizedBox(width: 22),
        _Stat(
          value: '${user.followers}',
          label: '粉丝',
          onTap: () => onOpenRelations(RelationKind.followers),
        ),
        const SizedBox(width: 22),
        _Stat(value: '${user.statuses}', label: '微博'),
        const Spacer(),
        if (!isSelf) _FollowButton(following: following, onPressed: onFollow),
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.following, required this.onPressed});

  final bool following;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: ShapeDecoration(
          color: following
              ? context.colorScheme.surfaceContainerHighest
              : context.colorScheme.primary,
          shape: AppShape.full,
        ),
        child: Text(
          following ? '已关注' : '关注',
          style: AppTextStyle.footnote
              .of(context)
              .copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: following
                    ? context.colorScheme.onSurfaceVariant
                    : context.colorScheme.onPrimary,
              ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colorScheme.onSurface,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(
                  fontSize: 12,
                  color: context.colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
