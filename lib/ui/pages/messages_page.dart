import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/store.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';

/// 私信会话列表。
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final List<MessageItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  String? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final repo = context.read<Repo>();
    if (!repo.hasSession()) {
      setState(() {
        _loading = false;
        _items.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await repo.messages(1, force: true);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _page = 1;
        _end = items.isEmpty;
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

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final store = context.read<Store>();
    return PrismScaffold(
      bar: HoboAppBar(
        title: Text(
          '消息',
          style: AppTextStyle.title1.of(context).copyWith(
            color: context.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: '刷新',
            icon: const GlyphIcon(HoboGlyphs.refresh, size: 22),
          ),
        ],
      ),
      body: !repo.hasSession()
          ? HoboEmpty(
              title: '登录后可以收发私信',
              action: TextButton(
                onPressed: () => openLogin(context),
                child: const Text('去登录'),
              ),
            )
          : _buildList(store),
    );
  }

  Widget _buildList(Store store) {
    if (_loading && _items.isEmpty) {
      return const HoboLoading(label: '正在加载消息…');
    }
    if (_items.isEmpty) {
      return HoboEmpty(
        title: _error ?? '还没有私信',
        message: _error == null ? '和关注的人聊两句吧' : '稍后再试',
        action: TextButton(onPressed: _refresh, child: const Text('重试')),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 400) {
          _loadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          pageBottomInset(context),
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
                              style: AppTextStyle.subheadline.of(context)
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
