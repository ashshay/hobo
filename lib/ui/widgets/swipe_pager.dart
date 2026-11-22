import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 左右滑动切页：手指横拖时给轻量跟手位移与边缘阻尼，松手达到阈值就翻页，
/// 切页时附带方向性平移淡入。纵向滚动完全留给内层列表。
class SwipePager extends StatefulWidget {
  const SwipePager({
    super.key,
    required this.index,
    required this.count,
    required this.onIndexChanged,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final int count;
  final ValueChanged<int> onIndexChanged;
  final Widget child;
  final bool enabled;

  @override
  State<SwipePager> createState() => _SwipePagerState();
}

class _SwipePagerState extends State<SwipePager>
    with TickerProviderStateMixin {
  /// 松手时走过的屏宽比例，或甩出的速度，够一个就切。
  static const _commitFraction = 0.22;
  static const _commitVelocity = 320.0;

  final ValueNotifier<double> _dragVisualDx = ValueNotifier<double>(0);
  late final AnimationController _snapBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final CurvedAnimation _snapCurve = CurvedAnimation(
    parent: _snapBack,
    curve: Curves.easeOutCubic,
  );
  late final AnimationController _switchAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  late final CurvedAnimation _switchCurve = CurvedAnimation(
    parent: _switchAnim,
    curve: Curves.easeOutCubic,
  );

  double _dx = 0;
  double _snapFrom = 0;
  int _switchDirection = 0; // +1 向右翻进下一页，-1 向左回上一页

  bool get _canSwipe => widget.enabled && widget.count > 1;

  bool get _disableAnimations =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    _snapBack.addListener(_tickSnapBack);
  }

  @override
  void didUpdateWidget(covariant SwipePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _snapBack.stop();
      _dragVisualDx.value = 0;
      if (_disableAnimations) {
        _switchDirection = 0;
        _switchAnim.value = 1;
      } else {
        _switchDirection = widget.index > oldWidget.index ? 1 : -1;
        _switchAnim
          ..stop()
          ..value = 0
          ..forward();
      }
    }
  }

  @override
  void dispose() {
    _snapBack.removeListener(_tickSnapBack);
    _snapCurve.dispose();
    _snapBack.dispose();
    _switchCurve.dispose();
    _switchAnim.dispose();
    _dragVisualDx.dispose();
    super.dispose();
  }

  void _tickSnapBack() {
    _dragVisualDx.value = _snapFrom * (1 - _snapCurve.value);
  }

  void _animateDragBackToZero() {
    if (_dragVisualDx.value == 0) return;
    if (_disableAnimations) {
      _dragVisualDx.value = 0;
      return;
    }
    _snapFrom = _dragVisualDx.value;
    _snapBack
      ..stop()
      ..value = 0
      ..forward();
  }

  void _onStart(DragStartDetails details) {
    _dx = 0;
    _snapBack.stop();
  }

  void _onUpdate(DragUpdateDetails details) {
    _dx += details.delta.dx;
    if (_disableAnimations) return;
    final atLeadingEdge = widget.index <= 0 && _dx > 0;
    final atTrailingEdge = widget.index >= widget.count - 1 && _dx < 0;
    if (atLeadingEdge || atTrailingEdge) {
      _dragVisualDx.value = (_dx * 0.09).clamp(-18.0, 18.0);
    } else {
      _dragVisualDx.value = (_dx * 0.24).clamp(-48.0, 48.0);
    }
  }

  void _onCancel() {
    _dx = 0;
    _animateDragBackToZero();
  }

  void _onEnd(DragEndDetails details) {
    final width = context.size?.width ?? 0;
    if (width <= 0) {
      _animateDragBackToZero();
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final far = _dx.abs() > width * _commitFraction;
    final fast = velocity.abs() > _commitVelocity;
    if (!far && !fast) {
      _animateDragBackToZero();
      return;
    }
    final step = _dx < 0 ? 1 : -1;
    final next = (widget.index + step).clamp(0, widget.count - 1);
    if (next != widget.index) {
      _dragVisualDx.value = 0;
      widget.onIndexChanged(next);
    } else {
      _animateDragBackToZero();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: Listenable.merge([_dragVisualDx, _switchCurve]),
      builder: (context, child) {
        final t = _switchCurve.value;
        final slideIn = _switchDirection * 22.0 * (1 - t);
        final tx = _dragVisualDx.value + slideIn;
        final opacity = t < 1 ? (0.82 + 0.18 * t) : 1.0;
        // 位移为 0 时也不能省掉这层 Transform：多插一层会让下面的整棵树
        // 换位置重建，翻页时各栏的列表状态（滚动位置、已加载的数据）会全丢。
        Widget result = Transform.translate(
          offset: Offset(tx, 0),
          child: child,
        );
        if (opacity < 1) {
          result = Opacity(opacity: opacity, child: result);
        }
        return result;
      },
      child: widget.child,
    );

    if (!_canSwipe) return content;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer
            >(
              () => HorizontalDragGestureRecognizer(debugOwner: this),
              (recognizer) => recognizer
                ..dragStartBehavior = DragStartBehavior.start
                ..onStart = _onStart
                ..onUpdate = _onUpdate
                ..onEnd = _onEnd
                ..onCancel = _onCancel,
            ),
      },
      child: content,
    );
  }
}
