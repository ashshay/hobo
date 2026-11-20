import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/ui/widgets/press_scale.dart';
import 'package:prism_ui/prism_ui.dart';

/// 测试画布 800×600，内容居中：200×100 的盒子落在 (300,250)–(500,350)。
const _center = Offset(400, 300);

/// [of] 里那层 Transform 的当前缩放。
///
/// 取矩阵的 x 轴长度：`getMaxScaleOnAxis` 会把恒为 1 的 z 轴也算进去，永远返回 1。
double _scaleOf(WidgetTester tester, Type of) {
  final transform = tester.widget<Transform>(
    find.descendant(of: find.byType(of), matching: find.byType(Transform)),
  );
  final storage = transform.transform.storage;
  return math.sqrt(storage[0] * storage[0] + storage[1] * storage[1]);
}

/// 按下后先空跑一帧让 ticker 起跳，再走满时长。
Future<void> _settle(WidgetTester tester, int milliseconds) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: milliseconds));
}

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(800, 600)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 200,
        height: 100,
        child: ColoredBox(color: const Color(0xFF101010), child: child),
      ),
    ),
  ),
);

void main() {
  group('PressScale', () {
    testWidgets('按下缩小，松手回弹', (tester) async {
      await tester.pumpWidget(
        _host(
          const PressScale(
            scale: 0.97,
            child: ColoredBox(color: Color(0xFF123456)),
          ),
        ),
      );
      expect(_scaleOf(tester, PressScale), 1);

      final gesture = await tester.startGesture(_center);
      await _settle(tester, 90);
      expect(_scaleOf(tester, PressScale), closeTo(0.97, 0.001));

      await gesture.up();
      await _settle(tester, 140);
      expect(_scaleOf(tester, PressScale), closeTo(1, 0.001));
    });

    testWidgets('手指移动超过 10px 就回弹，不黏住', (tester) async {
      await tester.pumpWidget(
        _host(
          const PressScale(
            scale: 0.97,
            child: ColoredBox(color: Color(0xFF123456)),
          ),
        ),
      );
      final gesture = await tester.startGesture(_center);
      await _settle(tester, 90);
      expect(_scaleOf(tester, PressScale), closeTo(0.97, 0.001));

      await gesture.moveBy(const Offset(0, 30));
      await _settle(tester, 140);
      expect(_scaleOf(tester, PressScale), closeTo(1, 0.001));
    });

    testWidgets('系统关闭动画时不动', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 600),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 200,
                height: 100,
                child: PressScale(
                  scale: 0.97,
                  child: const ColoredBox(color: Color(0xFF123456)),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(_center);
      await _settle(tester, 90);
      expect(_scaleOf(tester, PressScale), 1);
      await gesture.up();
    });
  });

  group('PressSurface.pressScale', () {
    testWidgets('按下缩小，松手回弹', (tester) async {
      await tester.pumpWidget(
        _host(
          PressSurface(
            fill: const Color(0xFF202020),
            shape: AppShape.all(12),
            pressScale: 0.985,
            onPressed: () {},
            child: const SizedBox(width: 200, height: 100),
          ),
        ),
      );
      expect(_scaleOf(tester, PressSurface), 1);

      final gesture = await tester.startGesture(_center);
      await _settle(tester, 90);
      expect(_scaleOf(tester, PressSurface), closeTo(0.985, 0.001));

      await gesture.up();
      await _settle(tester, 140);
      expect(_scaleOf(tester, PressSurface), closeTo(1, 0.001));
    });

    testWidgets('pressScale 为 1 时不插 Transform', (tester) async {
      await tester.pumpWidget(
        _host(
          PressSurface(
            fill: const Color(0xFF202020),
            shape: AppShape.all(12),
            onPressed: () {},
            child: const SizedBox(width: 200, height: 100),
          ),
        ),
      );
      expect(find.byType(Transform), findsNothing);
    });
  });
}
