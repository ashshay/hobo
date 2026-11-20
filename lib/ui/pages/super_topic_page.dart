import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/super_topic.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/image_actions.dart';
import '../widgets/remote_image.dart';
import '../widgets/status_card.dart';

/// 超话：资料头 + 栏目 + 微博流。

class SuperTopicScreen extends StatefulWidget {
  const SuperTopicScreen({super.key, required this.containerId});

  final String containerId;

  @override
  State<SuperTopicScreen> createState() => _SuperTopicScreenState();
}

class _SuperTopicScreenState extends State<SuperTopicScreen> {
  SuperTopicInfo? _info;
  List<SuperTopicTab> _tabs = const [];
  SuperTopicTab? _tab;
  final List<Status> _items = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _atEnd = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    final repo = context.read<Repo>();
    if (!repo.hasSession()) {
      setState(() {
        _loading = false;
        _error = '超话需要登录后查看';
      });
      return;
    }
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items.clear();
        _cursor = null;
        _atEnd = false;
      });
    } else {
      if (_loadingMore || _atEnd) return;
      setState(() => _loadingMore = true);
    }
    try {
      final tab = _tab ?? (await _defaultTab(repo));
      final page = await repo.superTopicTab(
        widget.containerId,
        tab.containerId,
        cursor: reset ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        _info = page.info;
        if (page.tabs.isNotEmpty) _tabs = page.tabs;
        _tab ??= tab;
        final seen = _items.map((s) => s.id).toSet();
        _items.addAll([
          for (final status in page.items)
            if (!seen.contains(status.id)) status,
        ]);
        _cursor = page.nextCursor;
        _atEnd = page.nextCursor == null || page.items.isEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<SuperTopicTab> _defaultTab(Repo repo) async {
    final page = await repo.superTopic(widget.containerId);
    if (page.tabs.isNotEmpty) {
      _tabs = page.tabs;
      _info = page.info;
      _items.addAll(page.items);
      _cursor = page.nextCursor;
      _atEnd = page.nextCursor == null;
      final feed = page.tabs.firstWhere(
        (tab) => tab.kind == SuperTopicTabKind.feed,
        orElse: () => page.tabs.first,
      );
      return feed;
    }
    return defaultSuperTopicTabs(widget.containerId).first;
  }

  void _selectTab(SuperTopicTab tab) {
    if (tab.containerId == _tab?.containerId) return;
    setState(() {
      _tab = tab;
      _items.clear();
      _cursor = null;
      _atEnd = false;
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return HoboPage(
      title: info?.title.isNotEmpty == true ? info!.title : '超话',
      leading: const HoboBackButton(),
      actions: [
        IconButton(
          onPressed: () => _load(reset: true),
          tooltip: '刷新',
          icon: const GlyphIcon(HoboGlyphs.refresh, size: 20),
        ),
      ],
      body: _loading && _items.isEmpty
          ? const HoboLoading(label: '正在加载超话…')
          : _error != null && _items.isEmpty
          ? HoboEmpty(
              title: _error!,
              message: '登录后可以查看超话内容',
              action: TextButton(
                onPressed: () => openLogin(context),
                child: const Text('去登录'),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.vertical &&
                    notification.metrics.extentAfter < 500 &&
                    !_loadingMore &&
                    !_atEnd) {
                  _load();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        pageTopInset(context),
                        16,
                        8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (info != null) _Header(info: info),
                          if (_tabs.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _tabs.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final tab = _tabs[index];
                                  return Chip(
                                    label: tab.label,
                                    selected:
                                        tab.containerId == _tab?.containerId,
                                    onPressed: () => _selectTab(tab),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      pageBottomInset(context),
                    ),
                    sliver: SliverList.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final status = _items[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: StatusCard(
                            status: status,
                            onOpen: () => openStatus(context, status),
                            onUser: (user) => openUser(context, user),
                            onImage: (pics, i) =>
                                openImages(context, pics: pics, index: i),
                            onLongPressImage: (pics, i) =>
                                showImageActions(context, pics: pics, index: i),
                            onVideo: (video) => openVideo(context, video),
                            onLongPress: () =>
                                showStatusActions(context, status),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
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
