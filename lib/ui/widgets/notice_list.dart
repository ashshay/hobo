import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import 'common.dart';
import 'refresh.dart';

/// 通知流：页号翻页 + 下拉刷新 + 空态 / 错误态，观感和 [StatusList] 一致。
///
/// 消息中心的「@我的微博」每条本身就是一条微博，直接用 `StatusList`；
/// 评论 / 赞这两类内容是定制的卡片，走这里。
class NoticeList<T> extends StatefulWidget {
  const NoticeList({
    super.key,
    required this.loader,
    required this.keyOf,
    required this.itemBuilder,
    required this.emptyTitle,
    this.emptyMessage,
    this.reload,
    this.padding,
    this.refreshInset,
  });

  /// 取第 [page] 页；`hasMore` 为 false 表示到底了。
  final Future<NoticeBatch<T>> Function(int page, {required bool force}) loader;

  /// 去重键：同一条通知可能落在相邻两页的边界上。
  final String Function(T item) keyOf;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyTitle;
  final String? emptyMessage;

  /// 顶栏刷新按钮的总线；响一下就把列表重新拉一遍。
  final Listenable? reload;
  final EdgeInsets? padding;

  /// 刷新药丸的落点；顶部有固定内容时由调用方显式给。
  final double? refreshInset;

  @override
  State<NoticeList<T>> createState() => _NoticeListState<T>();
}

class _NoticeListState<T> extends State<NoticeList<T>> {
  final List<T> _items = [];
  final Set<String> _seen = {};
  final ScrollController _scroll = ScrollController();
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _atEnd = false;
  bool _loadMoreQueued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.reload?.addListener(_onReload);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant NoticeList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reload != widget.reload) {
      oldWidget.reload?.removeListener(_onReload);
      widget.reload?.addListener(_onReload);
    }
  }

  @override
  void dispose() {
    widget.reload?.removeListener(_onReload);
    _scroll.dispose();
    super.dispose();
  }

  void _onReload() => _refresh();

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final batch = await widget.loader(1, force: true);
      if (!mounted) return;
      setState(() {
        _items.clear();
        _seen.clear();
        _absorb(batch.items);
        _page = 1;
        _atEnd = !batch.hasMore;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _atEnd || _loading || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final batch = await widget.loader(_page + 1, force: false);
      if (!mounted) return;
      setState(() {
        _absorb(batch.items);
        _page += 1;
        _atEnd = !batch.hasMore;
        _loadingMore = false;
      });
    } on Object {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 滚动通知有时是在布局里派发的（列表刚变长就起了一次轮），那期间
  /// setState 会被判成「帧内调度重建」，所以把续页推到帧末。
  void _scheduleLoadMore() {
    if (_loadMoreQueued) return;
    if (_loadingMore || _atEnd || _loading || _items.isEmpty) return;
    _loadMoreQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreQueued = false;
      if (mounted) _loadMore();
    });
  }

  void _absorb(List<T> incoming) {
    for (final item in incoming) {
      if (_seen.add(widget.keyOf(item))) _items.add(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding =
        widget.padding ??
        EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          pageBottomInset(context),
        );
    return HoboRefresh(
      onRefresh: _refresh,
      topInset: widget.refreshInset ?? padding.top,
      child: _items.isEmpty ? _emptyScrollable(padding) : _buildList(padding),
    );
  }

  Widget _buildList(EdgeInsets padding) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 400) {
          _scheduleLoadMore();
        }
        return false;
      },
      child: ListView.separated(
        controller: _scroll,
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        itemCount: _items.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return HoboListFooter(loading: _loadingMore, atEnd: _atEnd);
          }
          final item = _items[index];
          return KeyedSubtree(
            key: ValueKey(widget.keyOf(item)),
            child: widget.itemBuilder(context, item),
          );
        },
      ),
    );
  }

  /// 空态也要能下拉：套一层撑满一屏的滚动容器。
  Widget _emptyScrollable(EdgeInsets padding) {
    if (_loading) return const HoboLoading(label: '正在加载…');
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
          child: HoboEmpty(
            title: _error ?? widget.emptyTitle,
            message: _error == null ? widget.emptyMessage : '下拉或点刷新再试一次',
          ),
        ),
      ),
    );
  }
}
