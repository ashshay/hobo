import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import '../theme.dart' show formatCount;
import 'capsule.dart';
import 'pager.dart';

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

/// 个人页可滑动切换的胶囊分类条（关于 / 微博(N) / 相册 / 精选 / 视频）。
///
/// 按文字实际宽度排布：常规屏宽下五项完整居中呈现，支持直接按住胶囊滑块拖拽切换
/// 或左右横滑页面联动；窄屏 / 大字号超出宽度时自动启用横向滚动与两端渐隐。
class ProfileTabBar extends StatelessWidget {
  const ProfileTabBar({
    super.key,
    required this.selected,
    required this.weiboCount,
    required this.onSelect,
    this.pageController,
    this.pinned = false,
  });

  final ProfileTab selected;

  /// 「微博(10.6万)」里的数字；0 表示还没拿到，只显示「微博」。
  final int weiboCount;
  final ValueChanged<ProfileTab> onSelect;

  /// 与个人页横滑手势共用的弹簧控制器。
  final HoboPagerController? pageController;

  /// 吸顶且下方内容正在滚过时补一条底部分隔线，展开态保持无边框清爽观感。
  final bool pinned;

  /// 胶囊 40 + 上下各 5 留白，吸顶在折叠头下方舒展不拥挤。
  static const double height = 50;

  static String labelOf(ProfileTab tab, int weiboCount) =>
      tab == ProfileTab.weibo && weiboCount > 0
          ? '${tab.label}(${formatCount(weiboCount)})'
          : tab.label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final surface = SurfaceLevel.page.colorOf(scheme);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: pinned
            ? Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
          child: Center(
            child: HoboCapsule<ProfileTab>(
              segments: [
                for (final tab in ProfileTab.values)
                  (tab, labelOf(tab, weiboCount)),
              ],
              value: selected,
              onChanged: onSelect,
              pageController: pageController,
              height: 40,
              scrollable: true,
              expand: true,
              minSegmentWidth: 48,
              segmentHorizontalPadding: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// 把胶囊分类条钉在折叠头下面。
class ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  ProfileTabBarDelegate({
    required this.selected,
    required this.weiboCount,
    required this.onSelect,
    this.pageController,
  });

  final ProfileTab selected;
  final int weiboCount;
  final ValueChanged<ProfileTab> onSelect;
  final HoboPagerController? pageController;

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
      pageController: pageController,
      pinned: overlapsContent,
    );
  }

  @override
  bool shouldRebuild(covariant ProfileTabBarDelegate old) =>
      old.selected != selected ||
      old.weiboCount != weiboCount ||
      old.pageController != pageController ||
      old.onSelect != onSelect;
}
