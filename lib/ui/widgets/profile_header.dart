import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import 'remote_image.dart';

/// 顶栏上的一个图标按钮。颜色要跟着折叠进度从白变成正文色，所以这里只带
/// 图标和回调，具体的 IconButton 由 header 自己画。
typedef ProfileHeaderAction = ({Glyph glyph, String tooltip, VoidCallback onPressed});

/// 折叠头在某一帧的几何。
///
/// 抽成纯函数（不碰 widget）是为了能直接把 `progress` 从 0 扫到 1 做回归：
/// 头部的裁剪框一直在变矮，任何一项越界都会在真机上表现成「名字被切掉一截」。
@immutable
class ProfileHeaderLayout {
  const ProfileHeaderLayout({
    required this.extent,
    required this.coverBottom,
    required this.avatarTop,
    required this.avatarLeft,
    required this.avatarSize,
    required this.nameTop,
    required this.nameLeft,
    required this.nameSize,
    required this.nameHeight,
    required this.barFill,
    required this.buttonTint,
  });

  /// 这一帧头部实际高度（状态栏下沿到名字/顶栏底边）。
  final double extent;

  /// 封面底边：0 表示封面已经收没。
  final double coverBottom;
  final double avatarTop;
  final double avatarLeft;
  final double avatarSize;
  final double nameTop;
  final double nameLeft;
  final double nameSize;
  final double nameHeight;

  /// 顶栏底色的不透明度：0 时还看得见封面，1 时完全盖住下面的微博。
  final double barFill;

  /// 顶栏按钮的颜色（展开态压在封面上是白的，折叠后是正文色）。
  final Color buttonTint;

  static ProfileHeaderLayout at({
    required double progress,
    required double topInset,
    required double nameLine,
    required double textScale,
    required bool showBack,
    required Color surfaceTint,
    required Color onSurface,
  }) {
    final p = progress.clamp(0.0, 1.0);
    final maxExtent = ProfileHeaderDelegate.expandedExtent(topInset, nameLine);
    final minExtent = ProfileHeaderDelegate.collapsedExtent(topInset);
    final extent = maxExtent - (maxExtent - minExtent) * p;

    const cover = ProfileHeaderDelegate.coverHeight;
    const bar = ProfileHeaderDelegate.barHeight;
    const outer = ProfileHeaderDelegate.avatarOuter;
    const small = ProfileHeaderDelegate.avatarSmall;
    const overlap = ProfileHeaderDelegate.overlap;

    final ease = Curves.easeInOutCubic.transform(p);
    final barCenter = topInset + bar / 2;

    // 封面先收干净，最后三成只留给头像和名字落进顶栏。
    final coverT = (p / ProfileHeaderDelegate.coverRange).clamp(0.0, 1.0);
    final coverBottom = (topInset + cover) * (1 - coverT);

    // 头像一路贴着封面底边，缩到顶栏高度就停在栏里。
    final avatarSize = lerpDouble(outer, small, ease)!;
    final avatarLeft = lerpDouble(16, showBack ? 50 : 14, ease)!;
    final avatarTop = math.max(
      coverBottom - overlap * (1 - ease),
      barCenter - avatarSize / 2,
    );

    final nameSize = lerpDouble(
      ProfileHeaderDelegate.nameExpandedSize,
      ProfileHeaderDelegate.nameCollapsedSize,
      ease,
    )!;
    final nameHeight = textScale * nameSize * 1.3;
    // 名字先横着让开、再往上走：两段曲线错开，才不会从头像身上碾过去。
    final nameShift = Curves.easeOutCubic.transform(
      ((p - 0.40) / 0.45).clamp(0.0, 1.0),
    );
    final nameRise = Curves.easeInOutCubic.transform(
      ((p - 0.45) / 0.50).clamp(0.0, 1.0),
    );
    final nameTop = math.min(
      lerpDouble(avatarTop + avatarSize + 6, barCenter - nameHeight / 2, nameRise)!,
      // 裁剪框在变矮，名字不能掉出去：贴住底边往上让。
      extent - nameHeight - 4,
    );
    final nameLeft = lerpDouble(16, avatarLeft + avatarSize + 8, nameShift)!;

    return ProfileHeaderLayout(
      extent: extent,
      coverBottom: coverBottom,
      avatarTop: avatarTop,
      avatarLeft: avatarLeft,
      avatarSize: avatarSize,
      nameTop: nameTop,
      nameLeft: nameLeft,
      nameSize: nameSize,
      nameHeight: nameHeight,
      barFill: ((p - 0.55) / 0.45).clamp(0.0, 1.0),
      buttonTint: Color.lerp(const Color(0xFFFFFFFF), onSurface, ease)!,
    );
  }
}

