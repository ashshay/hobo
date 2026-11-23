import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'spring.dart';

/// 胶囊滑块与页面内容共用的一条弹簧。
///
/// [page] 是连续的页位置（0 = 第一页，0.5 = 正好翻到一半）。点顶栏胶囊、按住胶囊拖、
/// 手指横滑页面，三种操作写的都是这同一个值，所以滑块与内容永远同步，
/// 中途改主意也能带着当前速度平滑转向（非线性、可打断）。
class HoboPagerController extends ChangeNotifier {
  HoboPagerController({
    required TickerProvider vsync,
    int initialPage = 0,
    int count = 1,
  }) : _count = math.max(1, count),
       _dragOrigin = initialPage.toDouble(),
       _pos = ContinuousSpring(vsync, initialPage.toDouble(), rest: 8e-4) {
    _pos.addListener(notifyListeners);
  }

  /// 点击切换 / 松手吸附的主弹簧：利落，到点带约 4%–6% 的细腻过冲。
  static final SpringDescription travelSpring =
      SpringDescription.withDurationAndBounce(
        duration: const Duration(milliseconds: 380),
        bounce: 0.24,
      );

  /// 手指按住时的跟手弹簧：高刚度近临界阻尼，紧跟手指又过滤微小手抖。
  static final SpringDescription followSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 1050, ratio: 0.88);

  /// 拖到两端外侧的橡皮筋余量（单位：页）。
  static const double _edgeLimit = 0.22;

  /// 惯性投影系数：松手后按这个比例把手速折算成还要走多远（单位：秒）。
  static const double _projection = 0.18;

  /// 超过这个手速（页/秒）就至少翻一页，别让轻扫被位置投影吃掉。
  static const double _flickVelocity = 1.4;

  final ContinuousSpring _pos;
  int _count;
  bool _dragging = false;
  double _dragOrigin;

  /// 连续页位置：滑块与页面都读它。
  double get page => _pos.value;

  /// 松手后正在奔向的目标页位置。
  double get targetPage => _pos.target;

  /// 离当前页位置最近的一页，横滑途中高亮用它。
  int get nearest => _pos.value.round().clamp(0, _count - 1);

  int get count => _count;
  double get maxPage => math.max(1, _count) - 1.0;
  double get velocity => _pos.velocity;
  bool get isDragging => _dragging;
  bool get isAnimating => _pos.isAnimating;

  /// 段数变了（栏目设置改过、分组加载完）。只收紧范围，不动当前动画：
  /// 这个方法会在 build 期间被调用，通知监听者会撞上「帧内调度重建」。
  void setCount(int count) {
    _count = math.max(1, count);
    if (_pos.value > maxPage) _pos.jumpTo(maxPage);
  }

  void jumpToPage(int index) {
    _dragging = false;
    final target = index.clamp(0, _count - 1).toDouble();
    _dragOrigin = target;
    _pos.jumpTo(target);
  }

  void goToPage(int index, {double velocity = 0, bool animate = true}) {
    final target = index.clamp(0, _count - 1).toDouble();
    _dragging = false;
    _dragOrigin = target;
    if (!animate) {
      _pos.jumpTo(target);
      return;
    }
    _pos.springTo(target, travelSpring, initialVelocity: velocity);
  }

  /// 手指按住：从这里开始算「本次手势的起点页」，松手时用它兜住最多一页的位移。
  void beginDrag() {
    _dragging = true;
    _dragOrigin = _pos.target;
  }

  /// 跟手：位置直接写进来（单位是页），两端外侧走橡皮筋阻尼。
  void dragTo(double page, {double velocity = 0, bool animate = true}) {
    _dragging = true;
    final target = _rubberBand(page);
    if (!animate) {
      _pos.jumpTo(target.clamp(0.0, maxPage));
      return;
    }
    _pos.springTo(target, followSpring, initialVelocity: velocity);
  }

  /// 松手落格：按手速做一点惯性投影。返回落到的页。
  ///
  /// [limitToNeighbor] 给横滑页面用：一次手势最多翻一页，别因为残余速度一路滑过去。
  /// 直接拖胶囊时关掉它 —— 滑块是跟着手指走的，手指压在第几格就落在第几格。
  int endDrag(
    double velocity, {
    bool animate = true,
    bool limitToNeighbor = true,
  }) {
    _dragging = false;
    final origin = _dragOrigin.round();
    var target = (_pos.target + velocity * _projection).round();
    if (velocity.abs() > _flickVelocity) {
      target = velocity > 0
          ? math.max(target, origin + 1)
          : math.min(target, origin - 1);
    }
    if (limitToNeighbor) {
      target = target.clamp(origin - 1, origin + 1);
    }
    target = target.clamp(0, _count - 1);
    if (!animate) {
      _pos.jumpTo(target.toDouble());
      return target;
    }
    _pos.springTo(
      target.toDouble(),
      travelSpring,
      initialVelocity: velocity.clamp(-16.0, 16.0),
    );
    return target;
  }

  double _rubberBand(double value) {
    if (value < 0) return -_elastic(-value);
    if (value > maxPage) return maxPage + _elastic(value - maxPage);
    return value;
  }

  double _elastic(double overshoot) {
    if (overshoot <= 0) return 0;
    final pull = 1.0 - 1.0 / (overshoot * 0.55 / _edgeLimit + 1.0);
    return _edgeLimit * pull;
  }

  @override
  void dispose() {
    _pos.removeListener(notifyListeners);
    _pos.dispose();
    super.dispose();
  }
}

