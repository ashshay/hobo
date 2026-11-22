// 视频倍速：存在设置里的是一档枚举，读回来要能对上；对不上就退回原速。
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/settings.dart';

void main() {
  test('存过的那一档能原样读回来', () {
    for (final speed in VideoSpeed.values) {
      expect(VideoSpeed.fromRate(speed.rate), speed);
    }
  });

  test('没存过 / 存的值不认识都退回原速', () {
    expect(VideoSpeed.fromRate(null), VideoSpeed.normal);
    expect(VideoSpeed.fromRate(0.42), VideoSpeed.normal);
    expect(VideoSpeed.fromRate(3), VideoSpeed.normal);
  });

  test('标签就是播放器上显示的那一串', () {
    expect(VideoSpeed.normal.label, '1.0x');
    expect(VideoSpeed.oneHalf.label, '1.5x');
    expect(VideoSpeed.twice.label, '2.0x');
    expect(VideoSpeed.normal.rate, 1.0);
  });
}
