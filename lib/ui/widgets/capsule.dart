import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'pager.dart';
import 'spring.dart';

double _saturate(double value) => 1.0 - 2.0 / (math.exp(2.0 * value) + 1.0);

double _rubberBand(double overshoot, double limit) {
  if (overshoot <= 0 || limit <= 0) return 0;
  final pull = 1.0 - 1.0 / (overshoot * 0.55 / limit + 1.0);
  return limit * pull;
}

/// 滑块在任意瞬时位置 / 形变下的几何结果。
///
/// 抽成纯函数便于单测钉住两条硬约束：
/// - 中间项切换保留真实欠阻尼过冲；
/// - 两端项触壁时越界量转成压墙形变，滑块绝不越出圆角轨道被硬裁切。
@immutable
class CapsulePillGeometry {
  const CapsulePillGeometry({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(left, top, width, height);

  /// 极小的安全余量：两端吸附后允许 0.01px 的浮点误差，判定越界时忽略它。
  static const double _epsilon = 0.01;

  /// [bounds] 是每一段的累计右边界（长度 = 段数 + 1），等宽分段就是平均切分。
  static CapsulePillGeometry compute({
    required double position,
    required double stretch,
    required double pressBoost,
    required List<double> bounds,
    required double trackHeight,
  }) {
    final count = bounds.length - 1;
    if (count <= 0) {
      return const CapsulePillGeometry(left: 0, top: 0, width: 0, height: 0);
    }
    final trackWidth = bounds[count];
    if (trackWidth <= 0 || trackHeight <= 0) {
      return const CapsulePillGeometry(left: 0, top: 0, width: 0, height: 0);
    }
    final maxPos = count - 1.0;

    final double clampedPos;
    final double wallCompression;
    final bool atLeftWall = position < 0;
    final bool atRightWall = position > maxPos;
    if (atLeftWall) {
      clampedPos = 0;
      wallCompression = _rubberBand(-position, 0.16);
    } else if (atRightWall) {
      clampedPos = maxPos;
      wallCompression = _rubberBand(position - maxPos, 0.16);
    } else {
      clampedPos = position;
      wallCompression = 0;
    }

    final slot = clampedPos.floor().clamp(0, count - 1);
    final frac = (clampedPos - slot).clamp(0.0, 1.0);
    final segLeft = lerpDouble(bounds[slot], bounds[slot + 1], frac)!;
    final nextSlot = math.min(slot + 1, count - 1);
    final baseWidth = lerpDouble(
      bounds[slot + 1] - bounds[slot],
      bounds[nextSlot + 1] - bounds[nextSlot],
      frac,
    )!;

    // 水平拉长 + 垂直微压近似保持视觉面积；触壁压缩时反号变「压扁」。
    final netStretch = (stretch - wallCompression * 0.85).clamp(-0.18, 0.22);
    final swell = 1.0 + pressBoost * 0.025;
    final width = (baseWidth * (1.0 + netStretch) * swell)
        .clamp(baseWidth * 0.78, math.min(trackWidth, baseWidth * 1.24))
        .toDouble();
    final height = (trackHeight * (1.0 - netStretch * 0.42) * swell)
        .clamp(trackHeight * 0.84, trackHeight)
        .toDouble();

    final double left;
    if (atLeftWall) {
      left = 0;
    } else if (atRightWall) {
      left = trackWidth - width;
    } else {
      final centerX = segLeft + baseWidth / 2;
      left = (centerX - width / 2).clamp(0.0, trackWidth - width);
    }

    return CapsulePillGeometry(
      left: left.clamp(0.0, math.max(0.0, trackWidth - width)),
      top: (trackHeight - height) / 2,
      width: width,
      height: height,
    );
  }

  /// 滑块是否完全落在轨道里（单测用）。
  bool fitsIn(double trackWidth, double trackHeight) =>
      left >= -_epsilon &&
      left + width <= trackWidth + _epsilon &&
      top >= -_epsilon &&
      top + height <= trackHeight + _epsilon;
}

/// 非线性物理弹簧分段胶囊。
///
/// - **可打断弹簧 + 速度继承**：连点、拖拽、横滑翻页中途改主意都不刹车，
///   直接带着当前速度平滑转向；
/// - **速度驱动果冻形变与两端压墙回弹**：滑行时水平拉长 / 垂直微压，
///   撞到两端胶囊壁时转为柔和压缩，滑块全程不越界；
/// - **文字实时插值**：颜色、字重、微缩放跟着滑块位置逐帧过渡，滑块划过即亮；
/// - **跟手**：不滚动（段数少）时可以直接按住胶囊拖拽；绑定 [pageController]
///   后还会跟着页面横滑实时移动。
class HoboCapsule<T> extends StatefulWidget {
  const HoboCapsule({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.pageController,
    this.height = 40,
    this.scrollable = false,
    this.padding = const EdgeInsets.all(4),
  });

  /// 轨道内边距（滑块与文字都在这层里面）。
  static const double inset = 4;

  /// 点击切换 / 松手吸附的主位移弹簧。
  static final SpringDescription travelSpring =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 380),
        bounce: 0.24,
      );

