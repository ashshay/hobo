import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/like_gate.dart';

void main() {
  /// 一个可以手动拨动的时钟，免得测试真的等半分钟。
  late DateTime now;
  late LikeGate gate;

  setUp(() {
    now = DateTime(2026, 11, 20, 15);
    gate = LikeGate(
      base: const Duration(seconds: 30),
      max: const Duration(minutes: 5),
      clock: () => now,
    );
  });

  void advance(Duration by) => now = now.add(by);

  group('LikeGate', () {
    test('一开始不拦，也没有剩余时间', () {
      expect(gate.blocked, isFalse);
      expect(gate.remaining, Duration.zero);
    });

    test('撞到 20016 后按基础时长冷却', () {
      gate.onRejected();
      expect(gate.blocked, isTrue);
      expect(gate.remaining, const Duration(seconds: 30));
    });

    test('冷却到点自动放行', () {
      gate.onRejected();
      advance(const Duration(seconds: 29));
      expect(gate.blocked, isTrue);
      expect(gate.remaining, const Duration(seconds: 1));

      advance(const Duration(seconds: 1));
      expect(gate.blocked, isFalse);
      expect(gate.remaining, Duration.zero);
    });

    test('连续撞到时退避翻倍', () {
      gate.onRejected();
      expect(gate.remaining, const Duration(seconds: 30));

      advance(const Duration(seconds: 31));
      gate.onRejected();
      expect(gate.remaining, const Duration(seconds: 60));

      advance(const Duration(seconds: 61));
      gate.onRejected();
      expect(gate.remaining, const Duration(seconds: 120));
    });

    test('退避有上限，不会无限翻倍', () {
      for (var i = 0; i < 10; i++) {
        gate.onRejected();
        advance(const Duration(minutes: 6));
      }
      gate.onRejected();
      expect(gate.remaining, const Duration(minutes: 5));
    });

    test('成功一次就清零', () {
      gate.onRejected();
      advance(const Duration(seconds: 31));
      gate.onRejected();
      expect(gate.remaining, const Duration(seconds: 60));

      advance(const Duration(seconds: 61));
      gate.onAccepted();
      expect(gate.blocked, isFalse);

      // 清零后再撞，重新从基础时长开始，而不是接着翻倍。
      gate.onRejected();
      expect(gate.remaining, const Duration(seconds: 30));
    });
  });
}
