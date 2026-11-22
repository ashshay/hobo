import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import 'common.dart';
import 'image_actions.dart';
import 'refresh.dart';
import 'status_card.dart';

/// 一条可以一直往下翻的微博流。分页游标就是接口回的那个 `since_id` / `max_id`；
/// 消息中心这类接口回的是页码，用 [FeedController.paged] 建。
class FeedController extends ChangeNotifier {
  FeedController(this._loader, {this.pageSize = 20}) : _paged = null;

  /// 页码翻页的源：没有游标，到底没有由 [FeedPage.hasMore] 说明。
  FeedController.paged(this._paged, {this.pageSize = 20}) : _loader = null;

  final Future<FeedPage> Function(String? cursor, {required bool force})?
  _loader;
  final Future<FeedPage> Function(int page, {required bool force})? _paged;
  final int pageSize;

  final List<Status> items = [];
  String? _cursor;
  int _page = 0;
  bool _started = false;
  bool _disposed = false;
  bool loading = false;
  bool loadingMore = false;
  bool refreshing = false;
  bool atEnd = false;
  String? error;

  bool get started => _started;
  bool get isEmpty => items.isEmpty;

  /// 页面在请求还没回来时被关掉是很常见的事，别让回来的那一帧再撞上去。
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_started) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (loading || refreshing) return;
    _started = true;
    refreshing = loading = true;
    error = null;
    _notify();
    try {
      final paged = _paged;
      final page = paged != null
          ? await paged(1, force: true)
          : await _loader!(null, force: true);
      items
        ..clear()
        ..addAll(_dedupe(page.items));
      _page = 1;
      _cursor = page.sinceId;
      atEnd = paged != null
          ? page.hasMore == false || page.items.isEmpty
          : page.sinceId == null || page.items.isEmpty;
    } on Object catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      refreshing = false;
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || atEnd) return;
    loadingMore = true;
    _notify();
    try {
      final paged = _paged;
      final page = paged != null
          ? await paged(_page + 1, force: false)
          : await _loader!(_cursor, force: false);
      final fresh = _dedupe(page.items);
      items.addAll(fresh);
      if (paged != null) {
        _page += 1;
        if (page.hasMore == false || page.items.isEmpty) atEnd = true;
      } else {
        final next = page.sinceId;
        if (next == null ||
            next.isEmpty ||
            page.items.isEmpty ||
            (next == _cursor && fresh.isEmpty)) {
          atEnd = true;
        }
        _cursor = next ?? _cursor;
      }
    } on Object catch (e) {
      error = e.toString();
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  List<Status> _dedupe(List<Status> page) {
    final seen = items.map((s) => s.id).toSet();
    return [
      for (final status in page)
        if (!seen.contains(status.id)) status,
    ];
  }

  void replace(Status status) {
    final index = items.indexWhere((s) => s.id == status.id);
    if (index < 0) return;
    items[index] = status;
    _notify();
  }

  void remove(String id) {
    items.removeWhere((s) => s.id == id || s.mid == id);
    _notify();
  }
}

/// 微博列表：滚动到底自动翻页，空态与错误态统一。
class StatusList extends StatefulWidget {
  const StatusList({
    super.key,
    required this.controller,
    this.scrollController,
    this.onScroll,
    this.leading = const [],
    this.headerSliver,
    this.header,
    this.padding,
    this.onOpenStatus,
    this.onOpenUser,
    this.onOpenImage,
    this.onOpenVideo,
    this.onLongPressStatus,
    this.onLink,
    this.emptyTitle = '这里还没有内容',
    this.emptyMessage,
    this.emptyAction,
    this.dockInset = true,
    this.onRefresh,
    this.refreshInset,
  });

  final FeedController controller;

  /// 外层注入的滚动控制器（保存 / 恢复位置、刷新后回顶）；不传则内部自建。
  final ScrollController? scrollController;

  /// 每次滚动回报 `(delta, atTop)`：delta > 0 是往下翻。
  final void Function(double delta, bool atTop)? onScroll;
  final List<Widget> leading;

