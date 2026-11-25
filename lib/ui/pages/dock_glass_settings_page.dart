import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repo.dart';
import '../../data/settings.dart';
import '../widgets/capsule.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';

/// 底栏液态玻璃调节页：上方为可滚动高对比微博预览流 + 真实可拖拽底栏，下方为风格切换与双滑块控制区。
///
/// 拖动滑块时先驱动局部状态做到 60fps 零闪烁实时预览，松手、点击预设或离开页面时统一落盘。
class DockGlassSettingsPage extends StatefulWidget {
  const DockGlassSettingsPage({super.key});

  @override
  State<DockGlassSettingsPage> createState() => _DockGlassSettingsPageState();
}

class _DockGlassSettingsPageState extends State<DockGlassSettingsPage> {
  late DockGlassPreset _style;
  late double _frost;
  late double _refraction;
  int _previewTab = 0;
  Settings? _settings;

  bool get _isModified =>
      _style != DockGlassPreset.prism ||
      (_frost - defaultDockFrostAmount).abs() >= 0.005 ||
      (_refraction - defaultDockRefractionAmount).abs() >= 0.005;

  NavigationDockGlassStyle get _previewGlassStyle =>
      _style == DockGlassPreset.crystal
          ? NavigationDockGlassStyle.crystal(
              frost: _frost,
              refraction: _refraction,
            )
          : const NavigationDockGlassStyle.prism();

  @override
  void initState() {
    super.initState();
    final settings = context.read<Settings>();
    _settings = settings;
    _style = settings.dockGlassStyle;
    _frost = settings.dockFrostAmount;
    _refraction = settings.dockRefractionAmount;
  }

  @override
  void dispose() {
    // 防止用户拖动中途离开页面丢失最后一次调节值。
    final settings = _settings;
    if (settings != null) {
      if (settings.dockGlassStyle != _style) {
        settings.applyDockGlassStyle(_style);
      }
      if ((settings.dockFrostAmount - _frost).abs() >= 0.001) {
        settings.applyDockFrostAmount(_frost);
      }
      if ((settings.dockRefractionAmount - _refraction).abs() >= 0.001) {
        settings.applyDockRefractionAmount(_refraction);
      }
    }
    super.dispose();
  }

  void _selectStyle(DockGlassPreset next) {
    if (next == _style) return;
    HapticFeedback.selectionClick();
    setState(() => _style = next);
    context.read<Settings>().applyDockGlassStyle(next);
  }

  void _onFrostChanged(double raw) {
    final next = normalizeDockGlassAmount(raw);
    if ((next - _frost).abs() < 0.001) return;
    setState(() => _frost = next);
  }

  void _commitFrost(double raw) {
    final next = normalizeDockGlassAmount(raw);
    setState(() => _frost = next);
    context.read<Settings>().applyDockFrostAmount(next);
  }

  void _stepFrost(double delta) {
    final next = normalizeDockGlassAmount(_frost + delta);
    if ((next - _frost).abs() < 0.001) return;
    HapticFeedback.selectionClick();
    _commitFrost(next);
  }

  void _onRefractionChanged(double raw) {
    final next = normalizeDockGlassAmount(raw);
    if ((next - _refraction).abs() < 0.001) return;
    setState(() => _refraction = next);
  }

  void _commitRefraction(double raw) {
    final next = normalizeDockGlassAmount(raw);
    setState(() => _refraction = next);
    context.read<Settings>().applyDockRefractionAmount(next);
  }

  void _stepRefraction(double delta) {
    final next = normalizeDockGlassAmount(_refraction + delta);
    if ((next - _refraction).abs() < 0.001) return;
    HapticFeedback.selectionClick();
    _commitRefraction(next);
  }

