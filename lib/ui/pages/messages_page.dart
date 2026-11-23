import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/store.dart';
import '../routes.dart';
import '../widgets/capsule.dart';
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';
import '../widgets/notice_card.dart';
import '../widgets/notice_list.dart';
import '../widgets/pager.dart';
import '../widgets/refresh.dart';
import '../widgets/remote_image.dart';

/// 消息：@我 / 评论 / 赞 / 私信，顶栏胶囊切页，左右滑动也能翻。
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

/// 顶栏刷新按钮的总线：响一下，当前这几页各自回源。
class _RefreshBus extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _MessagesPageState extends State<MessagesPage>
    with TickerProviderStateMixin {
  static const _segments = <(int, String)>[
    (0, '@我'),
    (1, '评论'),
    (2, '赞'),
    (3, '私信'),
  ];

  /// 四格胶囊在 393dp 竖屏上刚好排满顶栏剩余宽度。
  static const _capsuleWidth = 244.0;

  final _RefreshBus _bus = _RefreshBus();

  /// 胶囊滑块与四个页面共用同一条弹簧：点顶栏、滑页面都是同一套非线性运动。
  late final HoboPagerController _pager = HoboPagerController(
    vsync: this,
    count: _segments.length,
  );

  /// 只挂载点过的栏目：四个列表一起拉没必要。
  final Set<int> _mounted = {0};
  int _tab = 0;

  @override
  void dispose() {
    _pager.dispose();
    _bus.dispose();
    super.dispose();
  }

  /// 横滑经过哪一栏就先把它挂上，松手落格时内容已经在了。
  void _mount(int tab) {
    if (_mounted.contains(tab)) return;
    setState(() => _mounted.add(tab));
  }

  void _select(int tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _mounted.add(tab);
    });
  }

  Widget _pageFor(int index) => switch (index) {
    0 => _AtMeTab(reload: _bus),
    1 => _CommentsTab(reload: _bus),
    2 => _LikesTab(reload: _bus),
    _ => _DmTab(reload: _bus),
  };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    return PrismScaffold(
      bar: HoboAppBar(
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _capsuleWidth),
            child: HoboCapsule<int>(
              value: _tab,
              onChanged: _select,
              pageController: _pager,
              segments: _segments,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _bus.bump,
            tooltip: '刷新',
            icon: const GlyphIcon(HoboGlyphs.refresh, size: 22),
          ),
        ],
      ),
      body: !repo.hasSession()
          ? HoboEmpty(
              title: '登录后可以收发私信和通知',
              action: TextButton(
                onPressed: () => openLogin(context),
                child: const Text('去登录'),
              ),
            )
          : HoboPager(
              controller: _pager,
              index: _tab,
              onIndexChanged: _select,
              onNeedsPage: _mount,
              children: [
                for (var i = 0; i < _segments.length; i++)
                  _mounted.contains(i)
                      ? _pageFor(i)
                      : const SizedBox.shrink(),
              ],
            ),
    );
  }
}

/// @我：上面两格小胶囊分「微博 / 评论」，微博那页每条本身就是一条微博。
class _AtMeTab extends StatefulWidget {
  const _AtMeTab({required this.reload});

  final Listenable reload;

  @override
  State<_AtMeTab> createState() => _AtMeTabState();
}

class _AtMeTabState extends State<_AtMeTab> with TickerProviderStateMixin {
  final Set<int> _mounted = {0};
  int _sub = 0;
  FeedController? _statuses;