/// 个人页的折叠头：封面随下拉收起，头像一边缩小一边挪进顶栏。
///
/// 只有两档高度：展开是「状态栏 + 封面 + 压边的头像 + 名字行」，折叠到底只剩
/// 「状态栏 + 一条 [barHeight] 的标题栏」。中间态全部由 [build] 按 `shrinkOffset`
/// 现算，不挂 AnimationController —— 手势到哪画面到哪，松手后不会多出一段追帧。
class ProfileHeaderDelegate extends SliverPersistentHeaderDelegate {
  ProfileHeaderDelegate({
    required this.topInset,
    required this.nameLine,
    required this.user,
    required this.showBack,
    required this.onBack,
    required this.actions,
  });

  /// 状态栏高度。封面画到状态栏底下，所以头部从屏幕顶算起。
  final double topInset;

  /// 展开态名字行的高度（含系统字号缩放），头部展开高度跟着它走。
  final double nameLine;
  final User user;
  final bool showBack;
  final VoidCallback onBack;
  final List<ProfileHeaderAction> actions;

  /// 封面在状态栏之下的高度。
  static const coverHeight = 160.0;

  /// 折叠到底时的标题栏高度。
  static const barHeight = 56.0;

  /// 头像外框（含白圈）的两种尺寸，以及展开态压住封面底边的距离。
  static const avatarOuter = 70.0;
  static const avatarSmall = 32.0;
  static const overlap = 28.0;

  static const _nameGap = 6.0;
  static const nameExpandedSize = 22.0;
  static const nameCollapsedSize = 17.0;

  /// 封面收完的那一段进度。
  static const coverRange = 0.62;

  static const actionWidth = 44.0;

  /// 展开态名字行的高度，跟着系统字号缩放走。
  static double nameLineOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(nameExpandedSize) * 1.3;

  /// 展开态从屏幕顶到名字行下沿的高度。
  static double expandedExtent(double topInset, double nameLine) =>
      topInset + coverHeight + avatarOuter - overlap + _nameGap + nameLine + 10;

  static double collapsedExtent(double topInset) => topInset + barHeight;

  @override
  double get minExtent => collapsedExtent(topInset);

  @override
  double get maxExtent => expandedExtent(topInset, nameLine);

  double get _range => maxExtent - minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = _range <= 0 ? 1.0 : (shrinkOffset / _range).clamp(0.0, 1.0);
    return _ProfileHeaderView(
      progress: t,
      topInset: topInset,
      nameLine: nameLine,
      user: user,
      showBack: showBack,
      onBack: onBack,
      actions: actions,
    );
  }

  @override
  bool shouldRebuild(covariant ProfileHeaderDelegate old) =>
      old.topInset != topInset ||
      old.nameLine != nameLine ||
      old.user != user ||
      old.showBack != showBack ||
      old.actions != actions;
}

class _ProfileHeaderView extends StatelessWidget {
  const _ProfileHeaderView({
    required this.progress,
    required this.topInset,
    required this.nameLine,
    required this.user,
    required this.showBack,
    required this.onBack,
    required this.actions,
  });

  final double progress;
  final double topInset;

