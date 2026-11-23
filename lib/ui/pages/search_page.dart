import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../routes.dart';
import '../widgets/capsule.dart';
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';
import '../widgets/pager.dart';
import '../widgets/user_list.dart';

enum _SearchMode { feed, users, topics }

/// 发现页：搜索、热搜榜、搜索历史。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = '', this.showBack = true});

  final String initialQuery;
  final bool showBack;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  late final TextEditingController _input = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  /// 胶囊与三个结果页共用的一条弹簧。
  late final HoboPagerController _pager = HoboPagerController(
    vsync: this,
    count: _SearchMode.values.length,
  );

  /// 只挂载点过的分类：三个结果列表一起请求没必要。
  final Set<_SearchMode> _mounted = {_SearchMode.feed};

  String _query = '';
  _SearchMode _mode = _SearchMode.feed;
  List<String> _suggestions = const [];
  List<HotItem> _hot = const [];
  HotBoard _hotBoard = HotBoard.realtime;
  bool _loadingHot = true;
  String? _hotError;

  FeedController? _feed;
  UserListController? _users;
  List<TopicItem> _topics = const [];
  bool _loadingTopics = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit(widget.initialQuery));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHot());
    }
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _focus.dispose();
    _pager.dispose();
    _feed?.dispose();
    _users?.dispose();
    super.dispose();
  }

  /// 横滑经过哪一格就先挂上哪一格，松手落格时内容已经在了。
  void _mount(int index) {
    final mode = _SearchMode.values[index];
    if (_mounted.contains(mode)) return;
    setState(() => _mounted.add(mode));
  }

  void _onInputChanged() {
    if (_input.text.trim() == _query) return;
    _debounce?.cancel();
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _suggestions = const [];
        _query = '';
      });
      _loadHot();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      if (!mounted) return;
      try {
        final repo = context.read<Repo>();
        final suggestions = await repo.suggest(text);
        if (mounted) setState(() => _suggestions = suggestions);
      } on Object {
        // 联想失败不影响直接搜索。
      }
    });
  }

  Future<void> _loadHot() async {
    setState(() {
      _loadingHot = true;
      _hotError = null;
    });
    try {
      final repo = context.read<Repo>();
      final items = await repo.hot(board: _hotBoard);
      if (!mounted) return;
      setState(() {
        _hot = items;
        _loadingHot = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _hotError = e.toString();
        _loadingHot = false;
      });
    }
  }

  void _submit(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    _input
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _focus.unfocus();
    context.read<Settings>().pushSearchHistory(query);
    _feed?.dispose();
    _users?.dispose();
    setState(() {
      _query = query;
      _suggestions = const [];
      _mode = _SearchMode.feed;
      _mounted
        ..clear()
        ..add(_SearchMode.feed);
      _feed = FeedController((cursor, {required force}) async {
        final page = int.tryParse(cursor ?? '1') ?? 1;
        final result = await context.read<Repo>().search(
          query,
          page: page,
          force: force,
        );
        return FeedPage(
          result.items,
          result.items.isEmpty ? null : '${page + 1}',
        );
      });
      _users = null;
      _topics = const [];
    });
    _pager.jumpToPage(0);
    _feed?.ensureLoaded();
  }

  void _switchMode(_SearchMode mode) {
    setState(() {
      _mode = mode;
      _mounted.add(mode);
      if (mode == _SearchMode.users && _users == null) {
        final query = _query;
        _users = UserListController(
          (page, {required force}) =>
              context.read<Repo>().searchUsers(query, page: page, force: force),
        );
        _users!.ensureLoaded();
      }
      if (mode == _SearchMode.topics &&
          _topics.isEmpty &&
          !_loadingTopics) {
        _loadTopics();
      }
    });
  }

  Future<void> _loadTopics() async {
    final query = _query;
    if (query.isEmpty) return;
    setState(() => _loadingTopics = true);
    try {
      final topics = await context.read<Repo>().searchTopics(query);
      if (mounted) {
        setState(() {
          _topics = topics;
          _loadingTopics = false;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadingTopics = false);
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 不要题头：搜索框直接占顶栏这一行，内容紧贴着它往下排。
    return PrismScaffold(
      bar: HoboAppBar(
        leading: widget.showBack ? const HoboBackButton() : null,
        title: SearchField(
          controller: _input,
          focusNode: _focus,
          hintText: '搜索微博、用户、话题',
          onSubmitted: () => _submit(_input.text),
          onChanged: (_) {},
        ),
        titleSpacing: widget.showBack ? 0 : 16,
        toolbarHeight: 56,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) return _buildDiscover();
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 264),
              child: HoboCapsule<_SearchMode>(
                segments: const [
                  (_SearchMode.feed, '综合'),
                  (_SearchMode.users, '用户'),
                  (_SearchMode.topics, '话题'),
                ],
                value: _mode,
                onChanged: _switchMode,
                pageController: _pager,
              ),
            ),
          ),
        ),
        Expanded(
          child: HoboPager(
            controller: _pager,
            index: _mode.index,
            onIndexChanged: (index) => _switchMode(_SearchMode.values[index]),
            onNeedsPage: _mount,
            children: [
              for (final mode in _SearchMode.values)
                _mounted.contains(mode)
                    ? _resultsFor(mode)
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultsFor(_SearchMode mode) {
    switch (mode) {
      case _SearchMode.feed:
        final feed = _feed;
        if (feed == null) return const SizedBox.shrink();
        return StatusList(
          controller: feed,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          dockInset: false,
          emptyTitle: '没有找到「$_query」',
          onOpenStatus: (status) => openStatus(context, status),
          onOpenUser: (user) => openUser(context, user),
          onOpenImage: (pics, index) =>
              openImages(context, pics: pics, index: index),
          onOpenVideo: (video) => openVideo(context, video),
          onLink: (url) => handleLink(context, url),
          onLongPressStatus: (status) => showStatusActions(context, status),
        );
      case _SearchMode.users:
        final users = _users;
        if (users == null) return const SizedBox.shrink();
        return UserListView(
          controller: users,
          onOpen: (user) => openUser(context, user),
          emptyTitle: '没有找到相关用户',
        );
      case _SearchMode.topics:
        if (_loadingTopics) return const HoboLoading(label: '正在搜索话题…');
        if (_topics.isEmpty) {
          return HoboEmpty(
            title: '没有找到相关话题',
            message: '换个关键词试试',
            icon: HoboGlyphs.tag,
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            pageBottomInset(context),
          ),
          itemCount: _topics.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final topic = _topics[index];
            return HoboCard(
              onPressed: () => openTopic(context, topic.title),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${topic.title}#',
                    style: AppTextStyle.body.of(context).copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  if (topic.desc1.isNotEmpty || topic.desc2.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      [topic.desc1, topic.desc2]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: AppTextStyle.caption1.of(context).copyWith(
                        fontSize: 11,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
    }
  }

  Widget _buildDiscover() {
    final settings = context.watch<Settings>();
    final history = settings.searchHistory;
    final children = <Widget>[];
    if (history.isNotEmpty) {
      children.add(
        Row(
          children: [
            Text(
              '搜索历史',
              style: AppTextStyle.headline.of(context).copyWith(
                fontSize: 15,
                color: context.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            HoboBarAction(
              label: '清空',
              onPressed: () => settings.clearSearchHistory(),
            ),
          ],
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in history)
              Chip(
                label: item,
                onPressed: () => _submit(item),
                onDeleted: () => settings.removeSearchHistory(item),
              ),
          ],
        ),
      );
      children.add(const SizedBox(height: 20));
    }

    final suggestions = _suggestions;
    if (suggestions.isNotEmpty) {
      children.add(
        Text(
          '联想',
          style: AppTextStyle.headline.of(context).copyWith(
            fontSize: 15,
            color: context.colorScheme.onSurface,
          ),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        HoboCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final suggestion in suggestions.take(8))
                HoboRow(
                  title: suggestion,
                  leading: const GlyphIcon(Glyphs.search, size: 18),
                  onPressed: () => _submit(suggestion),
                ),
            ],
          ),
        ),
      );
      children.add(const SizedBox(height: 20));
    }

    final boards = HotBoard.values
        .where((board) => settings.hotBoards.contains(board))
        .toList();
    if (boards.isNotEmpty) {
      children.add(
        Row(
          children: [
            Text(
              '热搜',
              style: AppTextStyle.headline.of(context).copyWith(
                fontSize: 15,
                color: context.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _loadHot,
              tooltip: '刷新热搜',
              icon: const GlyphIcon(HoboGlyphs.refresh, size: 18),
            ),
          ],
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: boards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final board = boards[index];
              return Chip(
                label: board.label,
                selected: board == _hotBoard,
                onPressed: () {
                  setState(() => _hotBoard = board);
                  _loadHot();
                },
              );
            },
          ),
        ),
      );
      children.add(const SizedBox(height: 10));
      if (_loadingHot) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: ActivityIndicator(size: 22)),
          ),
        );
      } else if (_hotError != null) {
        children.add(
          HoboEmpty(
            title: '热搜加载失败',
            message: _hotError,
            action: TextButton(onPressed: _loadHot, child: const Text('重试')),
          ),
        );
      } else {
        children.add(
          HoboCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final item in _hot.take(30))
                  HoboRow(
                    title: '${item.rank}. ${item.title}',
                    subtitle: item.label.isEmpty ? null : item.label,
                    onPressed: () => _submit(item.title),
                  ),
              ],
            ),
          ),
        );
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        pageTopInset(context),
        16,
        pageBottomInset(context),
      ),
      children: children,
    );
  }
}