/// 跟手翻页容器：所有页都在树里（保留滚动位置与已加载数据），
/// 只有当前页与相邻页参与绘制；横滑时按 [HoboPagerController.page] 实时错位。
class HoboPager extends StatefulWidget {
  const HoboPager({
    super.key,
    required this.controller,
    required this.index,
    required this.children,
    this.onIndexChanged,
    this.onNeedsPage,
    this.enabled = true,
    this.clipBehavior = Clip.hardEdge,
  });

  final HoboPagerController controller;

  /// 当前页（父层的状态）。外部改动它时容器自己也弹簧过去。
  final int index;

  /// 每一页，顺序与胶囊的段一一对应；没挂载的页给个占位即可。
  final List<Widget> children;

  /// 横滑落格后回调。松手那一刻就会回调，让目标页在回弹途中就开始加载。
  final ValueChanged<int>? onIndexChanged;

  /// 横滑经过某一页时回调（帧末派发，可以安全 setState）：用来先把目标页挂上，
  /// 免得手指底下是一块空白。
  final ValueChanged<int>? onNeedsPage;
  final bool enabled;
  final Clip clipBehavior;

  @override
  State<HoboPager> createState() => _HoboPagerState();
}

class _HoboPagerState extends State<HoboPager> {
  double _dragDistance = 0;
  double _dragFrom = 0;
  double _width = 1;
  int _reported = -1;

  bool get _disableAnimations =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller
      ..setCount(widget.children.length);
    if (controller.page != widget.index) controller.jumpToPage(widget.index);
    _reported = widget.index;
    controller.addListener(_onTick);
  }

  @override
  void didUpdateWidget(covariant HoboPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = widget.controller;
    if (!identical(oldWidget.controller, controller)) {
      oldWidget.controller.removeListener(_onTick);
      controller
        ..setCount(widget.children.length)
        ..jumpToPage(widget.index);
      _reported = widget.index;
      controller.addListener(_onTick);
      return;
    }
    if (oldWidget.children.length != widget.children.length) {
      controller.setCount(widget.children.length);
    }
    if (oldWidget.index != widget.index && !controller.isDragging) {
      _reported = widget.index;
      controller.goToPage(widget.index, animate: !_disableAnimations);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  /// 手指滑到哪一页就报哪一页。构建期间不能 setState，推到帧末。
  ///
  /// 只在跟手滑行时上报：点胶囊那种跨好几格的弹簧会依次路过中间各页，
  /// 一路挂上去等于把没去的栏目全部请求一遍。
  void _onTick() {
    if (!widget.controller.isDragging) return;
    final near = widget.controller.nearest;
    if (near == _reported) return;
    _reported = near;
    final callback = widget.onNeedsPage;
    if (callback == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback(near);
      });
      return;
    }
    callback(near);
  }

  void _onDragStart(DragStartDetails details) {
    _dragDistance = 0;
    _dragFrom = widget.controller.page;
    widget.controller.beginDrag();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_width <= 0) return;
    _dragDistance += details.delta.dx;
    widget.controller.dragTo(
      _dragFrom - _dragDistance / _width,
      velocity: -details.delta.dx * 60 / _width,
      animate: !_disableAnimations,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    if (_width <= 0) return;
    final velocity = -(details.primaryVelocity ?? 0) / _width;
    final landed = widget.controller.endDrag(
      velocity,
      animate: !_disableAnimations,
    );
    if (landed != widget.index) widget.onIndexChanged?.call(landed);
  }

  void _onDragCancel() {
    widget.controller.endDrag(0, animate: !_disableAnimations);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        final content = ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _buildPages(controller.page),
        );
        if (!widget.enabled || widget.children.length <= 1) return content;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: content,
        );
      },
    );
  }

  Widget _buildPages(double page) {
    final count = widget.children.length;
    final activeIndex = widget.controller.nearest;
    return ClipRect(
      clipBehavior: widget.clipBehavior,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < count; i++)
            _slot(i, page, activeIndex == i, (i - page).abs() < 1.0),
        ],
      ),
    );
  }

  /// 一页的壳。离开视口一页以上的页照旧留在树里（[Offstage] 保留 State），
  /// 只是不画、不响应点击、不跑动画，翻回去时滚动位置和已加载的数据都还在。
  Widget _slot(int index, double page, bool active, bool near) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !near || !active,
        child: Offstage(
          offstage: !near,
          child: TickerMode(
            enabled: near,
            child: Transform.translate(
              offset: Offset((index - page) * _width, 0),
              child: RepaintBoundary(child: widget.children[index]),
            ),
          ),
        ),
      ),
    );
  }
}
