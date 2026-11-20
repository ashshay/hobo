import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/settings.dart';

/// 应用图标本身：同一张方图按设置的形状裁切。
///
/// 关于页、设置页和桌面上的画面因此是一致的；方图在 `assets/icon/hobo_icon.png`，
/// 由 `tool/make_icons.py` 从母版导出。
class HoboAppIcon extends StatelessWidget {
  const HoboAppIcon({
    super.key,
    this.size = 28,
    this.shape = AppIconShape.rounded,
  });

  final double size;
  final AppIconShape shape;

  /// 圆角半径按边长取比例，观感跟 `tool/make_icons.py` 里那颗超椭圆遮罩对齐。
  static const _cornerRatio = 0.23;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          image: const DecorationImage(
            image: AssetImage('assets/icon/hobo_icon.png'),
            fit: BoxFit.cover,
          ),
          shape: shape == AppIconShape.circle
              ? AppShape.circle
              : AppShape.all(size * _cornerRatio),
        ),
      ),
    );
  }
}
