import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/pages/font_settings_page.dart';
import 'package:hobo/ui/theme.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Settings settings, Widget child) {
  return ChangeNotifierProvider<Settings>.value(
    value: settings,
    child: Consumer<Settings>(
      builder: (context, s, _) => PrismApp(
        theme: hoboTheme(brightness: Brightness.light, accentArgb: 0),
        textScale: s.fontScale,
        minTextScale: fontScaleMin,
        maxTextScale: fontScaleMax,
        fontWeightDelta: s.fontWeightDelta,
        localizationsDelegates: HoboUiLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        locale: const Locale('zh', 'CN'),
        builder: (context, inner) => ViewScope(
          size: MediaQuery.sizeOf(context),
          isMobile: true,
          child: inner ?? const SizedBox.shrink(),
        ),
        home: child,
      ),
    ),
  );
}

void main() {
  group('字重偏移与设置持久化', () {
    test('shiftFontWeight 按档位偏移并夹紧到 w100..w900', () {
      expect(shiftFontWeight(FontWeight.w400, 0), FontWeight.w400);
      expect(shiftFontWeight(FontWeight.w400, -1), FontWeight.w300);
      expect(shiftFontWeight(FontWeight.w400, 1), FontWeight.w500);
      expect(shiftFontWeight(FontWeight.w400, 2), FontWeight.w600);
      expect(shiftFontWeight(FontWeight.w400, 3), FontWeight.w700);
      expect(shiftFontWeight(FontWeight.w600, 2), FontWeight.w800);
      expect(shiftFontWeight(FontWeight.w700, 5), FontWeight.w900);
      expect(shiftFontWeight(FontWeight.w200, -5), FontWeight.w100);
    });

    test('Settings 持久化字号与字重，越界自动夹紧并支持一键恢复默认', () async {
      SharedPreferences.setMockInitialValues({
        'font_scale': 1.8,
        'font_weight_delta': 9,
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = Settings(prefs);
      expect(settings.fontScale, fontScaleMax);
      expect(settings.fontWeightDelta, fontWeightDeltaMax);

      settings.applyFontScale(0.95);
      settings.applyFontWeightDelta(-1);
      expect(settings.fontScale, 0.95);
      expect(settings.fontWeightDelta, -1);
      expect(prefs.getDouble('font_scale'), 0.95);
      expect(prefs.getInt('font_weight_delta'), -1);

      expect(fontScaleLabel(1.0), '100% · 标准');
      expect(fontWeightLabel(-1), '较细');
      expect(fontWeightLabel(0), '标准');
      expect(fontWeightLabel(1), '适中');
      expect(fontWeightLabel(2), '偏粗');
      expect(fontWeightLabel(3), '粗体');

      settings.resetTypography();
      expect(settings.fontScale, 1.0);
      expect(settings.fontWeightDelta, 0);
    });

    test('formatCount 超过一万按万计数、超过一亿按亿计数', () {
      expect(formatCount(0), '0');
      expect(formatCount(736), '736');
      expect(formatCount(9999), '9999');
      expect(formatCount(10000), '1万');
      expect(formatCount(148347), '14.8万');
      expect(formatCount(1599000), '159.9万');
      expect(formatCount(1600000), '160万');
      expect(formatCount(10000000), '1000万');
      expect(formatCount(125000000), '1.3亿');
    });
  });

  group('FontSettingsPage 预览与滑块交互', () {
    testWidgets('点击档位实时更新预览作用域并落盘，恢复默认清零', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = Settings(prefs);

      await tester.pumpWidget(_host(settings, const FontSettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('实时预览'), findsOneWidget);
      expect(find.byKey(const ValueKey('font-scale-slider')), findsOneWidget);
      expect(find.byKey(const ValueKey('font-weight-slider')), findsOneWidget);
      expect(find.text('恢复默认'), findsNothing);

      // 初始预览卡片里的正文样式为 W400、标题为 W600。
      Text previewTitle() => tester.widget<Text>(find.text('Hobo 排版预览'));
      expect(previewTitle().style?.fontWeight, FontWeight.w600);

      // 点击快捷字号 130% 与粗细「偏粗」。
      await tester.tap(find.text('130%'));
      await tester.pumpAndSettle();
      expect(settings.fontScale, 1.3);
      expect(find.text('恢复默认'), findsOneWidget);

      await tester.tap(find.text('偏粗'));
      await tester.pumpAndSettle();
      expect(settings.fontWeightDelta, 2);
      // 偏移 +2 后，emphasized 昵称从 W600 联动升至 W800。
      expect(previewTitle().style?.fontWeight, FontWeight.w800);

      // 点击「恢复默认」回到 100% + 标准。
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(settings.fontScale, 1.0);
      expect(settings.fontWeightDelta, 0);
      expect(previewTitle().style?.fontWeight, FontWeight.w600);
      expect(find.text('恢复默认'), findsNothing);
    });
  });
}
