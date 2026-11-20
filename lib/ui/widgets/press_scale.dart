import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// 按下即缩小的容器，给图片、视频这类没有 prism 按压面的整块内容用。
///
/// 只挂 [Listener]，不进手势竞技场：里面的 tap / 长按 / 列表滚动都照常识别，
/// 这里只负责"手指按下去的那一帧就有反馈"。手指移动超过 [_cancelSlop] 就回弹，
/// 免得滚动列表时一路缩着走。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    this.scale = 0.97,
    this.enabled = true,
    required this.child,
  });

  /// 按下时缩到多小。
  final double scale;
  final bool enabled;
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  static const _down = Duration(milliseconds: 90);
  static const _up = Duration(milliseconds: 140);

  /// 比 kTouchSlop（18）更早：手指一动就回弹，不等手势竞技场判负。
  static const _cancelSlop = 10.0;

  late final _press = AnimationController(
    vsync: this,
    duration: _down,
    reverseDuration: _up,
  );
  late final _curve = CurvedAnimation(parent: _press, curve: Curves.easeOutCubic);

  int? _pointer;
  Offset? _origin;

  @override
  void dispose() {
    _curve.dispose();
    _press.dispose();
    super.dispose();
  }

  bool get _active => widget.enabled && !context.disableAnimations;

  void _onDown(PointerDownEvent event) {
    if (!_active || _pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _press.forward();
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if ((event.position - _origin!).distance > _cancelSlop) _release();
  }

  void _release() {
    if (_pointer == null) return;
    _pointer = null;
    _origin = null;
    _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.scale) * _curve.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
