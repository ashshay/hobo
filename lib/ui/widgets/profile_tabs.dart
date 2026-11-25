import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import '../theme.dart' show formatCount;

/// 个人主页的分类。顺序与微博 App 一致：关于 / 微博 / 相册 / 精选 / 视频。
enum ProfileTab {
  about('关于'),
  weibo('微博'),
  album('相册'),
  featured('精选'),
  video('视频');

  const ProfileTab(this.label);

  final String label;
}

/// 「微博」栏目里的内容筛选。只在已经拉到的列表上过滤，不改变接口游标。
enum ProfileFilter {
  all('全部'),
  original('原创'),
  image('图片'),
  video('视频');

  const ProfileFilter(this.label);

  final String label;

  /// 按筛选挑出这一页里的微博：原创排除转发，图片 / 视频看正文（或转发的原博）。
  List<Status> apply(Iterable<Status> statuses) => switch (this) {
    ProfileFilter.all => statuses.toList(),
    ProfileFilter.original => [
      for (final status in statuses)
        if (status.retweeted == null) status,
    ],
    ProfileFilter.image => [
      for (final status in statuses)
        if (_hasImage(status)) status,
    ],
    ProfileFilter.video => [
      for (final status in statuses)
        if (_hasVideo(status)) status,
    ],
  };

  static bool _hasImage(Status status) =>
      status.pics.isNotEmpty || (status.retweeted?.pics.isNotEmpty ?? false);

  static bool _hasVideo(Status status) =>
      status.video != null || status.retweeted?.video != null;
}

/// 个人页顶部那一排文字分类，选中项加粗并带一小段下划线。
class ProfileTabBar extends StatelessWidget {
  const ProfileTabBar({
    super.key,
    required this.selected,
    required this.weiboCount,
    required this.onSelect,
  });

  final ProfileTab selected;

  /// 「微博(10.6万)」里的数字；0 表示还没拿到，只显示「微博」。
  final int weiboCount;
  final ValueChanged<ProfileTab> onSelect;

  /// 和首页栏目条同一档高度，折叠头下面正好放得下。
  static const double height = 46;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final surface = SurfaceLevel.page.colorOf(scheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        height: height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in ProfileTab.values)
                _TabButton(
                  tab: tab,
                  selected: tab == selected,
                  count: tab == ProfileTab.weibo ? weiboCount : 0,
                  onTap: () => onSelect(tab),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final ProfileTab tab;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final label = count > 0 ? '${tab.label}(${formatCount(count)})' : tab.label;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 24, left: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(
                      fontSize: 15,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: selected ? 16 : 0,
                height: 2.5,
                decoration: ShapeDecoration(
                  color: scheme.primary,
                  shape: AppShape.full,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把分类条钉在折叠头下面。
class ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  ProfileTabBarDelegate({
    required this.selected,
    required this.weiboCount,
    required this.onSelect,
  });

  final ProfileTab selected;
  final int weiboCount;
  final ValueChanged<ProfileTab> onSelect;

  @override
  double get minExtent => ProfileTabBar.height;

  @override
  double get maxExtent => ProfileTabBar.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ProfileTabBar(
      selected: selected,
      weiboCount: weiboCount,
      onSelect: onSelect,
    );
  }

  @override
  bool shouldRebuild(covariant ProfileTabBarDelegate old) =>
      old.selected != selected || old.weiboCount != weiboCount;
}
