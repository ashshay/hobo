import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/follow_tags.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../chrome.dart';
import '../routes.dart';
import '../theme.dart' show formatCount;
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';
import '../widgets/image_actions.dart';
import '../widgets/pager.dart';
import '../widgets/profile_about.dart';
import '../widgets/profile_album.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_status_grid.dart';
import '../widgets/profile_tabs.dart';
import '../widgets/refresh.dart';
import '../widgets/status_card.dart';

/// 用户主页：折叠资料头 + 可滑动切换胶囊分类（关于 / 微博 / 相册 / 精选 / 视频）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.uid = '', this.showBack = true});

  /// 为空表示看自己。
  final String uid;

  /// 「我」这一栏没有上一页，不摆返回箭头。
  final bool showBack;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _introKey = GlobalKey();
  final Map<ProfileTab, double> _tabOffsets = {};

  ProfileTab _tab = ProfileTab.weibo;
  ProfileFilter _filter = ProfileFilter.all;

  /// 胶囊分类条与个人页横向滑动共用同一条弹簧。
  late final HoboPagerController _pager = HoboPagerController(
    vsync: this,
    initialPage: _tab.index,
    count: ProfileTab.values.length,
  );

  /// 「微博」栏目的列表 / 网格。
  bool _grid = false;

  User? _user;
  String _uid = '';
  bool _loading = true;
  String? _error;
  bool _following = false;
  bool _localHidden = false;

  FeedController? _feed;
  FeedController? _featured;
  FeedController? _video;
  AlbumController? _album;

  double _lastPixels = 0;
  bool _loadQueued = false;
  bool _fillQueued = false;
  bool _restoringScroll = false;
  double _swipeDx = 0;
  double _swipeFrom = 0;

  /// 「我」这一栏和底栏共用外壳的显隐；push 进来的主页只管自己。
  bool get _isTab => !widget.showBack;

  bool get _disableAnimations =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  bool get _isSelf =>
      _uid.isNotEmpty && _uid == context.read<Repo>().session?.uid;

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
    _pager.dispose();
    _feed?.dispose();
    _featured?.dispose();
    _video?.dispose();
    _album?.dispose();
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
    if (_restoringScroll) return;
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

  // ---- 数据 ----

  void _onControllersChanged() {
    if (mounted) setState(() {});
  }

  T _attach<T extends ChangeNotifier>(T controller) {
    controller.addListener(_onControllersChanged);
    return controller;
  }

  /// 第一次切到某个栏目时才建它的控制器，别一进主页就把四个接口全打一遍。
  void _ensureTab(ProfileTab tab) {
    final repo = context.read<Repo>();
    switch (tab) {
      case ProfileTab.about:
        break;
      case ProfileTab.weibo:
        _feed?.ensureLoaded();
        break;
      case ProfileTab.featured:
        _featured ??= _attach(
          FeedController.paged(
            (page, {required force}) =>
                repo.userFeatured(_uid, page: page, force: force),
          ),
        );
        _featured!.ensureLoaded();
        break;
      case ProfileTab.video:
        _video ??= _attach(
          FeedController(
            (cursor, {required force}) =>
                repo.userVideos(_uid, sinceId: cursor, force: force),
          ),
        );
        _video!.ensureLoaded();
        break;
      case ProfileTab.album:
        _album ??= _attach(
          AlbumController(
            (cursor, {required force}) =>
                repo.userPhotos(_uid, sinceId: cursor, force: force),
          ),
        );
        _album!.ensureLoaded();
        break;
    }
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
      final feed = _attach(
        FeedController(
          (cursor, {required force}) =>
              repo.userStatuses(uid, sinceId: cursor, force: force),
        ),
      );
      setState(() {
        _uid = uid;
        _user = user;
        _following = user?.following ?? false;
        _loading = false;
        _feed = feed;
      });
      feed.ensureLoaded();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 下拉刷新：资料和当前栏目一起换新。
  Future<void> _refresh() async {
    _setHidden(false);
    final repo = context.read<Repo>();
    final tasks = <Future<void>>[];
    if (_uid.isNotEmpty) {
      tasks.add(() async {
        try {
          final user = await repo.profile(_uid, force: true);
          if (!mounted || user == null) return;
          setState(() {
            _user = user;
            _following = user.following;
          });
        } on Object {
          // 资料刷新失败不影响微博流。
        }
      }());
    }
    final tabTask = switch (_tab) {
      ProfileTab.weibo => _feed?.refresh(),
      ProfileTab.featured => _featured?.refresh(),
      ProfileTab.video => _video?.refresh(),
      ProfileTab.album => _album?.refresh(),
      ProfileTab.about => null,
    };
    if (tabTask != null) tasks.add(tabTask);
    await Future.wait(tasks);
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

  // ---- 栏目切换 ----

  double _pinnedOffset() {
    final topInset = MediaQuery.paddingOf(context).top;
    final nameLine = ProfileHeaderDelegate.nameLineOf(context);
    final headerRange =
        ProfileHeaderDelegate.expandedExtent(topInset, nameLine) -
        ProfileHeaderDelegate.collapsedExtent(topInset);
    final introBox =
        _introKey.currentContext?.findRenderObject() as RenderBox?;
    return headerRange + (introBox?.size.height ?? 0);
  }

  void _selectTab(ProfileTab tab, {bool syncPager = true}) {
    if (tab == _tab) return;
    final previous = _tab;
    final pinnedOffset = _pinnedOffset();
    final wasPinned = _scroll.hasClients && _scroll.offset > pinnedOffset;
    if (wasPinned) {
      _tabOffsets[previous] = _scroll.offset;
    }
    setState(() => _tab = tab);
    if (syncPager &&
        (!_pager.isAnimating || (_pager.targetPage - tab.index).abs() > 0.01)) {
      _pager.goToPage(
        tab.index,
        velocity: _pager.velocity,
        animate: !_disableAnimations,
      );
    }
    _ensureTab(tab);
    _setHidden(false);
    if (wasPinned) {
      final target = _tabOffsets[tab] ?? pinnedOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final pos = _scroll.position;
        final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
        if ((pos.pixels - clamped).abs() < 0.5) return;
        _restoringScroll = true;
        try {
          _scroll.jumpTo(clamped);
          _lastPixels = clamped;
        } finally {
          _restoringScroll = false;
        }
      });
    }
  }

  void _onSwipeStart(DragStartDetails details) {
    _swipeDx = 0;
    _swipeFrom = _pager.page;
    _pager.beginDrag();
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    _swipeDx += details.delta.dx;
    _pager.dragTo(
      _swipeFrom - _swipeDx / width,
      velocity: -details.delta.dx * 60 / width,
      animate: !_disableAnimations,
    );
  }

  void _onSwipeEnd(DragEndDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final velocity = width > 0 ? -(details.primaryVelocity ?? 0) / width : 0.0;
    _swipeDx = 0;
    final landed = _pager.endDrag(velocity, animate: !_disableAnimations);
    final next = ProfileTab.values[landed];
    if (next != _tab) {
      HapticFeedback.selectionClick();
      _selectTab(next, syncPager: false);
    }
  }

  void _onSwipeCancel() {
    _swipeDx = 0;
    _pager.endDrag(0, animate: !_disableAnimations);
  }

  Future<void> _pickFilter() async {
    await showHoboActionSheet(
      context,
      title: '筛选微博',
      actions: [
        for (final filter in ProfileFilter.values)
          (
            filter == _filter ? '✓ ${filter.label}' : filter.label,
            () {
              if (!mounted) return;
              setState(() => _filter = filter);
            },
          ),
      ],
    );
  }

  void _toggleGrid() => setState(() => _grid = !_grid);

  /// 筛选到「视频」「图片」这类少见的类型时，第一页可能一条都不匹配。
  /// 内容为空就自动续页，直到列表里有东西或者真的到底。
  void _ensureFilteredContent(FeedController feed) {
    if (_filter == ProfileFilter.all ||
        feed.loading ||
        feed.loadingMore ||
        feed.atEnd ||
        feed.error != null ||
        _fillQueued) {
      return;
    }
    if (_filter.apply(feed.items).isNotEmpty) return;
    _fillQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fillQueued = false;
      if (!mounted || _tab != ProfileTab.weibo) return;
      if (_filter.apply(feed.items).isEmpty &&
          !feed.atEnd &&
          feed.error == null) {
        feed.loadMore();
      }
    });
  }

  // ---- 滚动到底加载下一页 ----

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      final delta = pixels - _lastPixels;
      _lastPixels = pixels;
      if (delta.abs() > 0.5) {
        _handleScroll(delta, pixels <= 8);
      }
    } else if (notification is ScrollEndNotification) {
      _handleScroll(0, notification.metrics.pixels <= 8);
    }
    if (notification.metrics.extentAfter < 600) {
      _scheduleLoadMore();
    }
    return false;
  }

  /// 滚动通知有时是在布局里派发的，这期间控制器一 notify 就是「帧内调度重建」，
  /// 所以把续页推到帧末。
  void _scheduleLoadMore() {
    if (_loadQueued) return;
    _loadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQueued = false;
      if (!mounted) return;
      final controller = switch (_tab) {
        ProfileTab.weibo => _feed,
        ProfileTab.featured => _featured,
        ProfileTab.video => _video,
        ProfileTab.album => _album,
        ProfileTab.about => null,
      };
      if (controller is FeedController) controller.loadMore();
      if (controller is AlbumController) controller.loadMore();
    });
  }

  // ---- 交互 ----

  void _openStatus(Status status) => openStatus(context, status);

  void _openUser(User user) => openUserById(context, user.id);

  void _openPhoto(int index) {
    final photos = _album?.photos ?? const <AlbumPhoto>[];
    if (index < 0 || index >= photos.length) return;
    final photo = photos[index];
    if (photo.isVideo && photo.mid.isNotEmpty) {
      openStatusById(context, photo.mid, photo.mid);
      return;
    }
    final pics = <Pic>[];
    var start = 0;
    for (var i = 0; i < photos.length; i++) {
      if (photos[i].isVideo) continue;
      if (i == index) start = pics.length;
      pics.add(photos[i].toPic().withHeroTag('album:${photos[i].pid}'));
    }
    if (pics.isEmpty) return;
    openImages(context, pics: pics, index: start, sourceCornerRadius: 3);
  }

  void _longPressPhoto(int index) {
    final photos = _album?.photos ?? const <AlbumPhoto>[];
    if (photos.isEmpty) return;
    showImageActions(
      context,
      pics: [for (final photo in photos) photo.toPic()],
      index: index,
    );
  }

  void _openRelations(RelationKind kind) =>
      openRelations(context, uid: _uid, name: _user?.name ?? '', kind: kind);

  void _copyLink() => copyText(context, 'https://m.weibo.cn/u/$_uid');

  void _openLinkInBrowser() => openWeb(
    context,
    'https://m.weibo.cn/u/$_uid',
    title: _user?.name ?? '主页',
  );

  // ---- 构建 ----

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
    final topInset = MediaQuery.paddingOf(context).top;
    final actions = <ProfileHeaderAction>[
      (glyph: HoboGlyphs.more, tooltip: '更多', onPressed: () => _showMore(user)),
      if (!widget.showBack)
        (
          glyph: HoboGlyphs.wrench,
          tooltip: '设置',
          onPressed: () => openSettings(context),
        ),
    ];
    return PrismScaffold(
      bar: const _ZeroBar(),
      body: HoboRefresh(
        onRefresh: _refresh,
        topInset: topInset + ProfileHeaderDelegate.barHeight + 8,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _onSwipeStart,
          onHorizontalDragUpdate: _onSwipeUpdate,
          onHorizontalDragEnd: _onSwipeEnd,
          onHorizontalDragCancel: _onSwipeCancel,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ProfileHeaderDelegate(
                    topInset: topInset,
                    nameLine: ProfileHeaderDelegate.nameLineOf(context),
                    user: user,
                    showBack: widget.showBack,
                    onBack: () => Navigator.of(context).maybePop(),
                    actions: actions,
                  ),
                ),
                SliverToBoxAdapter(child: _intro(user)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ProfileTabBarDelegate(
                    selected: _tab,
                    weiboCount: user.statuses,
                    pageController: _pager,
                    onSelect: _selectTab,
                  ),
                ),
                for (final sliver in _contentSlivers(user))
                  _SliverSlide(
                    pager: _pager,
                    index: _tab.index,
                    enabled: !_disableAnimations,
                    sliver: sliver,
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(height: pageBottomInset(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(User user) {
    return Padding(
      key: _introKey,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatsRow(
            user: user,
            isSelf: _isSelf,
            following: _following,
            onOpenRelations: _openRelations,
            onFollow: _toggleFollow,
          ),
          if (user.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              user.description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(
                    fontSize: 13,
                    height: 1.4,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _contentSlivers(User user) {
    return switch (_tab) {
      ProfileTab.about => [
        SliverToBoxAdapter(
          child: ProfileAbout(
            user: user,
            isSelf: _isSelf,
            onOpenRelations: _openRelations,
            onCopyLink: _copyLink,
            onOpenWeb: _openLinkInBrowser,
            onRefresh: _refresh,
          ),
        ),
      ],
      ProfileTab.weibo => _weiboSlivers(),
      ProfileTab.featured => _feedSlivers(
        _featured,
        emptyTitle: '还没有精选内容',
        emptyMessage: '这个人还没有热门微博',
      ),
      ProfileTab.video => _feedSlivers(
        _video,
        emptyTitle: '还没有视频',
        emptyMessage: '发过的视频会出现在这里',
      ),
      ProfileTab.album => _albumSlivers(),
    };
  }

  Widget _statusCard(FeedController controller, Status status) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      key: ValueKey(status.id.isEmpty ? status.mid : status.id),
      child: StatusCard(
        status: status,
        onOpen: () => _openStatus(status),
        onOpenQuoted: _openStatus,
        onUser: _openUser,
        onImage: (pics, index) => openImages(context, pics: pics, index: index),
        onLongPressImage: (pics, index) =>
            showImageActions(context, pics: pics, index: index),
        onVideo: (video) => openVideo(context, video),
        onLink: (url) => handleLink(context, url),
        onLike: () => toggleStatusLike(context, controller, status),
        onRepost: () => repostStatus(context, controller, status),
        onComment: () => _openStatus(status),
        onLongPress: () => showStatusActions(context, status),
      ),
    );
  }

  List<Widget> _weiboSlivers() {
    final feed = _feed;
    if (feed == null ||
        (feed.items.isEmpty && (feed.loading || !feed.started))) {
      return [_loadingSliver()];
    }
    final items = _filter.apply(feed.items);
    if (items.isEmpty && feed.items.isNotEmpty) {
      _ensureFilteredContent(feed);
    }
    return [
      SliverToBoxAdapter(child: _filterRow()),
      if (feed.items.isEmpty)
        _emptySliver(
          title: feed.error ?? '还没有微博',
          message: feed.error != null
              ? '下拉或点刷新再试一次'
              : (_isSelf ? '发一条试试' : null),
          action: feed.error == null
              ? null
              : TextButton(onPressed: feed.refresh, child: const Text('重试')),
        )
      else if (items.isEmpty)
        _emptySliver(title: '没有「${_filter.label}」的微博', message: '换个筛选看看')
      else if (_grid)
        ProfileStatusGrid(
          statuses: items,
          onOpen: _openStatus,
          onLongPress: (status) => showStatusActions(context, status),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => _statusCard(feed, items[index]),
          ),
        ),
      _footerSliver(feed.loadingMore, feed.atEnd && !feed.loading),
    ];
  }

  List<Widget> _feedSlivers(
    FeedController? feed, {
    required String emptyTitle,
    String? emptyMessage,
  }) {
    if (feed == null ||
        (feed.items.isEmpty && (feed.loading || !feed.started))) {
      return [_loadingSliver()];
    }
    return [
      if (feed.items.isEmpty)
        _emptySliver(
          title: feed.error ?? emptyTitle,
          message: feed.error != null ? '下拉或点刷新再试一次' : emptyMessage,
          action: feed.error == null
              ? null
              : TextButton(onPressed: feed.refresh, child: const Text('重试')),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          sliver: SliverList.builder(
            itemCount: feed.items.length,
            itemBuilder: (context, index) =>
                _statusCard(feed, feed.items[index]),
          ),
        ),
      _footerSliver(feed.loadingMore, feed.atEnd && !feed.loading),
    ];
  }

  List<Widget> _albumSlivers() {
    final album = _album;
    if (album == null ||
        (album.photos.isEmpty && (album.loading || !album.started))) {
      return [_loadingSliver()];
    }
    if (album.photos.isEmpty) {
      return [
        _emptySliver(
          title: album.error ?? '还没有照片',
          message: album.error != null ? '下拉或点刷新再试一次' : '发过的照片会出现在这里',
          action: album.error == null
              ? null
              : TextButton(onPressed: album.refresh, child: const Text('重试')),
        ),
        _footerSliver(false, true),
      ];
    }
    return [
      ProfileAlbumGrid(
        photos: album.photos,
        onOpen: _openPhoto,
        onLongPress: _longPressPhoto,
      ),
      _footerSliver(album.loadingMore, album.atEnd),
    ];
  }

  Widget _filterRow() {
    final scheme = context.colorScheme;
    final color = scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          const Spacer(),
          Semantics(
            container: true,
            button: true,
            label: '筛选微博，当前${_filter.label}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickFilter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _filter.label,
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(fontSize: 13, color: color),
                    ),
                    const SizedBox(width: 1),
                    GlyphIcon(Glyphs.caretDown, size: 16, color: color),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            container: true,
            button: true,
            label: _grid ? '切换为列表' : '切换为网格',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleGrid,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: GlyphIcon(
                  _grid ? HoboGlyphs.list : HoboGlyphs.grid,
                  size: 20,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingSliver() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: HoboLoading(label: '正在加载…'),
      ),
    );
  }

  Widget _emptySliver({
    required String title,
    String? message,
    Widget? action,
  }) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HoboEmpty(title: title, message: message, action: action),
      ),
    );
  }

  Widget _footerSliver(bool loading, bool atEnd) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HoboListFooter(loading: loading, atEnd: atEnd),
      ),
    );
  }

  Future<void> _showMore(User user) async {
    final tags = context.read<FollowTags>();
    final current = tags.tagOf(user.id);
    final actions = <(String, VoidCallback)>[];
    final self = _isSelf;
    if (!self && user.id.isNotEmpty) {
      actions.add(('关注', () => _toggleFollow()));
      for (final tag in FollowTag.values) {
        actions.add((
          current == tag ? '取消${tag.menuLabel}' : '标记为${tag.menuLabel}',
          () => tags.set(user.id, current == tag ? null : tag),
        ));
      }
    }
    actions.addAll([('复制主页链接', _copyLink), ('刷新主页', _refresh)]);
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
          value: formatCount(user.friends),
          label: '关注',
          onTap: () => onOpenRelations(RelationKind.following),
        ),
        const SizedBox(width: 22),
        _Stat(
          value: formatCount(user.followers),
          label: '粉丝',
          onTap: () => onOpenRelations(RelationKind.followers),
        ),
        const SizedBox(width: 22),
        _Stat(value: formatCount(user.statuses), label: '微博'),
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
                  fontWeight: FontWeightScope.resolve(context, FontWeight.w700),
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

