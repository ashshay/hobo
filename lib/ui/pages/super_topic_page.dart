import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/store.dart';
import '../../data/super_topic.dart';
import '../routes.dart';
import '../widgets/capsule.dart';
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';
import '../widgets/pager.dart';
import '../widgets/remote_image.dart';

/// 超话：资料头 + 栏目胶囊 + 微博流。栏目跟着胶囊一起横滑切换。
class SuperTopicScreen extends StatefulWidget {
  const SuperTopicScreen({super.key, required this.containerId});

  final String containerId;

  @override
  State<SuperTopicScreen> createState() => _SuperTopicScreenState();
}

class _SuperTopicScreenState extends State<SuperTopicScreen>
    with TickerProviderStateMixin {
  SuperTopicInfo? _info;
  List<SuperTopicTab> _tabs = const [];
  bool _loading = true;
  String? _error;

  /// 每个栏目一条流：切回来时已加载的内容和滚动位置都还在。
  final Map<String, FeedController> _feeds = {};
  final Set<String> _mounted = {};
  int _index = 0;

  /// 胶囊与各栏目页共用的一条弹簧。
  late final HoboPagerController _pager = HoboPagerController(vsync: this);

  SuperTopicTab? get _current =>
      _index >= 0 && _index < _tabs.length ? _tabs[_index] : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pager.dispose();
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<Repo>();
    if (!repo.hasSession()) {
      setState(() {
        _loading = false;
        _error = '超话需要登录后查看';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await repo.superTopic(widget.containerId);
      if (!mounted) return;
      context.read<Store>().addRecentSuperTopic(
        SuperTopicSummary(
          containerId: page.info.containerId,
          title: page.info.title,
          avatar: page.info.avatar,
          desc1: page.info.description,
          desc2: [
            if (page.info.readCount.isNotEmpty) '阅读 ${page.info.readCount}',
            if (page.info.postCount.isNotEmpty) '帖子 ${page.info.postCount}',
            if (page.info.fanCount.isNotEmpty) '粉丝 ${page.info.fanCount}',
          ].join(' · '),
        ),
      );
      var tabs = page.tabs;
      if (tabs.isEmpty) {
        tabs = defaultSuperTopicTabs(widget.containerId);
      }
      final feed = tabs.firstWhere(
        (tab) => tab.kind == SuperTopicTabKind.feed,
        orElse: () => tabs.first,
      );
      setState(() {
        _info = page.info;
        _tabs = tabs;
        _loading = false;
      });
      _pager
        ..setCount(tabs.length)
        ..jumpToPage(0);
      _index = 0;
      _select(tabs.indexOf(feed));
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  FeedController _feedFor(SuperTopicTab tab) {
    return _feeds.putIfAbsent(tab.containerId, () {
      final controller = FeedController(
        (cursor, {required force}) async {
          final page = await context.read<Repo>().superTopicTab(
            widget.containerId,
            tab.containerId,
            cursor: cursor,
          );
          return FeedPage(page.items, page.nextCursor);
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await controller.ensureLoaded();
      });
      return controller;
    });
  }

  void _select(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    setState(() {
      _index = index;
      _mounted.add(tab.containerId);
    });
  }

  /// 横滑经过哪一栏就先挂上哪一栏，松手落格时内容已经在了。
  void _mount(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    if (_mounted.contains(tab.containerId)) return;
    setState(() => _mounted.add(tab.containerId));
  }

  void _refreshCurrent() {
    final tab = _current;
    if (tab == null) {
      _load();
      return;
    }
    _feedFor(tab).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final tabs = _tabs;
    return HoboPage(
      title: info?.title.isNotEmpty == true ? info!.title : '超话',
      leading: const HoboBackButton(),
      actions: [
        IconButton(
          onPressed: _refreshCurrent,
          tooltip: '刷新',
          icon: const GlyphIcon(HoboGlyphs.refresh, size: 20),
        ),
      ],
      body: _loading && tabs.isEmpty
          ? const HoboLoading(label: '正在加载超话…')
          : _error != null && tabs.isEmpty
          ? HoboEmpty(
              title: _error!,
              message: '登录后可以查看超话内容',
              action: TextButton(
                onPressed: () => openLogin(context),
                child: const Text('去登录'),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    pageTopInset(context),
                    16,
                    8,
                  ),
                  child: tabs.isNotEmpty
                      ? HoboCapsule<int>(
                          segments: [
                            for (var i = 0; i < tabs.length; i++)
                              (i, tabs[i].label),
                          ],
                          value: _index,
                          onChanged: _select,
                          pageController: _pager,
                          height: 40,
                          scrollable: tabs.length > 4,
                        )
                      : const SizedBox(height: 40),
                ),
                Expanded(
                  child: HoboPager(
                    controller: _pager,
                    index: _index,
                    onIndexChanged: _select,
                    onNeedsPage: _mount,
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        _mounted.contains(tabs[i].containerId)
                            ? _pageFor(tabs[i])
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _pageFor(SuperTopicTab tab) {
    final info = _info;
    return StatusList(
      controller: _feedFor(tab),
      padding: EdgeInsets.fromLTRB(16, 4, 16, pageBottomInset(context)),
      refreshInset: 4,
      leading: info == null
          ? const []
          : [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Header(info: info),
              ),
            ],
      emptyTitle: '这个栏目还没有内容',
      emptyMessage: '下拉刷新试试',
      onOpenStatus: (status) => openStatus(context, status),
      onOpenUser: (user) => openUser(context, user),
      onOpenImage: (pics, index) =>
          openImages(context, pics: pics, index: index),
      onOpenVideo: (video) => openVideo(context, video),
      onLink: (url) => handleLink(context, url),
      onLongPressStatus: (status) => showStatusActions(context, status),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.info});

  final SuperTopicInfo info;

  @override
  Widget build(BuildContext context) {
    return HoboCard(
      child: Row(
        children: [
          Avatar(url: info.avatar, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${info.title}#',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.headline.of(context).copyWith(
                    fontSize: 17,
                    color: context.colorScheme.onSurface,
                  ),
                ),
                if (info.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontSize: 12,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  [
                    if (info.readCount.isNotEmpty) '阅读 ${info.readCount}',
                    if (info.postCount.isNotEmpty) '帖子 ${info.postCount}',
                    if (info.fanCount.isNotEmpty) '粉丝 ${info.fanCount}',
                  ].join(' · '),
                  style: AppTextStyle.caption1.of(context).copyWith(
                    fontSize: 11,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
