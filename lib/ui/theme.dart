import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data/settings.dart';

/// 默认强调色：prism 的蓝。
const defaultAccent = Color(0xFF0A84FF);

/// 浅色模式的页面底色跟着 prism 的 surfaceContainer 走，这里只在系统色偏暗时兜底。
const _hueCyclePeriodMs = 36000;

/// 强调色：预设值 / 自定义 ARGB / 色相缓慢循环（Jeb_）。
int accentArgbAt(int configured, {required bool dark, DateTime? now}) {
  if (configured == accentHueCycle) {
    final millis =
        (now ?? DateTime.now()).millisecondsSinceEpoch % _hueCyclePeriodMs;
    final hue = millis / _hueCyclePeriodMs * 360;
    return _hsvToArgb(hue, dark ? 0.78 : 0.82, dark ? 0.94 : 0.88);
  }
  if (configured == 0) return defaultAccent.toARGB32();
  return configured | 0xFF000000;
}

Color accentColorAt(int configured, {required bool dark, DateTime? now}) =>
    Color(accentArgbAt(configured, dark: dark, now: now));

int _hsvToArgb(double hue, double saturation, double value) {
  final h = ((hue % 360) + 360) % 360;
  final c = value * saturation;
  final x = c * (1 - ((h / 60) % 2 - 1).abs());
  final m = value - c;
  final (double r, double g, double b) = switch (h ~/ 60) {
    0 => (c, x, 0),
    1 => (x, c, 0),
    2 => (0, c, x),
    3 => (0, x, c),
    4 => (x, 0, c),
    _ => (c, 0, x),
  };
  int channel(double v) => ((v + m) * 255).round().clamp(0, 255);
  return (0xFF << 24) | (channel(r) << 16) | (channel(g) << 8) | channel(b);
}

/// 应用主题。light / dark 各一份；强调色变了就是新的一份。
///
/// [tintCards] 打开时用 `ColorStyle.tinted`：中性面（页面/卡片）会带上种子色的色调，
/// 也就是「卡片背景跟随壁纸取色」；关掉时是 prism 默认的近灰面。
///
/// [exactAccent] 是 Monet 从壁纸取到的强调色：给了它就直接当 `primary` 用，
/// 不再让配色算法从种子色重新推一档（那样推出来的颜色和系统强调色总有偏差）。
ThemeData hoboTheme({
  required Brightness brightness,
  required int accentArgb,
  bool tintCards = false,
  Color? exactAccent,
}) {
  var scheme = seededColorScheme(
    seedColor: Color(accentArgb),
    brightness: brightness,
    style: tintCards ? ColorStyle.tinted : ColorStyle.soft,
  );
  if (exactAccent != null) {
    // 只换强调色本身：容器色仍由同一颗种子推出来，和它同色相，不会打架。
    scheme = scheme.copyWith(
      primary: exactAccent,
      onPrimary: _onAccent(exactAccent),
      surfaceTint: exactAccent,
    );
  }
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: SurfaceLevel.page.colorOf(scheme),
    fontFamily: null,
    fontFamilyFallback: const [
      'PingFang SC',
      'Noto Sans CJK SC',
      'Source Han Sans SC',
      'Microsoft YaHei',
      'sans-serif',
    ],
  );
}

/// 强调色上的文字：亮底用近黑，暗底用白。
Color _onAccent(Color color) => color.computeLuminance() > 0.55
    ? const Color(0xE6000000)
    : const Color(0xFFFFFFFF);

/// 正文颜色、次要色、分隔线这些到处都在用的角色。
extension HoboColors on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;

  Color get ink => scheme.onSurface;

  Color get inkSecondary => scheme.onSurfaceVariant;

  Color get inkTertiary => scheme.onSurfaceVariant.withValues(alpha: 0.7);

  Color get accent => scheme.primary;

  Color get danger => scheme.error;

  Color get success => const Color(0xFF30D158);

  Color get cardFill => surfaceLevel.next.colorOf(scheme);

  Color get cardPressed => surfaceLevel.next.next.colorOf(scheme);

  Color get pageFill => SurfaceLevel.page.colorOf(scheme);

  bool get isDark => scheme.brightness == Brightness.dark;
}

/// 「N 万 / N 亿」这种展示数字。微博接口本身也会给这种串，统一在这里格式化。
String formatCount(int value) {
  if (value < 10000) return '$value';
  if (value < 100000000) {
    final wan = value / 10000;
    return '${_trim(wan)}万';
  }
  final yi = value / 100000000;
  return '${_trim(yi)}亿';
}

String _trim(double value) {
  final text = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// 小圆点分隔的副标题：`11-16 · 来自 iPhone`。
String joinMeta(List<String> parts) =>
    parts.where((part) => part.trim().isNotEmpty).join(' · ');

/// 图片地址按屏幕宽度挑画质：列表里用 690 宽就够，原图只在看图页加载。
String sizedImageUrl(String url, int width) {
  if (url.isEmpty) return url;
  if (url.contains('sinaimg.cn/large/')) {
    return url.replaceFirst('/large/', '/mw690/');
  }
  return url;
}
