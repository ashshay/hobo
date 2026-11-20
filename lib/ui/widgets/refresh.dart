import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'glyphs.dart';

/// prism 风格的下拉刷新。
///
/// 列表用的是夹边滚动（没有回弹），所以这里不位移内容，只在顶部浮出一颗小药丸：
/// 下拉时随手指淡入放大，松手超过阈值就转圈刷新，刷新完再收回去。
class HoboRefresh extends StatefulWidget {
  const HoboRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.topInset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// 指示器落点：列表内容顶部留白（顶栏高度），免得被顶栏盖住。
  final double topInset;

  @override
  State<HoboRefresh> createState() => _HoboRefreshState();
}

class _HoboRefreshState extends State<HoboRefresh>
    with SingleTickerProviderStateMixin {
  static const _threshold = 72.0;
  static const _maxPull = 132.0;
  static const _hold = 52.0;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _settle,
    curve: Curves.easeOutCubic,
  );

  double _pull = 0;
  double _from = 0;
  double _to = 0;
  bool _refreshing = false;
  bool _atTop = true;
  bool _tracking = false;
  int? _pointer;
  double _startY = 0;
  double _startPull = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(_tick);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _tick() {
    final value = _from + (_to - _from) * _curve.value;
    if (value == _pull) return;
    setState(() => _pull = value);
  }

  void _animateTo(double target) {
    _from = _pull;
    _to = target;
    _settle
      ..stop()
      ..value = 0
      ..forward();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical) {
      _atTop = notification.metrics.extentBefore <= 0;
    }
    return false;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_refreshing || _pointer != null) return;
    _pointer = event.pointer;
    _tracking = _atTop;
    _startY = event.position.dy;
    _startPull = _pull;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_tracking || event.pointer != _pointer) return;
    final dy = event.position.dy - _startY;
    final next = (_startPull + dy * 0.5).clamp(0.0, _maxPull);
    if (next == _pull) return;
    _settle.stop();
    setState(() => _pull = next);
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final tracking = _tracking;
    _tracking = false;
    if (!tracking) return;
    if (_pull >= _threshold) {
      _start();
    } else if (_pull > 0) {
      _animateTo(0);
    }
  }

  Future<void> _start() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    _animateTo(_hold);
    try {
      await widget.onRefresh();
    } on Object {
      // 失败由调用方提示，这里只负责把指示器收回去。
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
        _animateTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_pull / _threshold).clamp(0.0, 1.0);
    final shown = _refreshing ? 1.0 : progress;
    final visible = _pull > 0.5 || _refreshing;
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: widget.child,
            ),
          ),
        ),
        if (visible)
          Positioned(
            left: 0,
            right: 0,
            top: widget.topInset + 6 + _pull * 0.55,
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: shown,
                  child: Transform.scale(
                    scale: 0.72 + 0.28 * shown,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        color: SurfaceLevel.floatingOf(
                          context.colorScheme,
                        ).colorOf(context.colorScheme),
                        shadows: dockShadows(context.colorScheme),
                        shape: AppShape.full,
                      ),
                      child: _refreshing
                          ? const ActivityIndicator(size: 16)
                          : GlyphIcon(
                              HoboGlyphs.refresh,
                              size: 16,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