/// 跟着 [HoboPagerController] 连续位置做轻微横向位移的 sliver 包装：
/// 直接监听控制器刷新绘制层，切栏与横滑期间不触发下方列表重建。
class _SliverSlide extends SingleChildRenderObjectWidget {
  const _SliverSlide({
    required this.pager,
    required this.index,
    required this.enabled,
    required Widget sliver,
  }) : super(child: sliver);

  final HoboPagerController pager;
  final int index;
  final bool enabled;

  @override
  _RenderSliverSlide createRenderObject(BuildContext context) =>
      _RenderSliverSlide(pager, index, enabled);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverSlide renderObject,
  ) {
    renderObject
      ..pager = pager
      ..index = index
      ..enabled = enabled;
  }
}

class _RenderSliverSlide extends RenderProxySliver {
  _RenderSliverSlide(this._pager, this._index, this._enabled);

  static const double _maxShift = 36;

  HoboPagerController _pager;
  set pager(HoboPagerController value) {
    if (identical(_pager, value)) return;
    if (attached) _pager.removeListener(markNeedsPaint);
    _pager = value;
    if (attached) _pager.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  int _index;
  set index(int value) {
    if (_index == value) return;
    _index = value;
    markNeedsPaint();
  }

  bool _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsPaint();
  }

  double get _dx {
    if (!_enabled) return 0;
    final delta = (_index - _pager.page).clamp(-1.0, 1.0);
    if (delta.abs() < 1e-4) return 0;
    return delta * _maxShift;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _pager.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _pager.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final dx = _dx;
    context.paintChild(child!, dx == 0 ? offset : offset + Offset(dx, 0));
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    return super.hitTestChildren(
      result,
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition - _dx,
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final dx = _dx;
    if (dx != 0) transform.translateByDouble(dx, 0, 0, 1);
    super.applyPaintTransform(child, transform);
  }
}
