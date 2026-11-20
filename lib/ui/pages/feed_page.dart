import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../chrome.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';
import '../widgets/press_scale.dart';
import '../widgets/scroll_anchor.dart';

/// 首页：一条按栏目切换的微博流。
class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with WidgetsBindingObserver {
  final Map<String, FeedController> _controllers = {};
  final ScrollController _scroll = ScrollController();
  final Set<String> _restoredKeys = {};
  List<FollowGroup> _groups = const [];
  bool _groupsLoaded = false;
  ChromeController? _chrome;
  Settings? _settings;
  Repo? _repo;
  Timer? _saveTimer;
  double _headerHeight = 0;
  int _seenHomeRequests = 0;
  bool _restoring = false;
  String _displayedTabKey = '';
  double _swipeDx = 0;
  int _switchDirection = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGroups());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = context.read<Settings>();
    _repo = context.read<Repo>();
    final chrome = context.read<ChromeController>();
    if (!identical(chrome, _chrome)) {
      _chrome?.removeListener(_handleChromeCommand);
      _chrome = chrome..addListener(_handleChromeCommand);
      _seenHomeRequests = chrome.homeRequests;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveAnchor();
    _chrome?.removeListener(_handleChromeCommand);
    _scroll.dispose();
    super.dispose();
  }

  /// 退到后台就记一次位置：进程被系统杀掉时 dispose 不一定会跑。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveTimer?.cancel();
      _saveAnchor();
    }
  }

  /// 双击底栏「微博」：刷新并回到最新。
  void _handleChromeCommand() {
    final chrome = _chrome;
    if (chrome == null) return;
    if (chrome.homeRequests != _seenHomeRequests) {
      _seenHomeRequests = chrome.homeRequests;
      chrome.setHidden(false);
      unawaited(_refreshToLatest());
    }
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 当前真正显示的栏目：设置里的栏目被隐藏时会落到可见的第一个。
  String get _activeTabKey => _displayedTabKey.isNotEmpty
      ? _displayedTabKey
      : (_settings?.feedTabKey ?? '');

  /// 双击底栏「微博」：刷新当前栏目，再回到最新一条。
  Future<void> _refreshToLatest() async {
    final controller = _controllers[_activeTabKey];
    if (controller == null) return;
    await controller.refresh();
    if (!mounted) return;
    _scrollToTop();
  }

  /// 顶栏发布：发完刷新当前栏目并回到最新一条。
  Future<void> _compose() async {
    final published = await openCompose(context);
    if (published != true || !mounted) return;
    context.read<ChromeController>().setHidden(false);
    await _refreshToLatest();
  }

  void _handleSwipeStart(DragStartDetails details) => _swipeDx = 0;

  void _handleSwipeUpdate(DragUpdateDetails details) {
    _swipeDx += details.delta.dx;
  }

  /// 左右滑动切换栏目：甩得够快，或拖过一小段就翻一栏。
  void _handleSwipeEnd(DragEndDetails details) {
    final dx = _swipeDx;
    _swipeDx = 0;
    final velocity = details.primaryVelocity ?? 0;
    final bool goNext;
    if (velocity.abs() >= 300) {
      goNext = velocity < 0;
    } else if (dx.abs() >= 40) {
      goNext = dx < 0;
    } else {
      return;
    }
    _stepTab(goNext ? 1 : -1);
  }

  void _stepTab(int step) {
    final tabs = _tabsFor();
    if (tabs.length < 2) return;
    var index = tabs.indexWhere((tab) => tab.key == _displayedTabKey);
    if (index < 0) index = 0;
    final next = (index + step).clamp(0, tabs.length - 1);
    if (next == index) return;
    _select(tabs[next]);
  }

  /// 下滑藏起顶栏与底栏，上滑或到顶重新露出。
  /// 只有真的往下翻过一屏的一部分才藏，轻轻抖一下不会把顶栏弄没。
  void _handleScroll(double delta, bool atTop) {
    _scheduleSave();
    final chrome = _chrome;
    // 冷启动恢复位置也是一次 jumpTo，别把它当成用户下滑，否则顶栏和底栏
    // 一进 App 就藏起来。
    if (chrome == null || _restoring) return;
    if (atTop) {
      chrome.setHidden(false);
      return;
    }
    final pixels = _scroll.hasClients ? _scroll.position.pixels : 0;
    if (delta > 0.5 && pixels > 240) {
      chrome.setHidden(true);
    } else if (delta < -0.5) {
      chrome.setHidden(false);
    }
  }

  Future<void> _loadGroups() async {
    if (_groupsLoaded || !mounted) return;
    _groupsLoaded = true;
    final repo = context.read<Repo>();
    if (!repo.hasSession()) return;
    try {
      final groups = await repo.followGroups();
      if (mounted && groups.isNotEmpty) setState(() => _groups = groups);
    } on Object {
      // 分组拉不到不影响内置栏目。
    }
  }

  List<FeedTabSelection> _tabsFor() {
    final repo = context.read<Repo>();
    final guest = !repo.hasSession();
    final tabs = <FeedTabSelection>[
      const FeedTabSelection(FeedTabItem.follow),
      const FeedTabSelection(FeedTabItem.recommend),
      if (!guest) const FeedTabSelection(FeedTabItem.circle),
      if (!guest) const FeedTabSelection(FeedTabItem.special),
      if (!guest) const FeedTabSelection(FeedTabItem.secret),
      if (!guest) const FeedTabSelection(FeedTabItem.local),
      const FeedTabSelection(FeedTabItem.favorites),
      const FeedTabSelection(FeedTabItem.nearby),
      for (final group in _groups) FeedTabSelection(FeedTabItem.group, group),
    ];
    final visible = _settings?.visibleFeedTabs;
    if (visible != null) {
      tabs.removeWhere((tab) => !visible.contains(tab.key));
      if (tabs.isEmpty) {
        tabs.add(
          FeedTabSelection(
            guest ? FeedTabItem.recommend : FeedTabItem.follow,
          ),
        );
      }
    }
    return tabs;
  }

  FeedController _controllerFor(FeedTabSelection selection) {
    final repo = context.read<Repo>();
    final key = selection.key;
    return _controllers.putIfAbsent(key, () {
      switch (selection.item) {
        case FeedTabItem.follow:
          return FeedController(
            (cursor, {required force}) =>
                repo.friends(maxId: cursor, force: force),
          );
        case FeedTabItem.circle:
          return FeedController(
            (cursor, {required force}) =>
                repo.circle(maxId: cursor, force: force),
          );
        case FeedTabItem.recommend:
          return FeedController(
            (cursor, {required force}) =>
                repo.container('102803', sinceId: cursor, force: force),
          );
        case FeedTabItem.special:
          return FeedController(
            (cursor, {required force}) =>
                repo.special(maxId: cursor, force: force),
          );
        case FeedTabItem.secret:
          return FeedController(
            (cursor, {required force}) =>
                repo.secret(maxId: cursor, force: force),
          );
        case FeedTabItem.local:
          return FeedController(
            (cursor, {required force}) =>
                repo.localFollows(maxId: cursor, force: force),
          );
        case FeedTabItem.favorites:
          return FeedController(
            (cursor, {required force}) =>
                repo.favorites(cursor: cursor, force: force),
          );
        case FeedTabItem.nearby:
          return FeedController(
            (cursor, {required force}) => repo.nearby(
              context.read<Settings>().nearbyCustom
                  ? '${context.read<Settings>().nearbyPlaceLat}'
                  : '31.23',
              context.read<Settings>().nearbyCustom
                  ? '${context.read<Settings>().nearbyPlaceLon}'
                  : '121.47',
              maxId: cursor,
              force: force,
            ),
          );
        case FeedTabItem.group:
          final gid = selection.group?.gid ?? '';
          return FeedController(
            (cursor, {required force}) => repo.groupFeed(gid, maxId: cursor),
          );
        case FeedTabItem.original:
        case FeedTabItem.none:
          return FeedController(
            (cursor, {required force}) =>
                repo.container('102803', sinceId: cursor, force: force),
          );
      }
    });
  }

  void _ensureLoaded(FeedController controller, String key) {
    if (controller.started || controller.loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await controller.ensureLoaded();
      // 列表加载完才有下标可落位：FeedPage 不监听控制器，这里主动补一次。
      if (mounted) _maybeRestore(controller, key);
    });
  }

  /// 冷启动落回上次停下的那条微博：先按 id 找，找不到再退回下标。
  void _maybeRestore(FeedController controller, String key) {
    if (_restoredKeys.contains(key)) return;
    if (!controller.started || controller.items.isEmpty) return;
    _restoredKeys.add(key);
    final anchor = _settings?.feedAnchor(_owner(), key);
    if (anchor == null) return;
    var index = controller.items.indexWhere((status) => status.id == anchor.id);
    if (index < 0) index = anchor.index;
    if (index <= 0 && anchor.offset <= 0) return;
    index = index.clamp(0, controller.items.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _restoring = true;
      try {
        await restoreScrollTo(_scroll, index, anchor.offset.toDouble());
      } finally {
        _restoring = false;
      }
    });
  }

  String _owner() => _repo?.session?.uid ?? '';

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveAnchor);
  }

  void _saveAnchor() {
    final settings = _settings;
    if (settings == null || !_scroll.hasClients) return;
    final key = _activeTabKey;
    final controller = _controllers[key];
    if (controller == null || controller.items.isEmpty) return;
    final anchor = firstVisibleAnchor(_scroll, paddingTop: _headerHeight);
    if (anchor == null) return;
    final index = anchor.index;
    if (index < 0 || index >= controller.items.length) return;
    settings.applyFeedAnchor(
      _owner(),
      key,
      controller.items[index].id,
      index,
      anchor.offset.round(),
    );
  }

  void _select(FeedTabSelection selection) {
    if (selection.key == _displayedTabKey) return;
    final tabs = _tabsFor();
    final oldIndex = tabs.indexWhere((tab) => tab.key == _displayedTabKey);
    final newIndex = tabs.indexWhere((tab) => tab.key == selection.key);
    _switchDirection = newIndex < oldIndex ? -1 : 1;
    _saveTimer?.cancel();
    _saveAnchor();
    final settings = context.read<Settings>();
    settings.applyFeedTab(selection);
    settings.applyFeedTabKey(selection.key);
    context.read<ChromeController>().setHidden(false);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final repo = context.watch<Repo>();
    final tabs = _tabsFor();
    var selected = tabs.firstWhere(
      (tab) => tab.key == settings.feedTab.key,
      orElse: () => tabs.first,
    );
    if (!tabs.any((tab) => tab.key == selected.key)) {
      selected = tabs.first;
    }
    final guest = !repo.hasSession();
    // 纯本地模式没有关注关系，落在「关注」只会看到空态，直接给推荐流。
    if (guest &&
        (selected.item == FeedTabItem.follow ||
            selected.item == FeedTabItem.circle ||
            selected.item == FeedTabItem.special ||
            selected.item == FeedTabItem.secret ||
            selected.item == FeedTabItem.local ||
            selected.item == FeedTabItem.group)) {
      selected = tabs.firstWhere(
        (tab) => tab.item == FeedTabItem.recommend,
        orElse: () => tabs.first,
      );
    }
    _displayedTabKey = selected.key;
    final controller = _controllerFor(selected);
    _ensureLoaded(controller, selected.key);
    _maybeRestore(controller, selected.key);
    final needsLogin =
        guest &&
        (selected.item == FeedTabItem.follow ||
            selected.item == FeedTabItem.circle ||
            selected.item == FeedTabItem.special ||
            selected.item == FeedTabItem.secret ||
            selected.item == FeedTabItem.local ||
            selected.item == FeedTabItem.group);

    final chrome = context.watch<ChromeController>();
    final topPadding = MediaQuery.paddingOf(context).top;
    // 顶栏与栏目条合成一整块：隐藏时一起滑走，不留遮罩盖在信息流上。
    const toolbarHeight = 56.0;
    const tabsHeight = 46.0;
    final headerHeight = topPadding + toolbarHeight + tabsHeight;
    _headerHeight = headerHeight;
    return Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _handleSwipeStart,
              onHorizontalDragUpdate: _handleSwipeUpdate,
              onHorizontalDragEnd: _handleSwipeEnd,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('feed-switch-${selected.key}'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset((1 - value) * 18 * _switchDirection, 0),
                    child: child,
                  ),
                ),
                child: needsLogin
                  ? Padding(
                      padding: EdgeInsets.only(top: headerHeight),
                      child: HoboEmpty(
                        title: '登录后可以看关注流',
                        message: '纯本地模式只能浏览推荐与收藏',
                        action: TextButton(
                          onPressed: () => openLogin(context),
                          child: const Text('去登录'),
                        ),
                      ),
                    )
                  : StatusList(
                      key: ValueKey(selected.key),
                      controller: controller,
                      scrollController: _scroll,
                      onScroll: _handleScroll,
                      dockInset: true,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        headerHeight + 8,
                        16,
                        pageBottomInset(context),
                      ),
                      emptyTitle: guest ? '这里还没有内容' : '还没有微博',
                      emptyMessage: guest ? '登录后内容会更全' : '下拉刷新试试',
                      onRefresh: () async {
                        chrome.setHidden(false);
                        await controller.refresh();
                      },
                      onOpenStatus: (status) => openStatus(context, status),
                      onOpenUser: (user) => openUser(context, user),
                      onOpenImage: (pics, index) =>
                          openImages(context, pics: pics, index: index),
                      onOpenVideo: (video) => openVideo(context, video),
                      onLink: (url) => handleLink(context, url),
                      onLongPressStatus: (status) =>
                          showStatusActions(context, status),
                    ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedSlide(
              offset: chrome.hidden ? const Offset(0, -1) : Offset.zero,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: HoboBlurBar(
                child: Padding(
                  padding: EdgeInsets.only(top: topPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: toolbarHeight,
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            PressScale(
                              scale: 0.88,
                              child: IconButton.filled(
                                onPressed: _compose,
                                tooltip: '发微博',
                                icon: const GlyphIcon(
                                  HoboGlyphs.add,
                                  size: 22,
                                  fill: 1,
                                ),
                              ),
                            ),
                            const Spacer(),
                            PressScale(
                              scale: 0.88,
                              child: IconButton(
                                onPressed: () => openHistory(context),
                                tooltip: '浏览历史',
                                icon: const GlyphIcon(
                                  HoboGlyphs.clock,
                                  size: 22,
                                ),
                              ),
                            ),
                            PressScale(
                              scale: 0.88,
                              child: IconButton(
                                onPressed: () => openFavorites(context),
                                tooltip: '收藏',
                                icon: const GlyphIcon(
                                  HoboGlyphs.star,
                                  size: 22,
                                ),
                              ),
                            ),
                            PressScale(
                              scale: 0.88,
                              child: IconButton(
                                onPressed: () => openSearch(context),
                                tooltip: '搜索',
                                icon: const GlyphIcon(Glyphs.search, size: 22),
                              ),
                            ),
                            PressScale(
                              scale: 0.88,
                              child: IconButton(
                                onPressed: () => openSettings(context),
                                tooltip: '设置',
                                icon: const GlyphIcon(
                                  HoboGlyphs.wrench,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ),
                      ),
                      _FeedTabs(
                        tabs: tabs,
                        selected: selected,
                        onSelected: _select,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedTabs extends StatelessWidget {
  const _FeedTabs({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<FeedTabSelection> tabs;
  final FeedTabSelection selected;
  final ValueChanged<FeedTabSelection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return Chip(
            label: tab.label,
            selected: tab.key == selected.key,
            onPressed: () => onSelected(tab),
          );
        },
      ),
    );
  }
}