/// 话题页：一个关键词的多种排序。
class TopicPage extends StatefulWidget {
  const TopicPage({super.key, required this.query});

  final String query;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> with TickerProviderStateMixin {
  static const _channels = TopicChannel.values;

  TopicChannel _channel = TopicChannel.comprehensive;
  final Map<TopicChannel, FeedController> _feeds = {};
  final Set<TopicChannel> _mounted = {TopicChannel.comprehensive};

  /// 胶囊与六个频道页共用的一条弹簧。
  late final HoboPagerController _pager = HoboPagerController(
    vsync: this,
    count: _channels.length,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _feedFor(_channel));
  }

  @override
  void dispose() {
    _pager.dispose();
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    super.dispose();
  }

  void _mount(int index) {
    final channel = _channels[index];
    if (_mounted.contains(channel)) return;
    setState(() => _mounted.add(channel));
  }

  /// 每个频道一条流：切回来时已加载的内容和滚动位置都还在。
  FeedController _feedFor(TopicChannel channel) {
    return _feeds.putIfAbsent(channel, () {
      final controller = FeedController(
        (cursor, {required force}) => context.read<Repo>().topicChannelFeed(
          widget.query,
          channel,
          cursor: cursor,
          force: force,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await controller.ensureLoaded();
      });
      return controller;
    });
  }

  void _selectChannel(TopicChannel channel) {
    if (channel == _channel) return;
    setState(() {
      _channel = channel;
      _mounted.add(channel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.query.startsWith('#')
        ? widget.query
        : '#${widget.query}#';
    return HoboPage(
      title: label,
      leading: const HoboBackButton(),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 8),
            child: HoboCapsule<TopicChannel>(
              segments: [for (final channel in _channels) (channel, channel.label)],
              value: _channel,
              onChanged: _selectChannel,
              pageController: _pager,
            ),
          ),
          Expanded(
            child: HoboPager(
              controller: _pager,
              index: _channels.indexOf(_channel),
              onIndexChanged: (index) => _selectChannel(_channels[index]),
              onNeedsPage: _mount,
              children: [
                for (final channel in _channels)
                  _mounted.contains(channel)
                      ? _listFor(channel)
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listFor(TopicChannel channel) {
    return StatusList(
      controller: _feedFor(channel),
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
      dockInset: false,
      emptyTitle: '这个话题还没有内容',
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
