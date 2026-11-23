import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 独立 Ticker 驱动的连续可打断物理弹簧（同 prism 底栏镜片的做法）。
///
/// 为什么不用 `AnimationController.animateWith`：目标值在拖拽或高速连点期间逐帧变化，
/// 每次重设都会重启内部 Ticker，重启后第一帧 `elapsed = 0`；若每帧都重设目标，
/// 值会被钉在原地不动。这里在 [springTo] 时读当前瞬时速度另起一段 Simulation，
/// Ticker 已在跑就只把起跑时刻挪到这一帧，速度天然连续。
class ContinuousSpring extends ChangeNotifier {
  ContinuousSpring(TickerProvider vsync, double value, {this.rest = 1e-3})
    : _value = value {
    _ticker = vsync.createTicker(_tick);
  }

  /// 距离容差。速度容差按固有角频率放大，高速弹簧不会提前截断、低速弹簧不会无限拖尾。
  final double rest;

  late final Ticker _ticker;
  double _value;
  double _target = 0;
  SpringSimulation? _simulation;
  double _now = 0;
  double _start = 0;

  double get value => _value;
  double get target => _simulation == null ? _value : _target;
  double get velocity => _simulation?.dx(_now - _start) ?? 0;
  bool get isAnimating => _simulation != null;

  /// 本次起跑后是否已经走过至少一帧。首帧瞬时速度为 0，别把它当成「已经停稳」。
  bool get hasAdvanced => _now > _start;

  void springTo(
    double target,
    SpringDescription spring, {
    double? initialVelocity,
  }) {
    final v0 = initialVelocity ?? velocity;
    _simulation = SpringSimulation(
      spring,
      _value,
      target,
      v0,
      tolerance: Tolerance(
        distance: rest,
        // 屏幕比例很小的抖动交给容差收尾即可，不必逐帧追到 1e-6。
        velocity: math.max(rest * math.sqrt(spring.stiffness / spring.mass), 1e-3),
      ),
    );
    _target = target;
    if (_ticker.isActive) {
      _start = _now;
      return;
    }
    _now = _start = 0;
    _ticker.start();
  }

  void jumpTo(double value) {
    _simulation = null;
    if (_ticker.isActive) _ticker.stop();
    if (_value == value) return;
    _value = value;
    notifyListeners();
  }

  /// 停下并保留当前值：松手交接给另一段动画时用，避免旧 Simulation 再推一帧。
  void freeze() {
    _simulation = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration elapsed) {
    _now = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final simulation = _simulation;
    if (simulation == null) {
      _ticker.stop();
      return;
    }
    final t = _now - _start;
    if (simulation.isDone(t)) {
      _value = _target;
      _simulation = null;
      _ticker.stop();
    } else {
      _value = simulation.x(t);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
