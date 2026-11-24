import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import 'data/follow_tags.dart';
import 'data/repo.dart';
import 'data/settings.dart';
import 'data/store.dart';
import 'ui/chrome.dart';
import 'ui/localizations.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

/// 不画拉伸回弹的滚动行为：夹边滚动 + 原生滚动条，省掉每帧的全屏滤镜。
class _HoboScrollBehavior extends ScrollBehavior {
  const _HoboScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

/// 应用根：注入依赖、跟设置换主题、起 prism 的 PrismApp。
class HoboApp extends StatefulWidget {
  const HoboApp({
    super.key,
    required this.settings,
    required this.repo,
    required this.store,
    required this.followTags,
  });

  final Settings settings;
  final Repo repo;
  final Store store;
  final FollowTags followTags;

  @override
  State<HoboApp> createState() => _HoboAppState();
}

class _HoboAppState extends State<HoboApp> {
  final Map<String, ThemeData> _themes = {};
  Timer? _hueTimer;
  Color? _monetLight;
  Color? _monetDark;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_syncHueTimer);
    _syncHueTimer();
    unawaited(_loadMonet());
  }

  /// Android 12+ 从壁纸取色（Monet）。取不到就继续用 prism 的默认蓝。
  Future<void> _loadMonet() async {
    try {
      final seeds = await DynamicColorPlugin.getSystemSeeds();
      if (!mounted || seeds == null) return;
      setState(() {
        _monetLight = seeds.light;
        _monetDark = seeds.dark;
      });
    } on Object {
      // 旧系统或非 Android：没有壁纸取色，保持默认强调色。
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncHueTimer);
    _hueTimer?.cancel();
    super.dispose();
  }

  /// 强调色选了「Jeb_」才需要按帧刷新色相，其余情况完全不重建。
  void _syncHueTimer() {
    final cycling = widget.settings.accentColor == accentHueCycle;
    if (cycling && _hueTimer == null) {
      _hueTimer = Timer.periodic(const Duration(milliseconds: 140), (_) {
        if (mounted) setState(() {});
      });
    } else if (!cycling && _hueTimer != null) {
      _hueTimer?.cancel();
      _hueTimer = null;
    }
  }

  ThemeData _themeFor(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final configured = widget.settings.accentColor;
    final monet = dark ? _monetDark : _monetLight;
    // 默认（0）时优先跟随系统壁纸取色，并且直接拿 Monet 那一档当强调色。
    final argb = configured == 0 && monet != null
        ? monet.toARGB32()
        : accentArgbAt(configured, dark: dark);
    final scheme = hoboTheme(
      brightness: brightness,
      accentArgb: argb,
      tintCards: widget.settings.monetCards && monet != null,
      exactAccent: configured == 0 ? monet : null,
    );
    // 字号与字重由 PrismApp 的独立作用域驱动，不放进 ThemeData 缓存键，
    // 避免调节滑块时触发全屏 ThemeCrossFade 截屏过渡。
    final key =
        '${brightness.name}-${scheme.colorScheme.primary.toARGB32()}-${widget.settings.monetCards}';
    if (_themes.length > 16) _themes.clear();
    return _themes.putIfAbsent(key, () => scheme);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Store>.value(value: widget.store),
        ChangeNotifierProvider<Settings>.value(value: widget.settings),
        ChangeNotifierProvider<FollowTags>.value(value: widget.followTags),
        ChangeNotifierProvider<Repo>.value(value: widget.repo),
        ChangeNotifierProvider<ChromeController>(
          create: (_) => ChromeController(),
        ),
      ],
      child: Consumer<Settings>(
        builder: (context, settings, _) {
          final themeMode = switch (settings.darkMode) {
            1 => ThemeMode.light,
            2 => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return PrismApp(
            title: 'Hobo',
            debugShowCheckedModeBanner: false,
            theme: _themeFor(Brightness.light),
            darkTheme: _themeFor(Brightness.dark),
            themeMode: themeMode,
            textScale: settings.fontScale,
            minTextScale: fontScaleMin,
            maxTextScale: fontScaleMax,
            fontWeightDelta: settings.fontWeightDelta,
            // 「模糊效果」是总开关：关掉时顶栏退回实色，底栏也不走玻璃 shader。
            // 液态玻璃固定标准档，不再让用户分级。
            liquidGlass: settings.blurEffects
                ? LiquidGlassQuality.standard
                : null,
            localizationsDelegates: HoboUiLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            locale: const Locale('zh', 'CN'),
            // prism_ui 的顶栏与底栏都从 ViewScope 判断是不是手机布局，少了它会直接断言。
            builder: (context, child) => ScrollConfiguration(
              // Android 的拉伸回弹会在每帧做 ImageFiltered 采样，模拟器的软件 GPU
              // 顶不住（画面冻结）。这里统一用夹边滚动，去掉这层逐帧滤镜。
              behavior: const _HoboScrollBehavior(),
              child: ViewScope(
                size: MediaQuery.sizeOf(context),
                isMobile: true,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: const HoboShell(),
          );
        },
      ),
    );
  }
}
