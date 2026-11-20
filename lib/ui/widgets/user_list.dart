import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import '../theme.dart' show formatCount;
import 'common.dart';
import 'remote_image.dart';

/// 用户列表分页：关注 / 粉丝 / 搜索结果都是「页码 + 空页结束」。
class UserListController extends ChangeNotifier {
  UserListController(this._loader);

  final Future<List<User>> Function(int page, {required bool force}) _loader;

  final List<User> items = [];
  int _page = 0;
  bool loading = false;
  bool loadingMore = false;
  bool atEnd = false;
  String? error;
  bool _started = false;

  bool get started => _started;

  Future<void> ensureLoaded() async {
    if (_started) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (loading) return;
    _started = true;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final users = await _loader(1, force: true);
      items
        ..clear()
        ..addAll(users);
      _page = 1;
      atEnd = users.isEmpty;
    } on Object catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || atEnd) return;
    loadingMore = true;
    notifyListeners();
    try {
      final users = await _loader(_page + 1, force: false);
      if (users.isEmpty) {
        atEnd = true;
      } else {
        final seen = items.map((u) => u.id).toSet();
        items.addAll([
          for (final user in users)
            if (!seen.contains(user.id)) user,
        ]);
        _page++;
      }
    } on Object catch (e) {
      error = e.toString();
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }
}

class UserTile extends StatelessWidget {
  const UserTile({
    super.key,
    required this.user,
    this.onTap,
    this.trailing,
    this.subtitle,
  });

  final User user;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final description = subtitle ?? user.description;
    return HoboCard(
      onPressed: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Avatar(url: user.avatar, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline.of(context).copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (user.verified) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(),
                    ],
                    if (user.membership != Membership.none) ...[
                      const SizedBox(width: 4),
                      MemberBadge(svip: user.membership == Membership.svip),
                    ],
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${formatCount(user.followers)} 粉丝 · ${formatCount(user.statuses)} 微博',
                  style: AppTextStyle.caption1.of(context).copyWith(
                    fontSize: 11,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// 用户列表页的主体：滚动到底自动翻页。
class UserListView extends StatefulWidget {
  const UserListView({
    super.key,
    required this.controller,
    this.onOpen,
    this.leading = const [],
    this.emptyTitle = '这里还没有人',
    this.emptyMessage,
    this.trailingOf,
  });

  final UserListController controller;
  final ValueChanged<User>? onOpen;
  final List<Widget> leading;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget Function(User user)? trailingOf;

  @override
  State<UserListView> createState() => _UserListViewState();
}

class _UserListViewState extends State<UserListView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.loading && controller.items.isEmpty) {
      return const HoboLoading(label: '正在加载…');
    }
    if (controller.items.isEmpty) {
      return HoboEmpty(
        title: controller.error ?? widget.emptyTitle,
        message: controller.error == null ? widget.emptyMessage : '稍后再试',
      );
    }
    final leadingCount = widget.leading.length;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 500 &&
            !controller.loadingMore &&
            !controller.atEnd) {
          controller.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          pageBottomInset(context),
        ),
        itemCount: leadingCount + controller.items.length + 1,
        itemBuilder: (context, index) {
          if (index < leadingCount) return widget.leading[index];
          final itemIndex = index - leadingCount;
          if (itemIndex >= controller.items.length) {
            return HoboListFooter(
              loading: controller.loadingMore,
              atEnd: controller.atEnd,
            );
          }
          final user = controller.items[itemIndex];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: UserTile(
              user: user,
              onTap: widget.onOpen == null
                  ? null
                  : () => widget.onOpen!(user),
              trailing: widget.trailingOf?.call(user),
            ),
          );
        },
      ),
    );
  }
}