  void _applyCrystalPreset(double frost, double refraction) {
    HapticFeedback.selectionClick();
    final f = normalizeDockGlassAmount(frost);
    final r = normalizeDockGlassAmount(refraction);
    setState(() {
      _style = DockGlassPreset.crystal;
      _frost = f;
      _refraction = r;
    });
    context.read<Settings>()
      ..applyDockGlassStyle(DockGlassPreset.crystal)
      ..applyDockFrostAmount(f)
      ..applyDockRefractionAmount(r);
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _style = DockGlassPreset.prism;
      _frost = defaultDockFrostAmount;
      _refraction = defaultDockRefractionAmount;
    });
    context.read<Settings>().resetDockGlass();
  }

  String _resolveAvatar(BuildContext context, Settings settings) {
    if (!settings.profileTabAvatar) return '';
    try {
      final repo = context.watch<Repo>();
      return repo.hasSession() ? repo.ownAvatar() : '';
    } on ProviderNotFoundException {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final dockAvatar = _resolveAvatar(context, settings);
    final isCrystal = settings.blurEffects && _style == DockGlassPreset.crystal;

    return HoboPage(
      title: '底栏液态玻璃',
      leading: const HoboBackButton(),
      actions: [
        if (_isModified)
          HoboBarAction(label: '恢复默认', onPressed: _reset),
      ],
      body: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ListView(
                      key: const ValueKey('dock-glass-preview-list'),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        pageTopInset(context),
                        16,
                        NavigationDock.heightOf(context) + 40,
                      ),
                      children: const [
                        _PreviewHint(),
                        SizedBox(height: 10),
                        _TextContrastPreviewCard(),
                        SizedBox(height: 12),
                        _SecondaryArticlePreviewCard(),
                        SizedBox(height: 12),
                        _ReadingSampleCard(),
                        SizedBox(height: 12),
                        _ClosingTextPreviewCard(),
                        SizedBox(height: 12),
                        _SpectrumPreviewCard(),
                        SizedBox(height: 12),
                        _ColorRibbonPreviewCard(),
                        SizedBox(height: 12),
                        _DarkContrastPreviewCard(),
                        SizedBox(height: 12),
                        _SecondaryArticlePreviewCard(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: NavigationDock(
                        key: const ValueKey('dock-glass-preview-dock'),
                        destinations: [
                          const NavigationDockDestination(
                            glyph: HoboGlyphs.home,
                            label: '微博',
                          ),
                          const NavigationDockDestination(
                            glyph: HoboGlyphs.explore,
                            label: '发现',
                          ),
                          const NavigationDockDestination(
                            glyph: HoboGlyphs.messages,
                            label: '消息',
                          ),
                          NavigationDockDestination(
                            glyph: HoboGlyphs.person,
                            label: '我',
                            icon: dockAvatar.isEmpty
                                ? null
                                : Avatar(url: dockAvatar, size: 28),
                          ),
                        ],
                        selectedIndex: _previewTab,
                        onSelected: (index) =>
                            setState(() => _previewTab = index),
                        tintSelection: isCrystal,
                        glassStyle: _previewGlassStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ControlPanel(
            blurEnabled: settings.blurEffects,
            style: _style,
            frost: _frost,
            refraction: _refraction,
            bottomInset: bottomInset,
            onBlurEnabledChanged: settings.applyBlurEffects,
            onStyleChanged: _selectStyle,
            onPresetSelected: _applyCrystalPreset,
            onFrostChanged: _onFrostChanged,
            onFrostEnd: _commitFrost,
            onStepFrost: _stepFrost,
            onRefractionChanged: _onRefractionChanged,
            onRefractionEnd: _commitRefraction,
            onStepRefraction: _stepRefraction,
          ),
        ],
      ),
    );
  }
}

class _PreviewHint extends StatelessWidget {
  const _PreviewHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '实时预览 · 可上下滚动卡片，并按住或拖动下方底栏体验折射与色散',
        style: AppTextStyle.footnote
            .of(context, emphasized: true)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _TextContrastPreviewCard extends StatelessWidget {
  const _TextContrastPreviewCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '如何在高通透液态玻璃与清晰微博阅读之间取得平衡？',
            style: AppTextStyle.headline
                .of(context)
                .copyWith(color: scheme.onSurface, height: 1.35),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _PreviewTag(label: '液态玻璃'),
              SizedBox(width: 6),
              _PreviewTag(label: '光学折射', color: Color(0xFF00897B)),
              SizedBox(width: 6),
              _PreviewTag(label: '微博信息流', color: Color(0xFFE65100)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '将磨砂设为 0% 时，底栏如同纯透明水晶镜片，背后每一行正文与配图都会清晰透出并在边缘产生强烈曲率弯折；若经常在纯文字时间线浏览，可将磨砂轻拉到 15%–30% 获得更柔和的对比度。',
            style: AppTextStyle.body
                .of(context)
                .copyWith(fontSize: 15, height: 1.5, color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Text(
            '转发 128 · 评论 386 · 赞 2.4万 · 刚刚',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PreviewTag extends StatelessWidget {
  const _PreviewTag({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ShapeDecoration(
        color: fg.withValues(alpha: 0.12),
        shape: AppShape.xs,
      ),
      child: Text(
        label,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(color: fg),
      ),
    );
  }
}

class _SecondaryArticlePreviewCard extends StatelessWidget {
  const _SecondaryArticlePreviewCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '物理弹簧与边缘折射预览',
            style: AppTextStyle.headline
                .of(context)
                .copyWith(color: scheme.onSurface, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(
            '向上滑动即可把下方的彩虹渐变、6 色色带与深色对比卡依次移到底栏背后；左右滑动底栏或滑块时已禁用页面侧滑返回。',
            style: AppTextStyle.body
                .of(context)
                .copyWith(
                  fontSize: 14,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ReadingSampleCard extends StatelessWidget {
  const _ReadingSampleCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '长列表滚动时，为什么边缘折射比纯半透明更有层次？',
            style: AppTextStyle.headline
                .of(context)
                .copyWith(color: scheme.onSurface, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            '当彩色卡片和文字滚入底栏下缘时，光线沿圆角胶囊边缘发生曲率弯折，让悬浮底栏自然从信息流上方“浮”出来，而不是生硬地盖在内容上面。',
            style: AppTextStyle.body
                .of(context)
                .copyWith(
                  fontSize: 14.5,
                  height: 1.48,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hobo 客户端 · 上海 · 10 分钟前',
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ClosingTextPreviewCard extends StatelessWidget {
  const _ClosingTextPreviewCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '密集文字底栏穿透测试 · 0123456789',
            style: AppTextStyle.headline
                .of(context)
                .copyWith(color: scheme.onSurface, height: 1.35),
          ),
          const SizedBox(height: 8),
          Text(
            '可以随时拖动下方「磨砂效果」与「玻璃折射」滑块，对比 0% 纯透明水晶质感与 20%–55% 轻雾质感在文字密集页面上的阅读舒适度。',
            style: AppTextStyle.body
                .of(context)
                .copyWith(fontSize: 15, height: 1.5, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _SpectrumPreviewCard extends StatelessWidget {
  const _SpectrumPreviewCard();

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return HoboCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 112,
            width: double.infinity,
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [
                        Color(0xFF0A4D8C),
                        Color(0xFF1A7F7A),
                        Color(0xFFD96B27),
                      ]
                    : const [
                        Color(0xFF1D74F5),
                        Color(0xFF12B886),
                        Color(0xFFFF7A45),
                      ],
              ),
              shape: AppShape.all(AppCorner.md),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: ShapeDecoration(
                        color: Colors.white.withValues(alpha: 0.24),
                        shape: AppShape.full,
                      ),
                      child: const Text(
                        'LIQUID GLASS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '01 · 02 · 03',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Text(
                  '把这张彩色卡片滑到底栏背后，观察胶囊边缘的光线弯折与按压色散',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '清透液态玻璃支持独立调节磨砂程度与折射强度，按压拖动滑块时还会呈现悬浮水滴色散与局部图标放大。',
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ColorRibbonPreviewCard extends StatelessWidget {
  const _ColorRibbonPreviewCard();

  static const _swatches = <Color>[
    Color(0xFF2563EB),
    Color(0xFF06B6D4),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFA855F7),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return HoboCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '高对比色带对照',
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < _swatches.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 54,
                    decoration: ShapeDecoration(
                      color: _swatches[i],
                      shape: AppShape.all(AppCorner.sm),
                    ),
                  ),
                ),
                if (i < _swatches.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkContrastPreviewCard extends StatelessWidget {
  const _DarkContrastPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF141824), Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        shape: AppShape.all(AppCorner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(
                  color: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                  shape: AppShape.full,
                ),
                child: const Text(
                  '深色背景对照',
                  style: TextStyle(
                    color: Color(0xFF7DD3FC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: ShapeDecoration(
                  color: const Color(0xFFF472B6).withValues(alpha: 0.22),
                  shape: AppShape.full,
                ),
                child: const Text(
                  '高光与色散',
                  style: TextStyle(
                    color: Color(0xFFF9A8D4),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '深色图片与夜景封面穿过玻璃底栏时的对比度预览',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '观察底栏 45° 斜角白高光以及按压拖动时水滴胶囊边缘的彩色折射。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.blurEnabled,
    required this.style,
    required this.frost,
    required this.refraction,
    required this.bottomInset,
    required this.onBlurEnabledChanged,
    required this.onStyleChanged,
    required this.onPresetSelected,
    required this.onFrostChanged,
    required this.onFrostEnd,
    required this.onStepFrost,
    required this.onRefractionChanged,
    required this.onRefractionEnd,
    required this.onStepRefraction,
  });

  final bool blurEnabled;
  final DockGlassPreset style;
  final double frost;
  final double refraction;
  final double bottomInset;
  final ValueChanged<bool> onBlurEnabledChanged;
  final ValueChanged<DockGlassPreset> onStyleChanged;
  final void Function(double frost, double refraction) onPresetSelected;
  final ValueChanged<double> onFrostChanged;
  final ValueChanged<double> onFrostEnd;
  final ValueChanged<double> onStepFrost;
  final ValueChanged<double> onRefractionChanged;
  final ValueChanged<double> onRefractionEnd;
  final ValueChanged<double> onStepRefraction;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final frostPct = (frost * 100).round();
    final refractPct = (refraction * 100).round();
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
        padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!blurEnabled) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: ShapeDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  shape: AppShape.all(AppCorner.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '模糊效果总开关已关闭，开启后底栏液态玻璃实时生效',
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      key: const ValueKey('dock-glass-enable-switch'),
                      value: blurEnabled,
                      onChanged: onBlurEnabledChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            HoboCapsule<DockGlassPreset>(
              value: style,
              onChanged: onStyleChanged,
              segments: const [
                (DockGlassPreset.prism, 'Prism 磨砂'),
                (DockGlassPreset.crystal, '清透液态玻璃'),
              ],
            ),
            const SizedBox(height: 14),
            if (style == DockGlassPreset.prism) ...[
              Text(
                '当前使用 Prism 默认磨砂胶囊，在密集文字上方保持高对比度。切换到「清透液态玻璃」后可分别调节磨砂程度与边缘折射强度。',
                style: AppTextStyle.footnote.of(context).copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey('dock-glass-try-crystal'),
                onPressed: () => onStyleChanged(DockGlassPreset.crystal),
                child: const Text('切换为清透液态玻璃'),
              ),
            ] else ...[
              Row(
                children: [
                  _PresetChip(
                    label: '纯透强折射',
                    active: frostPct == 0 && refractPct == 100,
                    onTap: () => onPresetSelected(0.0, 1.0),
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: '轻雾清透',
                    active: frostPct == 20 && refractPct == 85,
                    onTap: () => onPresetSelected(0.20, 0.85),
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: '柔雾玻璃',
                    active: frostPct == 55 && refractPct == 60,
                    onTap: () => onPresetSelected(0.55, 0.60),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _GlassSliderRow(
                sliderKey: const ValueKey('dock-frost-slider'),
                title: '磨砂效果',
                valueText: '$frostPct%',
                leftLabel: '透明',
                rightLabel: '磨砂',
                value: frost,
                onChanged: onFrostChanged,
                onChangeEnd: onFrostEnd,
                onTapLeft: () => onStepFrost(-0.1),
                onTapRight: () => onStepFrost(0.1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  height: 0.5,
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              _GlassSliderRow(
                sliderKey: const ValueKey('dock-refraction-slider'),
                title: '玻璃折射',
                valueText: '$refractPct%',
                leftLabel: '无折射',
                rightLabel: '强折射',
                value: refraction,
                onChanged: onRefractionChanged,
                onChangeEnd: onRefractionEnd,
                onTapLeft: () => onStepRefraction(-0.1),
                onTapRight: () => onStepRefraction(0.1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
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
    return Expanded(
      child: PressSurface(
        fill: active
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.onSurface.withValues(alpha: 0.06),
        shape: AppShape.full,
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context, emphasized: active)
                .copyWith(
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

class _GlassSliderRow extends StatelessWidget {
  const _GlassSliderRow({
    required this.sliderKey,
    required this.title,
    required this.valueText,
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onTapLeft,
    required this.onTapRight,
  });

  final Key sliderKey;
  final String title;
  final String valueText;
  final String leftLabel;
  final String rightLabel;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              title,
              style: AppTextStyle.subheadline
                  .of(context, emphasized: true)
                  .copyWith(color: scheme.onSurface),
            ),
            const Spacer(),
            Text(
              valueText,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .toTabular
                  .copyWith(color: scheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapLeft,
              child: SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    leftLabel,
                    maxLines: 1,
                    softWrap: false,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Slider(
                key: sliderKey,
                value: value.clamp(0.0, 1.0),
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: valueText,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapRight,
              child: SizedBox(
                width: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    rightLabel,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    softWrap: false,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