  /// 钉在列表顶部的 sliver（个人页的折叠头）。给了它就用 CustomScrollView，
  /// 其余页面仍然是 ListView，行为不变。
  final Widget? headerSliver;
  final Widget? header;
  final EdgeInsets? padding;
  final ValueChanged<Status>? onOpenStatus;
  final ValueChanged<User>? onOpenUser;
  final void Function(List<Pic> pics, int index)? onOpenImage;
  final ValueChanged<VideoInfo>? onOpenVideo;
  final ValueChanged<Status>? onLongPressStatus;

  /// 正文里的链接（`@`、话题、网页、「查看图片」）。
  final ValueChanged<String>? onLink;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final bool dockInset;

  /// 下拉刷新；不传就刷这个列表自己的控制器。
  final Future<void> Function()? onRefresh;

  /// 刷新指示器的落点；不传按内容留白算。折叠头这种「顶部被固定占住」的
  /// 页面要显式给，否则药丸会压在封面上。
  final double? refreshInset;

  @override
  State<StatusList> createState() => _StatusListState();
}

class _StatusListState extends State<StatusList> {
  ScrollController? _ownedScroll;
  double _lastPixels = 0;
  bool _loadMoreQueued = false;

  ScrollController get _scroll => widget.scrollController ?? (_ownedScroll ??= ScrollController());

  /// 点赞：先改本地卡片，失败再撤回。列表页没有独立状态，乐观更新最顺手。
  Future<void> _toggleLike(Status status) async {
    final repo = context.read<Repo>();
    final settings = context.read<Settings>();
    // 刚被微博限流过就别再「先点亮再回弹」了，直接说清楚。
    if (repo.likeBlocked) {
      showHoboToast(context, '点赞太频繁，稍后再试', level: BannerLevel.warning);
      return;
    }
    if (settings.confirmLike && !status.liked) {
      final ok = await showHoboConfirm(
        context,
        title: '给 @${status.user?.name ?? '这条'} 点个赞？',
        confirmText: '点赞',
      );
      if (ok != true || !mounted) return;
    }
    final next = !status.liked;
    widget.controller.replace(
      status.copyWith(
        liked: next,
        attitudes: (status.attitudes + (next ? 1 : -1)).clamp(0, 1 << 30),
      ),
    );
    try {
      await repo.like(status.id, liked: status.liked);
    } on Object catch (e) {
      if (!mounted) return;
      widget.controller.replace(status);
      showHoboToast(
        context,
        e.toString(),
        level: repo.likeBlocked ? BannerLevel.warning : BannerLevel.error,
      );
    }
  }

  /// 转发：弹输入框，成功后把卡片上的转发数 +1。
  Future<void> _repost(Status status) async {
    final text = await showHoboInputDialog(
      context,
      title: '转发',
      hint: '说点什么（可留空）',
      multiline: true,
      confirmText: '转发',
    );
    if (text == null || !mounted) return;
    final repo = context.read<Repo>();
    await runGuarded(context, () async {
      await repo.repost(status.id, status.mid, text);
      if (!mounted) return;
      widget.controller.replace(
        status.copyWith(reposts: status.reposts + 1),
      );
      showHoboToast(context, '已转发');
    });
  }

  void _openComments(Status status) => widget.onOpenStatus?.call(status);