  /// 展开态的名字行高。
  final double nameLine;
  final User user;
  final bool showBack;
  final VoidCallback onBack;
  final List<ProfileHeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final surface = SurfaceLevel.page.colorOf(scheme);
    const bar = ProfileHeaderDelegate.barHeight;
    const cover = ProfileHeaderDelegate.coverHeight;
    const outer = ProfileHeaderDelegate.avatarOuter;
    const action = ProfileHeaderDelegate.actionWidth;

    final m = ProfileHeaderLayout.at(
      progress: progress,
      topInset: topInset,
      nameLine: nameLine,
      textScale: MediaQuery.textScalerOf(context).scale(1),
      showBack: showBack,
      surfaceTint: surface,
      onSurface: scheme.onSurface,
    );
    final coverVisible =
        m.coverBottom <= 0 ? 0.0 : (m.coverBottom / (topInset + cover));
    final buttonTop = topInset + (bar - action) / 2;
    final actionsWidth = action * actions.length + 8;
    final barBottom = topInset + bar;

    return ClipRect(
      child: Stack(
        children: [
          if (m.coverBottom > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: m.coverBottom,
              // 图片固定按整张封面大小排版，只改裁剪窗口，滚动时不重新取样。
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: topInset + cover,
                  maxHeight: topInset + cover,
                  child: _Cover(
                    url: user.covers.isEmpty ? '' : user.covers.first,
                    height: topInset + cover,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: barBottom,
            child: ColoredBox(
              color: surface.withValues(alpha: m.barFill),
              child: const SizedBox.expand(),
            ),
          ),
          if (m.barFill > 0)
            Positioned(
              left: 0,
              right: 0,
              top: barBottom - 0.5,
              height: 0.5,
              child: ColoredBox(
                color: scheme.outlineVariant.withValues(alpha: 0.5 * m.barFill),
              ),
            ),
          // 展开态按钮压在封面上，垫一层渐变保证对比度。
          if (coverVisible > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: barBottom + 16,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.fromRGBO(0, 0, 0, 0.28 * coverVisible),
                        const Color(0x00000000),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: m.avatarLeft,
            top: m.avatarTop,
            width: m.avatarSize,
            height: m.avatarSize,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: outer,
                height: outer,
                child: _RingedAvatar(url: user.avatar),
              ),
            ),
          ),
          Positioned(
            left: m.nameLeft,
            right: actionsWidth,
            top: m.nameTop,
            height: m.nameHeight,
            child: IgnorePointer(
              child: Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.body.of(context).copyWith(
                  fontSize: m.nameSize,
                  height: 1.3,
                  fontWeight: FontWeight.lerp(
                    FontWeight.w700,
                    FontWeight.w600,
                    Curves.easeInOutCubic.transform(progress),
                  ),
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
          if (showBack)
            Positioned(
              left: 4,
              top: buttonTop,
              width: action,
              height: action,
              child: IconButton(
                onPressed: onBack,
                tooltip: '返回',
                icon: GlyphIcon(
                  Glyphs.chevronBack,
                  size: 24,
                  color: m.buttonTint,
                ),
              ),
            ),
          for (var i = 0; i < actions.length; i++)
            Positioned(
              right: 8 + action * (actions.length - 1 - i),
              top: buttonTop,
              width: action,
              height: action,
              child: IconButton(
                onPressed: actions[i].onPressed,
                tooltip: actions[i].tooltip,
                icon: GlyphIcon(
                  actions[i].glyph,
                  size: 22,
                  color: m.buttonTint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.height});

  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    // 封面是整屏宽，按屏宽下采样，别把原图全尺寸解码进显存。
    return RemoteImage(
      url: url,
      width: MediaQuery.sizeOf(context).width,
      height: height,
      fit: BoxFit.cover,
      placeholderColor: context.colorScheme.primaryContainer,
    );
  }
}

class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    const outer = ProfileHeaderDelegate.avatarOuter;
    const ring = 3.0;
    return Container(
      padding: const EdgeInsets.all(ring),
      decoration: ShapeDecoration(
        color: context.colorScheme.surface,
        shape: AppShape.full,
      ),
      child: Avatar(url: url, size: outer - ring * 2),
    );
  }
}
