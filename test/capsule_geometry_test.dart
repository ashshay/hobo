import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/ui/widgets/capsule.dart';

/// 等宽分段的累计边界（长度 = 段数 + 1）。
List<double> _bounds(int count, double trackWidth) =>
    [for (var i = 0; i <= count; i++) i * trackWidth / count];

void main() {
  group('CapsulePillGeometry', () {
    const trackWidth = 300.0;
    const trackHeight = 36.0;

    test('任何位置 / 形变下都不越出圆角轨道', () {
      for (final count in [1, 2, 3, 4, 6]) {
        final bounds = _bounds(count, trackWidth);
        final maxPos = count - 1.0;
        for (var position = -0.35; position <= maxPos + 0.35; position += 0.05) {
          for (var stretch = -0.1; stretch <= 0.15; stretch += 0.01) {
            for (final boost in [0.0, 0.5, 1.0]) {
              final geometry = CapsulePillGeometry.compute(
                position: position,
                stretch: stretch,
                pressBoost: boost,
                bounds: bounds,
                trackHeight: trackHeight,
              );
              expect(
                geometry.fitsIn(trackWidth, trackHeight),
                isTrue,
                reason:
                    'count=$count position=${position.toStringAsFixed(2)} '
                    'stretch=${stretch.toStringAsFixed(2)} boost=$boost → '
                    '${geometry.rect}',
              );
            }
          }
        }
      }
    });

    test('静止时正好落在格子上', () {
      final bounds = _bounds(3, trackWidth);
      for (var i = 0; i < 3; i++) {
        final geometry = CapsulePillGeometry.compute(
          position: i.toDouble(),
          stretch: 0,
          pressBoost: 0,
          bounds: bounds,
          trackHeight: trackHeight,
        );
        expect(geometry.left, closeTo(i * 100, 0.01));
        expect(geometry.width, closeTo(100, 0.01));
        expect(geometry.height, closeTo(trackHeight, 0.01));
        expect(geometry.top, closeTo(0, 0.01));
      }
    });

    test('切到中间项时滑块中心真实越过目标位（保留欠阻尼过冲）', () {
      final bounds = _bounds(3, trackWidth);
      final resting = CapsulePillGeometry.compute(
        position: 1,
        stretch: 0,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      final overshoot = CapsulePillGeometry.compute(
        position: 1.25,
        stretch: 0,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      expect(overshoot.rect.center.dx, greaterThan(resting.rect.center.dx));
      // 两端的压墙逻辑不该被中间项触发。
      expect(overshoot.width, closeTo(100, 0.01));
    });

    test('两端过冲转成压墙压缩：贴住端壁、水平变窄', () {
      final bounds = _bounds(3, trackWidth);
      final left = CapsulePillGeometry.compute(
        position: -0.3,
        stretch: 0,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      expect(left.left, 0);
      expect(left.width, lessThan(100));

      // 同样的拉伸量，撞墙时会被压缩抵消一部分。
      final stretched = CapsulePillGeometry.compute(
        position: 1,
        stretch: 0.1,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      final walled = CapsulePillGeometry.compute(
        position: 2.3,
        stretch: 0.1,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      expect(walled.left + walled.width, closeTo(trackWidth, 0.01));
      expect(walled.width, lessThan(stretched.width));
    });

    test('按住时的膨胀只放大一点点', () {
      final bounds = _bounds(2, trackWidth);
      final rest = CapsulePillGeometry.compute(
        position: 0,
        stretch: 0,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      final pressed = CapsulePillGeometry.compute(
        position: 0,
        stretch: 0,
        pressBoost: 1,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      expect(pressed.width, closeTo(rest.width * 1.025, 0.01));
    });

    test('不等宽分段按各自宽度过渡', () {
      final bounds = <double>[0, 40, 120, 300];
      final geometry = CapsulePillGeometry.compute(
        position: 0,
        stretch: 0,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      expect(geometry.left, 0);
      expect(geometry.width, closeTo(40, 0.01));

      final second = CapsulePillGeometry.compute(
        position: 1,
        stretch: 0,
        pressBoost: 0,
        bounds: bounds,
        trackHeight: trackHeight,
      );
      expect(second.left, closeTo(40, 0.01));
      expect(second.width, closeTo(80, 0.01));
    });

    test('空分段不崩', () {
      final geometry = CapsulePillGeometry.compute(
        position: 0,
        stretch: 0,
        pressBoost: 0,
        bounds: const [0],
        trackHeight: trackHeight,
      );
      expect(geometry.width, 0);
      expect(geometry.height, 0);
    });
  });
}
