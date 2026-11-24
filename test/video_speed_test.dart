// 视频倍速：存在设置里的是一档枚举，读回来要能对上；对不上就退回原速；长按按当前倍速临时加速。
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/ui/pages/video_page.dart';

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

  test('长按倍速：低于 2.0x 时临时加速到 2.0x，已是 2.0x 时加速到 3.0x', () {
    expect(longPressBoostRate(VideoSpeed.half), 2.0);
    expect(longPressBoostRate(VideoSpeed.threeQuarters), 2.0);
    expect(longPressBoostRate(VideoSpeed.normal), 2.0);
    expect(longPressBoostRate(VideoSpeed.fiveQuarters), 2.0);
    expect(longPressBoostRate(VideoSpeed.oneHalf), 2.0);
    expect(longPressBoostRate(VideoSpeed.twice), 3.0);
    expect(formatPlaybackRate(2.0), '2.0x');
    expect(formatPlaybackRate(3.0), '3.0x');
    expect(formatPlaybackRate(1.25), '1.25x');
  });
}