  late final HoboPagerController _pager = HoboPagerController(
    vsync: this,
    count: 2,
  );

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_onReload);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller().ensureLoaded();
    });
  }

  @override
  void dispose() {
    widget.reload.removeListener(_onReload);
    _pager.dispose();
    _statuses?.dispose();
    super.dispose();
  }

  /// 横滑经过哪一格就先挂上哪一格，松手落格时内容已经在了。
  void _mount(int index) {
    if (_mounted.contains(index)) return;
    setState(() => _mounted.add(index));
  }

  void _onReload() => _statuses?.refresh();

  FeedController _controller() => _statuses ??= FeedController.paged((
    page, {
    required force,
  }) async {
    final batch = await context.read<Repo>().atMe(page, force: force);
    return FeedPage(batch.items, null, hasMore: batch.hasMore);
  });

  void _selectSub(int value) {
    if (value == _sub) return;
    setState(() {
      _sub = value;
      _mounted.add(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 小胶囊固定在顶上，两个列表在它下面滚动。
    final listPadding = EdgeInsets.fromLTRB(
      16,
      8,
      16,
      pageBottomInset(context),
    );
    return Column(
      children: [
        SizedBox(height: pageTopInset(context) - 4),
        // 胶囊自己有 44 的高度，别再套 SizedBox 去压扁它。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: 140,
            child: HoboCapsule<int>(
              value: _sub,
              onChanged: _selectSub,
              pageController: _pager,
              segments: const [(0, '微博'), (1, '评论')],
            ),
          ),
        ),
        Expanded(
          child: HoboPager(
            controller: _pager,
            index: _sub,
            onIndexChanged: _selectSub,
            onNeedsPage: _mount,
            children: [
              _statusTab(listPadding),
              _mounted.contains(1)
                  ? _commentTab(listPadding)
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statusTab(EdgeInsets padding) {
    return StatusList(
      controller: _controller(),
      padding: padding,
      refreshInset: 8,
      emptyTitle: '还没有人 @ 你',
      emptyMessage: '别人在微博或评论里 @ 你时会出现在这里',
      onOpenStatus: (status) => openStatus(context, status),
      onOpenUser: (user) => openUser(context, user),
      onOpenImage: (pics, index) =>
          openImages(context, pics: pics, index: index),
      onOpenVideo: (video) => openVideo(context, video),
      onLink: (url) => handleLink(context, url),
      onLongPressStatus: (status) => showStatusActions(context, status),
    );
  }

  Widget _commentTab(EdgeInsets padding) {
    return NoticeList<Comment>(
      reload: widget.reload,
      loader: (page, {required force}) =>
          context.read<Repo>().atComments(page, force: force),
      keyOf: (comment) => comment.id,
      padding: padding,
      refreshInset: 8,
      emptyTitle: '还没有人 @ 你',
      emptyMessage: '别人在评论里 @ 你时会出现在这里',
      itemBuilder: (context, comment) => NoticeCard(
        user: comment.user,
        action: '在评论里 @ 了你',
        createdAt: comment.createdAt,
        html: comment.textHtml,
        status: comment.status,
        onOpen: _openStatusOf(context, comment.status),
        onUser: (user) => openUser(context, user),
        onLink: (url) => handleLink(context, url),
      ),
    );
  }
}

/// 收到的评论。
class _CommentsTab extends StatelessWidget {
  const _CommentsTab({required this.reload});

  final Listenable reload;

  @override
  Widget build(BuildContext context) {
    return NoticeList<Comment>(
      reload: reload,
      loader: (page, {required force}) =>
          context.read<Repo>().commentsToMe(page, force: force),
      keyOf: (comment) => comment.id,
      emptyTitle: '还没有收到评论',
      emptyMessage: '别人评论你的微博时会出现在这里',
      itemBuilder: (context, comment) => NoticeCard(
        user: comment.user,
        action: '评论了你的微博',
        createdAt: comment.createdAt,
        html: comment.textHtml,
        status: comment.status,
        onOpen: _openStatusOf(context, comment.status),
        onUser: (user) => openUser(context, user),
        onLink: (url) => handleLink(context, url),
      ),
    );
  }
}

/// 收到的赞。
class _LikesTab extends StatelessWidget {
  const _LikesTab({required this.reload});

  final Listenable reload;

  @override
  Widget build(BuildContext context) {
    return NoticeList<LikeNotice>(
      reload: reload,
      loader: (page, {required force}) =>
          context.read<Repo>().likesToMe(page, force: force),
      keyOf: (notice) => notice.id,
      emptyTitle: '还没有收到赞',
      emptyMessage: '别人赞你的微博时会出现在这里',
      itemBuilder: (context, notice) => NoticeCard(
        user: notice.user,
        action: '赞了你的微博',
        createdAt: notice.createdAt,
        status: notice.status,
        onOpen: _openStatusOf(context, notice.status),
        onUser: (user) => openUser(context, user),
      ),
    );
  }
}

/// 点卡片进被评论 / 被赞的那条微博；微博已删就没什么可进的。
VoidCallback? _openStatusOf(BuildContext context, Status? status) =>
    status == null ? null : () => openStatus(context, status);

/// 私信会话列表。
class _DmTab extends StatefulWidget {
  const _DmTab({required this.reload});

  final Listenable reload;

  @override
  State<_DmTab> createState() => _DmTabState();
}

class _DmTabState extends State<_DmTab> {
  final List<MessageItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  bool _loadMoreQueued = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant _DmTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reload != widget.reload) {
      oldWidget.reload.removeListener(_refresh);
      widget.reload.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.reload.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = _items.isEmpty);
    try {
      final items = await context.read<Repo>().messages(1, force: true);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _end = items.isEmpty;
        _loading = false;
      });
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _end || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final items = await context.read<Repo>().messages(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _page++;
        _end = items.isEmpty;
        _loadingMore = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 滚动通知有时是在布局里派发的，那期间 setState 会被判成「帧内调度重建」。
  void _scheduleLoadMore() {
    if (_loadMoreQueued) return;
    if (_loadingMore || _end || _loading) return;
    _loadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreQueued = false;
      if (mounted) _loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final padding = EdgeInsets.fromLTRB(
      16,
      pageTopInset(context),
      16,
      pageBottomInset(context),
    );
    return HoboRefresh(
      onRefresh: _refresh,
      topInset: padding.top,
      child: _loading && _items.isEmpty
          ? const HoboLoading(label: '正在加载消息…')
          : _items.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - padding.vertical)
                        .clamp(0.0, double.infinity),
                  ),
                  child: const HoboEmpty(
                    title: '还没有私信',
                    message: '和关注的人聊两句吧',
                  ),
                ),
              ),
            )
          : _buildList(store, padding),
    );
  }

  Widget _buildList(Store store, EdgeInsets padding) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 400) {
          _scheduleLoadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _items[index];
          final user = item.user;
          final key = user?.id ?? item.gid;
          final seen = store.chatSeen(key);
          final unread = item.unread > 0 && seen != item.id;
          return HoboCard(
            key: ValueKey(item.id),
            padding: const EdgeInsets.all(12),
            onPressed: () => openChat(
              context,
              uid: user?.id ?? '',
              gid: item.gid,
              name: user?.name ?? '私信',
              avatar: user?.avatar ?? '',
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Avatar(url: user?.avatar ?? '', size: 46),
                    if (unread)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: ShapeDecoration(
                            color: context.colorScheme.error,
                            shape: AppShape.full,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user?.name ?? '私信',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.subheadline
                                  .of(context)
                                  .copyWith(
                                    fontSize: 15,
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: context.colorScheme.onSurface,
                                  ),
                            ),
                          ),
                          Text(
                            formatWeiboTime(item.createdAt),
                            style: AppTextStyle.caption1.of(context).copyWith(
                              fontSize: 11,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.text.isEmpty ? '[图片]' : item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote.of(context).copyWith(
                          fontSize: 13,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
