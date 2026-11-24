import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/settings.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';

/// 字体与字号调节页：顶部实时微博卡片预览，底部固定字号与粗细双滑块。
///
/// 拖动滑块时先驱动局部预览作用域（MediaQuery.textScaler + FontWeightScope）
/// 做到 60fps 零闪烁预览，松手或点击快捷档位时立即落盘生效到全站。
class FontSettingsPage extends StatefulWidget {
  const FontSettingsPage({super.key});

  @override
  State<FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends State<FontSettingsPage> {
  late double _scale;
  late int _weightDelta;
  Settings? _settings;

  bool get _isModified =>
      (_scale - 1.0).abs() >= 0.005 || _weightDelta != 0;

  @override
  void initState() {
    super.initState();
    final settings = context.read<Settings>();
    _settings = settings;
    _scale = settings.fontScale;
    _weightDelta = settings.fontWeightDelta;
  }

  @override
  void dispose() {
    // 防止用户拖动中途直接系统侧滑返回时丢失最后一次调节值。
    final settings = _settings;
    if (settings != null) {
      if ((settings.fontScale - _scale).abs() >= 0.001) {
        settings.applyFontScale(_scale);
      }
      if (settings.fontWeightDelta != _weightDelta) {
        settings.applyFontWeightDelta(_weightDelta);
      }
    }
    super.dispose();
  }

  void _onScaleChanged(double raw) {
    final next = normalizeFontScale(raw);
    if ((next - _scale).abs() < 0.001) return;
    HapticFeedback.selectionClick();
    setState(() => _scale = next);
  }

  void _commitScale(double raw) {
    final next = normalizeFontScale(raw);
    setState(() => _scale = next);
    context.read<Settings>().applyFontScale(next);
  }

  void _stepScale(double delta) {
    final next = normalizeFontScale(_scale + delta);
    if ((next - _scale).abs() < 0.001) return;
    HapticFeedback.selectionClick();
    _commitScale(next);
  }

  void _onWeightChanged(double raw) {
    final next = normalizeFontWeightDelta(raw.round());
    if (next == _weightDelta) return;
    HapticFeedback.selectionClick();
    setState(() => _weightDelta = next);
  }

  void _commitWeight(int value) {
    final next = normalizeFontWeightDelta(value);
    if (next != _weightDelta) HapticFeedback.selectionClick();
    setState(() => _weightDelta = next);
    context.read<Settings>().applyFontWeightDelta(next);
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _scale = 1.0;
      _weightDelta = 0;
    });
    context.read<Settings>().resetTypography();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final scheme = context.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return HoboPage(
      title: '字体与字号',
      leading: const HoboBackButton(),
      actions: [
        if (_isModified)
          HoboBarAction(label: '恢复默认', onPressed: _reset),
      ],
      body: Column(
        children: [
          Expanded(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(_scale),
              ),
              child: FontWeightScope(
                delta: _weightDelta,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    pageTopInset(context),
                    16,
                    16,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        '实时预览',
                        style: AppTextStyle.footnote
                            .of(context, emphasized: true)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    _PostPreviewCard(iconShape: settings.iconShape),
                    const SizedBox(height: 12),
                    const _HierarchyPreviewCard(),
                  ],
                ),
              ),
            ),
          ),
          _ControlPanel(
            scale: _scale,
            weightDelta: _weightDelta,
            bottomInset: bottomInset,
            onScaleChanged: _onScaleChanged,
            onScaleEnd: _commitScale,
            onStepScale: _stepScale,
            onQuickScale: _commitScale,
            onWeightChanged: _onWeightChanged,
            onWeightEnd: (raw) => _commitWeight(raw.round()),
            onQuickWeight: _commitWeight,
          ),
        ],
      ),
    );
  }
}

/// 模拟真实微博卡片的预览块：包含头像、昵称、时间来源、正文、话题链接、引用块与互动数。
class _PostPreviewCard extends StatelessWidget {
  const _PostPreviewCard({required this.iconShape});

