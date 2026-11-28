import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'glyphs.dart';

/// 超话签到胶囊按钮：复用于超话详情页头和「我的超话」列表项。
///
/// 内部走 `PressSurface`，在 `HoboCard` 内按压时会自动声明手势归属，
/// 不会带着外层卡片一起缩放或误触发卡片点击；已签 / 签到中同样拦截点击，
/// 防止连点两下误跳进详情页。
class SuperTopicCheckInButton extends StatelessWidget {
  const SuperTopicCheckInButton({
    super.key,
    required this.checkedIn,
    required this.loading,
    required this.onPressed,
    this.compact = false,
  });

  final bool checkedIn;
  final bool loading;
  final VoidCallback? onPressed;

  /// 列表卡片用紧凑文案「已签」，详情页头用「已签到」。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final muted = checkedIn || loading;
    final fill = muted ? scheme.surfaceContainerHighest : scheme.primary;
    final fg = muted ? scheme.onSurfaceVariant : scheme.onPrimary;
    final horizontal = compact ? 12.0 : 14.0;
    final vertical = compact ? 6.0 : 7.0;
    final label = checkedIn ? (compact ? '已签' : '已签到') : '签到';

    final pill = PressSurface(
      fill: fill,
      shape: AppShape.full,
      pressScale: muted ? 1.0 : 0.95,
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      onPressed: muted ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const ActivityIndicator(size: 13),
            const SizedBox(width: 5),
            Text(
              '签到中',
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(fontSize: compact ? 12 : 13, color: fg),
            ),
          ] else ...[
            if (checkedIn) ...[
              GlyphIcon(HoboGlyphs.check, size: compact ? 13 : 14, color: fg),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(fontSize: compact ? 12 : 13, color: fg),
            ),
          ],
        ],
      ),
    );

    if (!muted) {
      return Semantics(button: true, label: label, child: pill);
    }
    // 禁用态仍吃掉点击事件，避免在列表卡片上连点两下时第二下穿透进详情页。
    return Semantics(
      button: true,
      enabled: false,
      label: loading ? '签到中' : label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: pill,
      ),
    );
  }
}
