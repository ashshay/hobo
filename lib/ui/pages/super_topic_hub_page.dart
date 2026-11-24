import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/links.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/store.dart';
import '../../data/super_topic.dart';
import '../../data/super_topic_id.dart';
import '../routes.dart';
import '../widgets/capsule.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/pager.dart';
import '../widgets/refresh.dart';
import '../widgets/remote_image.dart';

enum _HubTab { mine, plaza }

/// 超话入口页：顶栏支持按名称搜索或粘贴链接/ID 直达，下方提供「我的超话」与「超话广场」。
class SuperTopicHubPage extends StatefulWidget {
  const SuperTopicHubPage({super.key});

  @override
  State<SuperTopicHubPage> createState() => _SuperTopicHubPageState();
}

class _SuperTopicHubPageState extends State<SuperTopicHubPage>
    with TickerProviderStateMixin {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  late final HoboPagerController _pager = HoboPagerController(
    vsync: this,
    count: _HubTab.values.length,
  );

  _HubTab _tab = _HubTab.mine;
  final Set<_HubTab> _mounted = {_HubTab.mine};

  List<SuperTopicSummary> _recent = const [];

  // 我的超话
  List<SuperTopicSummary> _mine = const [];
  String? _mineCursor;
  bool _mineLoading = false;
  bool _mineStarted = false;
  bool _mineEnd = false;
  String? _mineError;
  bool _mineLoginRequired = false;

  // 超话广场
  List<SuperTopicSummary> _plaza = const [];
  String? _plazaCursor;
  bool _plazaLoading = false;
  bool _plazaStarted = false;
  bool _plazaEnd = false;
  String? _plazaError;

  // 搜索态
  String _query = '';
  List<TopicItem> _searchResults = const [];
  bool _searching = false;
  bool _searchCompleted = false;
  String? _searchError;
  bool _searchLoginRequired = false;
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadRecent();
      _loadMine(refresh: true);
    });
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focus.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _reloadRecent() {
    if (!mounted) return;
    setState(() => _recent = context.read<Store>().recentSuperTopics());
  }

  void _onInputChanged() {
    final text = _input.text.trim();
    if (text.isEmpty && _query.isNotEmpty) {
      _searchGen++;
      setState(() {
        _query = '';
        _searchResults = const [];
        _searching = false;
        _searchCompleted = false;
        _searchError = null;
        _searchLoginRequired = false;
      });
    }
  }

  void _selectTab(_HubTab tab) {
    setState(() {
      _tab = tab;
      _mounted.add(tab);
    });
    if (tab == _HubTab.mine && !_mineStarted) {
      unawaited(_loadMine(refresh: true));
    } else if (tab == _HubTab.plaza && !_plazaStarted) {
      unawaited(_loadPlaza(refresh: true));
    }
  }

  void _mountTab(int index) {
    if (index < 0 || index >= _HubTab.values.length) return;
    final tab = _HubTab.values[index];
    if (_mounted.contains(tab)) return;
    setState(() => _mounted.add(tab));
    if (tab == _HubTab.plaza && !_plazaStarted) {
      unawaited(_loadPlaza(refresh: true));
    }
  }

  Future<void> _loadMine({required bool refresh}) async {
    if (_mineLoading) return;
    if (!refresh && (_mineEnd || _mineCursor == null)) return;
    final repo = context.read<Repo>();
    if (!repo.hasSession()) {
      setState(() {
        _mineStarted = true;
        _mineLoading = false;
        _mineError = '登录后可查看你关注的超话';
        _mineLoginRequired = true;
      });
      return;
    }
    setState(() {
      _mineLoading = true;
      if (refresh) {
        _mineError = null;
        _mineLoginRequired = false;
      }
    });
    try {
      final page = await repo.followedSuperTopics(
        cursor: refresh ? null : _mineCursor,
        force: refresh,
      );
      if (!mounted) return;
      setState(() {
        _mineStarted = true;
        _mineLoading = false;
        _mineError = null;
        _mineLoginRequired = false;
        if (refresh) {
          _mine = List<SuperTopicSummary>.of(page.items);
        } else {
          final seen = _mine.map((e) => e.containerId).toSet();
          final merged = List<SuperTopicSummary>.of(_mine);
          for (final item in page.items) {
            if (seen.add(item.containerId)) merged.add(item);
          }
          _mine = merged;
        }
        _mineCursor = page.nextCursor;
        _mineEnd = page.nextCursor == null || page.items.isEmpty;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final needLogin = e.errno == '-100' || e.errno == '432';
      setState(() {
        _mineStarted = true;
        _mineLoading = false;
        _mineLoginRequired = needLogin;
        _mineError = needLogin ? '登录后可查看你关注的超话' : e.message;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _mineStarted = true;
        _mineLoading = false;
        _mineError = e.toString();
      });
    }
  }

  Future<void> _loadPlaza({required bool refresh}) async {
    if (_plazaLoading) return;
    if (!refresh && (_plazaEnd || _plazaCursor == null)) return;
    setState(() {
      _plazaLoading = true;
      if (refresh) _plazaError = null;
    });
    try {
      final page = await context.read<Repo>().hotSuperTopics(
        cursor: refresh ? null : _plazaCursor,
        force: refresh,
      );
      if (!mounted) return;
      setState(() {
        _plazaStarted = true;
        _plazaLoading = false;
        _plazaError = null;
        if (refresh) {
          _plaza = List<SuperTopicSummary>.of(page.items);
        } else {
          final seen = _plaza.map((e) => e.containerId).toSet();
          final merged = List<SuperTopicSummary>.of(_plaza);
          for (final item in page.items) {
            if (seen.add(item.containerId)) merged.add(item);
          }
          _plaza = merged;
        }
        _plazaCursor = page.nextCursor;
        _plazaEnd = page.nextCursor == null || page.items.isEmpty;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _plazaStarted = true;
        _plazaLoading = false;
        _plazaError = e.toString();
      });
    }
  }

  Future<void> _openAndRemember(SuperTopicSummary topic) async {
    context.read<Store>().addRecentSuperTopic(topic);
    _reloadRecent();
    await openSuperTopic(context, topic.containerId);
    if (mounted) _reloadRecent();
  }

  Future<void> _submit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _focus.unfocus();

    // 直接粘贴超话容器 ID 或超话链接时直达超话页。
    final directId = superTopicId(text);
    if (directId != null) {
      await openSuperTopic(context, directId);
      if (mounted) _reloadRecent();
      return;
    }
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('sinaweibo://') ||
        text.startsWith('intent://')) {
      final resolved = resolveWeiboLink(text) ?? text;
      final id = superTopicId(resolved);
      if (id != null) {
        await openSuperTopic(context, id);
        if (mounted) _reloadRecent();
      } else {
        openWeb(context, resolved, title: '超话');
      }
      return;
    }

    final clean = text.replaceAll(RegExp(r'^#+|#+$'), '').trim();
    if (clean.isEmpty) return;
    final gen = ++_searchGen;
    setState(() {
      _query = clean;
      _searching = true;
      _searchCompleted = false;
      _searchError = null;
      _searchLoginRequired = false;
      _searchResults = const [];
    });
    try {
      final found = await context.read<Repo>().searchSuperTopics(clean);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searchResults = found;
        _searching = false;
        _searchCompleted = true;
      });
      // 唯一精确同名匹配直接进入超话，减少一次点击。
      final normalizedQuery = _normalizeName(clean);
      final exact = found
          .where((item) => _normalizeName(item.title) == normalizedQuery)
          .toList();
      if (exact.length == 1 && exact.single.containerId != null) {
        final item = exact.single;
        unawaited(
          _openAndRemember(
            SuperTopicSummary(
              containerId: item.containerId!,
              title: item.title,
              avatar: item.avatar,
              desc1: item.desc1,
              desc2: item.desc2,
              scheme: item.scheme,
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (!mounted || gen != _searchGen) return;
      final needLogin = e.errno == '-100' || e.errno == '432';
      setState(() {
        _searching = false;
        _searchCompleted = true;
        _searchLoginRequired = needLogin;
        _searchError = needLogin ? '请先登录，再搜索超话' : e.message;
      });
    } on Object catch (e) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _searching = false;
        _searchCompleted = true;
        _searchError = e.toString();
      });
    }
  }

  void _openWebSearch() {
    final name = _query.isNotEmpty ? _query : _input.text.trim();
    if (name.isEmpty) return;
    final cid = Uri.encodeComponent('100103type=1&q=$name');
    openWeb(
      context,
      'https://m.weibo.cn/search?containerid=$cid',
      title: name,
    );
  }

  void _refreshCurrent() {
    if (_query.isNotEmpty) {
      unawaited(_submit(_query));
      return;
    }
    _reloadRecent();
    if (_tab == _HubTab.mine) {
      unawaited(_loadMine(refresh: true));
    } else {
      unawaited(_loadPlaza(refresh: true));
    }
  }

  static String _normalizeName(String raw) {
    var text = raw.trim().replaceAll(RegExp(r'^#+|#+$'), '').trim();
    if (text.endsWith('[超话]')) {
      text = text.substring(0, text.length - '[超话]'.length);
    } else if (text.endsWith('超话')) {
      text = text.substring(0, text.length - '超话'.length);
    }
    return text.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    return PrismScaffold(
      bar: HoboAppBar(
        leading: const HoboBackButton(),
        title: SearchField(
          controller: _input,
          focusNode: _focus,
          hintText: '搜索超话、粘贴超话链接或 ID',
          onSubmitted: () => _submit(_input.text),
          onChanged: (_) {},
        ),
        actions: [
          IconButton(
            onPressed: _refreshCurrent,
            tooltip: '刷新',
            icon: const GlyphIcon(HoboGlyphs.refresh, size: 20),
          ),
        ],
        titleSpacing: 0,
        toolbarHeight: 56,
      ),
      body: _query.isNotEmpty ? _buildSearchResults() : _buildHub(),
    );
  }

  Widget _buildSearchResults() {
    if (_searching) return const HoboLoading(label: '正在搜索超话…');
    if (_searchError != null) {
      return HoboEmpty(
        title: _searchError!,
        icon: HoboGlyphs.superTopic,
        action: Column(
          children: [
            if (_searchLoginRequired)
              TextButton(
                onPressed: () => openLogin(context),
                child: const Text('去登录'),
              )
            else
              TextButton(
                onPressed: () => _submit(_query),
                child: const Text('重试'),
              ),
            TextButton(
              onPressed: _openWebSearch,
              child: const Text('网页搜索'),
            ),
          ],
        ),
      );
    }
    if (_searchCompleted && _searchResults.isEmpty) {
      return HoboEmpty(
        title: '没有找到相关超话',
        message: '换个关键词试试，或直接粘贴超话链接 / ID',
        icon: HoboGlyphs.superTopic,
        action: TextButton(
          onPressed: _openWebSearch,
          child: const Text('用网页搜索'),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        16,
        pageTopInset(context),
        16,
        pageBottomInset(context),
      ),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final summary = SuperTopicSummary(
          containerId: item.containerId ?? '',
          title: item.title,
          avatar: item.avatar,
          desc1: item.desc1,
          desc2: item.desc2,
          scheme: item.scheme,
        );
        return _SuperTopicCard(
          topic: summary,
          onTap: () {
            if (summary.containerId.isNotEmpty) {
              unawaited(_openAndRemember(summary));
            } else {
              openTopic(context, item.title);
            }
          },
        );
      },
    );
  }

  Widget _buildHub() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: HoboCapsule<_HubTab>(
                segments: const [
                  (_HubTab.mine, '我的超话'),
                  (_HubTab.plaza, '超话广场'),
                ],
                value: _tab,
                onChanged: _selectTab,
                pageController: _pager,
              ),
            ),
          ),
        ),
        Expanded(
          child: HoboPager(
            controller: _pager,
            index: _tab.index,
            onIndexChanged: (index) => _selectTab(_HubTab.values[index]),
            onNeedsPage: _mountTab,
            children: [
              _mounted.contains(_HubTab.mine)
                  ? _buildMineTab()
                  : const SizedBox.shrink(),
              _mounted.contains(_HubTab.plaza)
                  ? _buildPlazaTab()
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMineTab() {
    return HoboRefresh(
      topInset: 4,
      onRefresh: () async {
        _reloadRecent();
        await _loadMine(refresh: true);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 360 &&
              !_mineLoading &&
              !_mineEnd &&
              _mineCursor != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_loadMine(refresh: false));
            });
          }
          return false;
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, pageBottomInset(context)),
          children: [
            if (_recent.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    '最近访问',
                    style: AppTextStyle.headline.of(context).copyWith(
                      fontSize: 14,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  HoboBarAction(
                    label: '清空',
                    onPressed: () {
                      context.read<Store>().clearRecentSuperTopics();
                      _reloadRecent();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in _recent.take(12))
                    Chip(
                      label: item.title,
                      onPressed: () => _openAndRemember(item),
                      onDeleted: () {
                        context.read<Store>().removeRecentSuperTopic(
                          item.containerId,
                        );
                        _reloadRecent();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_mineLoading && !_mineStarted)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: HoboLoading(label: '正在加载我的超话…'),
              )
            else if (_mineError != null && _mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: HoboEmpty(
                  title: _mineError!,
                  message: _mineLoginRequired
                      ? '也可以直接在顶部搜索或切换到超话广场'
                      : '下拉刷新重试',
                  icon: HoboGlyphs.superTopic,
                  action: _mineLoginRequired
                      ? TextButton(
                          onPressed: () => openLogin(context),
                          child: const Text('去登录'),
                        )
                      : TextButton(
                          onPressed: () => _loadMine(refresh: true),
                          child: const Text('重试'),
                        ),
                ),
              )
            else if (_mine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: HoboEmpty(
                  title: '还没有关注的超话',
                  message: '可以在顶部搜索超话，或去超话广场逛逛',
                  icon: HoboGlyphs.superTopic,
                  action: TextButton(
                    onPressed: () => _selectTab(_HubTab.plaza),
                    child: const Text('去超话广场'),
                  ),
                ),
              )
            else ...[
              if (_recent.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '我关注的超话',
                    style: AppTextStyle.headline.of(context).copyWith(
                      fontSize: 14,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                ),
              for (var i = 0; i < _mine.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _SuperTopicCard(
                  topic: _mine[i],
                  onTap: () => _openAndRemember(_mine[i]),
                ),
              ],
              HoboListFooter(loading: _mineLoading, atEnd: _mineEnd),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlazaTab() {
    if (_plazaLoading && !_plazaStarted) {
      return const HoboLoading(label: '正在加载超话广场…');
    }
    if (_plazaError != null && _plaza.isEmpty) {
      return HoboEmpty(
        title: '超话广场加载失败',
        message: _plazaError,
        icon: HoboGlyphs.superTopic,
        action: TextButton(
          onPressed: () => _loadPlaza(refresh: true),
          child: const Text('重试'),
        ),
      );
    }
    if (_plaza.isEmpty) {
      return HoboEmpty(
        title: '暂无推荐超话',
        message: '可以在顶部搜索框直接搜你想逛的超话',
        icon: HoboGlyphs.superTopic,
        action: TextButton(
          onPressed: () => _loadPlaza(refresh: true),
          child: const Text('刷新'),
        ),
      );
    }
    return HoboRefresh(
      topInset: 4,
      onRefresh: () => _loadPlaza(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 360 &&
              !_plazaLoading &&
              !_plazaEnd &&
              _plazaCursor != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_loadPlaza(refresh: false));
            });
          }
          return false;
        },
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(16, 4, 16, pageBottomInset(context)),
          itemCount: _plaza.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == _plaza.length) {
              return HoboListFooter(loading: _plazaLoading, atEnd: _plazaEnd);
            }
            final item = _plaza[index];
            return _SuperTopicCard(
              topic: item,
              onTap: () => _openAndRemember(item),
            );
          },
        ),
      ),
    );
  }
}

class _SuperTopicCard extends StatelessWidget {
  const _SuperTopicCard({required this.topic, required this.onTap});

  final SuperTopicSummary topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final subtitle = [
      topic.desc1,
      topic.desc2,
    ].where((s) => s.isNotEmpty).join(' · ');
    return HoboCard(
      onPressed: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (topic.avatar.isNotEmpty)
            RemoteImage(
              url: topic.avatar,
              width: 46,
              height: 46,
              radius: AppCorner.md,
              placeholderColor: scheme.surfaceContainerHighest,
            )
          else
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.65),
                shape: AppShape.all(AppCorner.md),
              ),
              child: GlyphIcon(
                HoboGlyphs.superTopic,
                size: 22,
                color: scheme.onPrimaryContainer,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(
                        fontSize: 15,
                        color: scheme.onSurface,
                      ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1.of(context).copyWith(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlyphIcon(
            Glyphs.chevronForward,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