  /// 手指按住胶囊拖拽时的跟手位移弹簧。
  static final SpringDescription followSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1050, ratio: 0.88);

  /// 速度驱动拉伸 / 挤压的次级弹簧：偏欠阻尼，形变带一点余震。
  static final SpringDescription jellySpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.48);

  /// 按住时的轻微膨胀反馈。
  static final SpringDescription pressSpring =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 220),
        bounce: 0.15,
      );

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// 与页面共用的弹簧控制器：绑上之后滑块与页面是同一个位置值。
  final HoboPagerController? pageController;

  final double height;

  /// 段数多、放不下时按内容宽度排布并横向滚动（顶栏栏目用它）。
  /// 滚动模式下拖动是滚轨道，不再拖滑块。
  final bool scrollable;

  final EdgeInsets padding;

  @override
  State<HoboCapsule<T>> createState() => _HoboCapsuleState<T>();
}

class _HoboCapsuleState<T> extends State<HoboCapsule<T>>
    with TickerProviderStateMixin {
  late final ContinuousSpring _pos;
  late final ContinuousSpring _jelly;
  late final ContinuousSpring _press;
  final ScrollController _scroll = ScrollController();

  bool _dragging = false;
  double _dragFrom = 0;
  double _dragDistance = 0;

  bool get _disableAnimations =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  HoboPagerController? get _pageController => widget.pageController;

  /// 当前连续页位置：绑定页面时读页面弹簧，否则读自己的位移弹簧。
  double get _page => _pageController?.page ?? _pos.value;

  int get _selectedIndex {
    final index = widget.segments.indexWhere((s) => s.$1 == widget.value);
    return index < 0 ? 0 : index;
  }

  double get _maxPage => math.max(1, widget.segments.length) - 1.0;

  @override
  void initState() {
    super.initState();
    _pos = ContinuousSpring(this, _selectedIndex.toDouble(), rest: 8e-4)
      ..addListener(_onOwnTick);
    _jelly = ContinuousSpring(this, 0, rest: 1e-3);
    _press = ContinuousSpring(this, 0, rest: 2e-3);
    _pageController?.addListener(_onPageTick);
    // 冷启动落在中间某一格时（顶部栏目记着上次的选择），先把那一段滚进来。
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant HoboCapsule<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pageController, widget.pageController)) {
      oldWidget.pageController?.removeListener(_onPageTick);
      widget.pageController?.addListener(_onPageTick);
      _pos.jumpTo(_page);
    }
    final nextIndex = _selectedIndex;
    final oldIndex = oldWidget.segments.indexWhere(
      (s) => s.$1 == oldWidget.value,
    );
    if (nextIndex != oldIndex && !_dragging) {
      _animateToIndex(nextIndex);
    } else if (widget.segments.length != oldWidget.segments.length &&
        !_dragging) {
      _pos.jumpTo(nextIndex.toDouble());
      _jelly.jumpTo(0);
    }
    _revealSelected();
  }

  @override
  void dispose() {
    _pageController?.removeListener(_onPageTick);
    _pos.removeListener(_onOwnTick);
    _pos.dispose();
    _jelly.dispose();
    _press.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 次级果冻弹簧只在目标本身明显变化时才重定向，别逐帧打断它。
  void _driveStretch(double velocity) {
    final speed = velocity.abs();
    final target = speed > 0.15
        ? 0.16 * _saturate(speed / 5.0)
        : 0.0;
    if ((_jelly.target - target).abs() > 0.012 ||
        (target == 0 && _jelly.target != 0)) {
      _jelly.springTo(target, HoboCapsule.jellySpring);
    }
  }

  void _onOwnTick() {
    if (_dragging) return;
    // 首帧 t == 0 瞬时速度为 0，别把起步的拉伸脉冲当成「已停稳」。
    if (_pos.isAnimating && !_pos.hasAdvanced) return;
    _driveStretch(_pos.velocity);
  }

  void _onPageTick() => _driveStretch(_pageController?.velocity ?? 0);

  void _animateToIndex(int index, {double? initialVelocity}) {
    final controller = _pageController;
    final target = index.toDouble();
    if (_disableAnimations) {
      if (controller != null) {
        controller.goToPage(index, animate: false);
      }
      _pos.jumpTo(target);
      _jelly.jumpTo(0);
      return;
    }
    final distance = (target - _page).abs();
    if (distance > 0.25) {
      // 起步给一记轻巧的拉伸脉冲，启动瞬间更有张力。
      final kick = (0.09 + 0.03 * math.min(distance, 2.0)).clamp(0.0, 0.16);
      _jelly.springTo(kick, HoboCapsule.jellySpring);
    }
    if (controller != null) {
      controller.goToPage(index, velocity: initialVelocity ?? 0);
      return;
    }
    _pos.springTo(
      target,
      HoboCapsule.travelSpring,
      initialVelocity: initialVelocity,
    );
  }

  void _select(int index) {
    if (index < 0 || index >= widget.segments.length) return;
    final option = widget.segments[index].$1;
    if (option == widget.value) {
      _animateToIndex(index);
      return;
    }
    HapticFeedback.selectionClick();
    _animateToIndex(index);
    widget.onChanged(option);
  }

  void _onDragStart(DragStartDetails details) {
    if (widget.scrollable || widget.segments.length <= 1) return;
    _dragging = true;
    _dragFrom = _page;
    _dragDistance = 0;
    if (!_disableAnimations) {
      _press.springTo(1, HoboCapsule.pressSpring);
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (!_dragging || trackWidth <= 0) return;
    _dragDistance += details.delta.dx;
    final slot = trackWidth / widget.segments.length;
    final raw = _dragFrom + _dragDistance / math.max(1.0, slot);
    final page = raw < 0
        ? -_rubberBand(-raw, 0.22)
        : raw > _maxPage
        ? _maxPage + _rubberBand(raw - _maxPage, 0.22)
        : raw;
    final velocity = details.delta.dx * 60 / math.max(1.0, slot);
    final controller = _pageController;
    if (_disableAnimations) {
      if (controller != null) {
        controller.dragTo(page, animate: false);
      }
      _pos.jumpTo(page.clamp(0.0, _maxPage));
      return;
    }
    if (controller != null) {
      controller.dragTo(page, velocity: velocity);
      return;
    }
    _pos.springTo(page, HoboCapsule.followSpring, initialVelocity: velocity);
    _jelly.springTo(
      0.12 * _saturate(velocity.abs() / 5.0),
      HoboCapsule.jellySpring,
    );
  }

  void _onDragEnd(DragEndDetails details, double trackWidth) {
    if (!_dragging) return;
    _dragging = false;
    if (!_disableAnimations) {
      _press.springTo(0, HoboCapsule.pressSpring);
    } else {
      _press.jumpTo(0);
    }
    final count = widget.segments.length;
    final slot = trackWidth > 0 ? trackWidth / count : 60.0;
    final velocity = details.velocity.pixelsPerSecond.dx / math.max(1.0, slot);
    final controller = _pageController;
    _jelly.springTo(0, HoboCapsule.jellySpring);
    if (controller != null) {
      final landed = controller.endDrag(
        velocity,
        animate: !_disableAnimations,
        limitToNeighbor: false,
      );
      final option = widget.segments[landed].$1;
      if (option != widget.value) widget.onChanged(option);
      return;
    }
    // 用跟手弹簧的「目标」落格：手指已经到了哪一格就落哪一格，
    // 再叠一点手速预测，快速短拖不会弹回原格。
    final projected = (_pos.target + velocity * 0.08).round().clamp(
      0,
      count - 1,
    );
    _animateToIndex(
      projected,
      initialVelocity: velocity.clamp(-14.0, 14.0),
    );
    final option = widget.segments[projected].$1;
    if (option != widget.value) widget.onChanged(option);
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _press.springTo(0, HoboCapsule.pressSpring);
    _jelly.springTo(0, HoboCapsule.jellySpring);
    _animateToIndex(_selectedIndex);
  }

  /// 滚动模式：让选中的那一段露在可视区中间。
  void _revealSelected() {
    if (!widget.scrollable) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final bounds = _scrollBounds;
      if (bounds == null || bounds.length < 2) return;
      final viewport = position.viewportDimension;
      final content = bounds.last;
      if (content <= viewport) return;
      final index = _selectedIndex.clamp(0, widget.segments.length - 1);
      final center = (bounds[index] + bounds[index + 1]) / 2;
      final target = (center - viewport / 2)
          .clamp(0.0, math.max(0.0, content - viewport))
          .toDouble();
      if ((position.pixels - target).abs() < 1) return;
      if (_disableAnimations) {
        _scroll.jumpTo(target);
        return;
      }
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 滚动模式的累计边界（内容坐标），供 [_revealSelected] 定位。
  List<double>? _scrollBounds;

  List<double> _bounds(double trackWidth) {
    final count = widget.segments.length;
    if (count <= 0) return const [0];
    final slot = trackWidth / count;
    return [for (var i = 0; i <= count; i++) i * slot];
  }

  /// 滚动模式按文字实际宽度排布（不挤成等分），返回每段宽度。
  List<double> _measureWidths(BuildContext context, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return [
      for (final (_, label) in widget.segments)
        () {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return math.max(64.0, width + 28);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final baseStyle = AppTextStyle.subheadline.of(context);
    final animation = Listenable.merge([
      _pos,
      _jelly,
      _press,
      ?_pageController,
    ]);
    final innerRadius = math.max(0.0, (widget.height - widget.padding.vertical) / 2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = widget.scrollable
            ? _measureWidths(context, baseStyle)
            : const <double>[];
        final contentWidth = widths.fold<double>(0, (a, b) => a + b);
        final fallback =
            math.max(120.0, MediaQuery.sizeOf(context).width - 48);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallback;
        final innerMax = math.max(0.0, maxWidth - widget.padding.horizontal);
        final trackWidth = widget.scrollable
            ? math.min(contentWidth, innerMax)
            : innerMax;
        final bounds = widget.scrollable && contentWidth > 0
            ? () {
                final list = <double>[0];
                for (final width in widths) {
                  list.add(list.last + width);
                }
                return list;
              }()
            : _bounds(trackWidth);
        _scrollBounds = widget.scrollable ? bounds : null;
        final trackHeight = math.max(
          0.0,
          widget.height - widget.padding.vertical,
        );

        return SizedBox(
          height: widget.height,
          width: widget.scrollable
              ? trackWidth + widget.padding.horizontal
              : null,
          child: Container(
            padding: widget.padding,
            decoration: ShapeDecoration(
              color: context.raisedSurfaceLevel.colorOf(scheme),
              shape: AppShape.full,
            ),
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(innerRadius),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) => _buildTrack(
                  context: context,
                  bounds: bounds,
                  trackWidth: trackWidth,
                  trackHeight: trackHeight,
                  widths: widths,
                  baseStyle: baseStyle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrack({
    required BuildContext context,
    required List<double> bounds,
    required double trackWidth,
    required double trackHeight,
    required List<double> widths,
    required TextStyle baseStyle,
  }) {
    final scheme = context.colorScheme;
    final count = widget.segments.length;
    final page = _page;
    final geometry = CapsulePillGeometry.compute(
      position: page,
      stretch: _jelly.value,
      pressBoost: _press.value,
      bounds: bounds,
      trackHeight: trackHeight,
    );
    final visualPos = page.clamp(0.0, _maxPage);

    final track = SizedBox(
      width: widget.scrollable ? bounds.last : trackWidth,
      height: trackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (count > 0)
            Positioned(
              left: geometry.left,
              top: geometry.top,
              width: geometry.width,
              height: geometry.height,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.primary,
                  shape: AppShape.full,
                ),
              ),
            ),
          Row(
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  width: widget.scrollable
                      ? widths[i]
                      : trackWidth / math.max(1, count),
                  child: _CapsuleSegment(
                    label: widget.segments[i].$2,
                    selected: widget.segments[i].$1 == widget.value,
                    focus: Curves.easeInOut.transform(
                      (1.0 - (visualPos - i).abs()).clamp(0.0, 1.0),
                    ),
                    style: baseStyle,
                    onTap: () => _select(i),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final gesture = GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: (details) =>
          _onDragUpdate(details, trackWidth),
      onHorizontalDragEnd: (details) => _onDragEnd(details, trackWidth),
      onHorizontalDragCancel: _onDragCancel,
      child: track,
    );

    if (!widget.scrollable) return gesture;
    return _EdgedScroll(
      controller: _scroll,
      width: trackWidth,
      height: trackHeight,
      fadeColor: context.raisedSurfaceLevel.colorOf(context.colorScheme),
      child: track,
    );
  }
}

/// 横向滚动的轨道 + 两端渐隐：段数放不下时，边缘那半截文字被底色吃掉，
/// 看上去是「还能接着滑」，而不是被圆角轨道硬裁了一刀。
class _EdgedScroll extends StatelessWidget {
  const _EdgedScroll({
    required this.controller,
    required this.width,
    required this.height,
    required this.fadeColor,
    required this.child,
  });

  final ScrollController controller;
  final double width;
  final double height;
  final Color fadeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: child,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  if (!controller.hasClients) return const SizedBox.shrink();
                  final position = controller.position;
                  return Stack(
                    children: [
                      if (position.pixels > 1)
                        _EdgeFade(color: fadeColor, fromLeft: true),
                      if (position.pixels < position.maxScrollExtent - 1)
                        _EdgeFade(color: fadeColor, fromLeft: false),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.color, required this.fromLeft});

  final Color color;
  final bool fromLeft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: fromLeft ? 0 : null,
      right: fromLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
            end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _CapsuleSegment extends StatelessWidget {
  const _CapsuleSegment({
    required this.label,
    required this.selected,
    required this.focus,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double focus;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = Color.lerp(scheme.onSurfaceVariant, scheme.onPrimary, focus)!;
    final weight = FontWeight.lerp(
      style.fontWeight ?? FontWeight.w400,
      FontWeight.w600,
      focus,
    );
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.full,
      look: selected ? PressLook.none : PressLook.ink,
      ringStandsOff: selected,
      selected: selected,
      childFills: true,
      onPressed: onTap,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Transform.scale(
            scale: lerpDouble(1, 1.02, focus)!,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style.copyWith(color: color, fontWeight: weight),
            ),
          ),
        ),
      ),
    );
  }
}