  void _longPressImage(List<Pic> pics, int index) =>
      showImageActions(context, pics: pics, index: index);


  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant StatusList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _ownedScroll?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final pixels = notification.metrics.pixels;
      final delta = pixels - _lastPixels;
      _lastPixels = pixels;
      if (delta.abs() > 0.5) {
        widget.onScroll?.call(delta, pixels <= 8);
      }
    } else if (notification is ScrollEndNotification) {
      widget.onScroll?.call(0, notification.metrics.pixels <= 8);
    }
    final controller = widget.controller;
    if (notification.metrics.extentAfter < 600 &&
        !controller.loading &&
        !controller.loadingMore &&
        !controller.atEnd) {
      _scheduleLoadMore(controller);
    }
    return false;
  }

  /// 滚动通知有时是在布局里派发的（列表刚变长就起了一次轮），那期间
  /// 控制器一 notify 就是「帧内调度重建」，所以把续页推到帧末。
  void _scheduleLoadMore(FeedController controller) {
    if (_loadMoreQueued) return;
    _loadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreQueued = false;
      if (mounted) controller.loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final hasHeader = widget.headerSliver != null;
    if (controller.loading && controller.items.isEmpty && !hasHeader) {
      return const HoboLoading(label: '正在加载…');
    }
    final padding =
        widget.padding ??
        EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          (widget.dockInset ? pageBottomInset(context) : 24),
        );
    return HoboRefresh(
      onRefresh: widget.onRefresh ?? controller.refresh,
      // 指示器别落在浮动顶栏底下：列表自己的留白不够时按顶栏高度兜底。
      topInset:
          widget.refreshInset ??
          (padding.top < pageTopInset(context)
              ? pageTopInset(context)
              : padding.top),
      child: hasHeader
          ? _buildWithHeader(controller, padding)
          : controller.items.isEmpty
          ? _EmptyScrollable(
              padding: padding,
              child: _empty(controller),
            )
          : _buildList(controller, padding),
    );
  }

  Widget _empty(FeedController controller) {
    return HoboEmpty(
      title: controller.error ?? widget.emptyTitle,
      message: controller.error == null
          ? widget.emptyMessage
          : '下拉或点刷新再试一次',
      action: widget.emptyAction,
    );
  }

  /// 折叠头是 pinned sliver，头部之外的内容全走 sliver，空态也要能下拉。
  Widget _buildWithHeader(FeedController controller, EdgeInsets padding) {
    final header = widget.headerSliver!;
    final sliver = controller.loading && controller.items.isEmpty
        ? const SliverFillRemaining(
            hasScrollBody: false,
            child: HoboLoading(label: '正在加载…'),
          )
        : controller.items.isEmpty
        ? SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(padding: padding, child: _empty(controller)),
          )
        : SliverPadding(
            padding: padding,
            sliver: SliverList.builder(
              itemCount: widget.leading.length + controller.items.length + 1,
              itemBuilder: (context, index) => _itemAt(controller, index),
            ),
          );
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [header, sliver],
      ),
    );
  }

  /// 下标 → 列表项：先是 [StatusList.leading]，再是微博，最后是底部状态。
  Widget _itemAt(FeedController controller, int index) {
    final leadingCount = widget.leading.length;
    if (index < leadingCount) return widget.leading[index];
    final itemIndex = index - leadingCount;
    if (itemIndex >= controller.items.length) {
      return HoboListFooter(
        loading: controller.loadingMore,
        atEnd: controller.atEnd,
      );
    }
    final status = controller.items[itemIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // 按 id 复用 State：刷新后按位置复用会把按压态、图片、动画串到别的微博上。
      key: ValueKey(status.id.isEmpty ? 'i$itemIndex' : status.id),
      child: StatusCard(
        status: status,
        onOpen: () => widget.onOpenStatus?.call(status),
        onOpenQuoted: widget.onOpenStatus,
        onUser: widget.onOpenUser,
        onImage: widget.onOpenImage,
        onLongPressImage: _longPressImage,
        onVideo: widget.onOpenVideo,
        onLink: widget.onLink,
        onLike: () => _toggleLike(status),
        onRepost: () => _repost(status),
        onComment: () => _openComments(status),
        onLongPress: widget.onLongPressStatus == null
            ? null
            : () => widget.onLongPressStatus!(status),
      ),
    );
  }

  Widget _buildList(FeedController controller, EdgeInsets padding) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scroll,
        padding: padding,
        // 内容不满一屏时也要能下拉，否则空列表刷不了。
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemCount: widget.leading.length + controller.items.length + 1,
        itemBuilder: (context, index) => _itemAt(controller, index),
      ),
    );
  }
}

/// 空态 / 错误态也要能下拉：套一层撑满一屏的滚动容器。
class _EmptyScrollable extends StatelessWidget {
  const _EmptyScrollable({required this.padding, required this.child});

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - padding.vertical).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