  final AppIconShape iconShape;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HoboAppIcon(size: 40, shape: iconShape),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Hobo 排版预览',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.subheadline
                                .of(context, emphasized: true)
                                .copyWith(
                                  fontSize: 15,
                                  color: scheme.onSurface,
                                ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const VerifiedBadge(),
                        const SizedBox(width: 4),
                        const MemberBadge(svip: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '刚刚 · 10:24 · Hobo 客户端 · 上海',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1.of(context).copyWith(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: AppTextStyle.body.of(context).copyWith(
                fontSize: 16,
                height: 1.42,
                color: scheme.onSurface,
              ),
              children: [
                const TextSpan(
                  text:
                      '拖动下方滑块可实时调节全局字号与字体粗细。中英文混排 Hobo 2026 与数字 123,456 均会同步生效。',
                ),
                TextSpan(
                  text: ' #字体排版预览#',
                  style: TextStyle(color: scheme.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: ShapeDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
              shape: AppShape.all(AppCorner.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@评论示例',
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(fontSize: 12, color: scheme.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  '标题、正文与次要信息会随粗细档位按比例联动，保持清晰的视觉层次。',
                  style: AppTextStyle.body.of(context).copyWith(
                    fontSize: 14,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _PreviewStat(glyph: HoboGlyphs.repost, label: '12'),
              _PreviewStat(glyph: HoboGlyphs.comment, label: '38'),
              _PreviewStat(glyph: HoboGlyphs.likeOutline, label: '128'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.glyph, required this.label});

  final Glyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurfaceVariant;
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlyphIcon(glyph, size: 17, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyle.caption1.of(context).copyWith(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 字重层级对照卡：一眼区分标题 / 正文 / 辅助信息的粗细差异。
class _HierarchyPreviewCard extends StatelessWidget {
  const _HierarchyPreviewCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '标题与重点文字 · Headline',
            style: AppTextStyle.headline.of(context).copyWith(
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '正文阅读样例 · Regular Body 0123456789',
            style: AppTextStyle.body.of(context).copyWith(
              fontSize: 15,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '时间、来源与说明文字 · Secondary Caption',
            style: AppTextStyle.caption1.of(context).copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '提示：支持可变字体的系统各档细腻过渡；部分仅含常规与粗体两档的系统字体在「偏粗 / 粗体」时中文会明显加粗。',
            style: AppTextStyle.caption2.of(context).copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部固定调节面板：字号滑块 + 粗细滑块。调节过程中面板位置不动，不跟手抖动。
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.scale,
    required this.weightDelta,
    required this.bottomInset,
    required this.onScaleChanged,
    required this.onScaleEnd,
    required this.onStepScale,
    required this.onQuickScale,
    required this.onWeightChanged,
    required this.onWeightEnd,
    required this.onQuickWeight,
  });

  final double scale;
  final int weightDelta;
  final double bottomInset;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onScaleEnd;
  final ValueChanged<double> onStepScale;
  final ValueChanged<double> onQuickScale;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<double> onWeightEnd;
  final ValueChanged<int> onQuickWeight;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final pct = (scale * 100).round();
    final bodyWeight = shiftFontWeight(FontWeight.w400, weightDelta).value;
    // 控制区文字缩放上限压在 1.1x，防止用户在 130% 大字号时把底部滑块区撑出屏幕。
    final controlScaler = MediaQuery.textScalerOf(context).clamp(
      minScaleFactor: 0.9,
      maxScaleFactor: 1.1,
    );

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: controlScaler),
      child: Container(
        decoration: ShapeDecoration(
          color: context.surfaceLevel.next.colorOf(scheme),
          shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppCorner.xl),
            ),
          ),
          shadows: [
            BoxShadow(
              color: scheme.shadow.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.36 : 0.08,
              ),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- 字号调节 ----
            Row(
              children: [
                Text(
                  '字号大小',
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const Spacer(),
                Text(
                  fontScaleLabel(scale),
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onStepScale(-0.05),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      'A',
                      style: AppTextStyle.footnote.of(context).copyWith(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('font-scale-slider'),
                    value: scale.clamp(fontScaleMin, fontScaleMax),
                    min: fontScaleMin,
                    max: fontScaleMax,
                    divisions: fontScaleDivisions,
                    label: '$pct%',
                    onChanged: onScaleChanged,
                    onChangeEnd: onScaleEnd,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onStepScale(0.05),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      'A',
                      style: AppTextStyle.headline.of(context).copyWith(
                        fontSize: 21,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickTick(
                    label: '85%',
                    active: pct == 85,
                    onTap: () => onQuickScale(0.85),
                  ),
                  _QuickTick(
                    label: '标准 100%',
                    active: pct == 100,
                    onTap: () => onQuickScale(1.0),
                  ),
                  _QuickTick(
                    label: '130%',
                    active: pct == 130,
                    onTap: () => onQuickScale(1.3),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                height: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            // ---- 字体粗细调节 ----
            Row(
              children: [
                Text(
                  '字体粗细',
                  style: AppTextStyle.subheadline
                      .of(context, emphasized: true)
                      .copyWith(color: scheme.onSurface),
                ),
                const Spacer(),
                Text(
                  '${fontWeightLabel(weightDelta)} · W$bodyWeight',
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onQuickWeight(weightDelta - 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      '细',
                      style: AppTextStyle.footnote.of(context).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey('font-weight-slider'),
                    value: weightDelta
                        .clamp(fontWeightDeltaMin, fontWeightDeltaMax)
                        .toDouble(),
                    min: fontWeightDeltaMin.toDouble(),
                    max: fontWeightDeltaMax.toDouble(),
                    divisions: fontWeightDeltaMax - fontWeightDeltaMin,
                    label: fontWeightLabel(weightDelta),
                    onChanged: onWeightChanged,
                    onChangeEnd: onWeightEnd,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onQuickWeight(weightDelta + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Text(
                      '粗',
                      style: AppTextStyle.footnote.of(context).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var d = fontWeightDeltaMin;
                      d <= fontWeightDeltaMax;
                      d++)
                    _QuickTick(
                      label: fontWeightLabel(d),
                      active: weightDelta == d,
                      onTap: () => onQuickWeight(d),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTick extends StatelessWidget {
  const _QuickTick({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: AppTextStyle.caption1.of(context).copyWith(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
