import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/settings.dart';
import 'package:hobo/data/update.dart';
import 'package:hobo/ui/localizations.dart';
import 'package:hobo/ui/theme.dart';
import 'package:hobo/ui/widgets/update_dialog.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) {
  return PrismApp(
    theme: hoboTheme(brightness: Brightness.light, accentArgb: 0),
    localizationsDelegates: HoboUiLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    locale: const Locale('zh', 'CN'),
    builder: (context, inner) => ViewScope(
      size: MediaQuery.sizeOf(context),
      isMobile: true,
      child: inner ?? const SizedBox.shrink(),
    ),
    home: child,
  );
}

void main() {
  group('更新解析与版本比较', () {
    test('挑出更高正式版，跳过草稿与预发布，无 APK 附件也能跳 Release 页', () {
      final body = jsonEncode([
        {
          'tag_name': 'v1.10.0-beta.1',
          'prerelease': true,
          'draft': false,
          'html_url': 'https://github.com/ashshay/hobo/releases/tag/v1.10.0-beta.1',
          'body': '测试版',
        },
        {
          'tag_name': 'v1.11.0',
          'prerelease': false,
          'draft': true,
          'html_url': 'https://github.com/ashshay/hobo/releases/tag/v1.11.0',
          'body': '草稿',
        },
        {
          'tag_name': 'v1.09.0',
          'prerelease': false,
          'draft': false,
          'html_url': 'https://github.com/ashshay/hobo/releases/tag/v1.09.0',
          'body': '## 更新内容\n- 新增超话入口\n- 修复实况图',
          'assets': [
            {
              'name': 'hobo-1.09.0-arm64.apk',
              'browser_download_url':
                  'https://github.com/ashshay/hobo/releases/download/v1.09.0/hobo-1.09.0-arm64.apk',
              'size': 21000000,
            },
          ],
        },
        {
          'tag_name': 'v1.08.0',
          'prerelease': false,
          'draft': false,
          'html_url': 'https://github.com/ashshay/hobo/releases/tag/v1.08.0',
          'body': '当前版',
        },
      ]);

      final found = Updater.parseLatest(body, '1.08.0');
      expect(found, isNotNull);
      expect(found!.version, '1.09.0');
      expect(
        found.targetReleaseUrl,
        'https://github.com/ashshay/hobo/releases/tag/v1.09.0',
      );
      expect(found.sizeLabel, '20 MB');
      expect(Updater.parseLatest(body, '1.09.0'), isNull);

      final notes = Updater.plainReleaseNotes(found.notes);
      expect(notes, '更新内容\n· 新增超话入口\n· 修复实况图');
    });

    test('单条 release 没有 APK 附件仍返回有效 pageUrl', () {
      final body = jsonEncode({
        'tag_name': 'v1.09.0',
        'prerelease': false,
        'draft': false,
        'html_url': 'https://github.com/ashshay/hobo/releases/tag/v1.09.0',
        'body': '纯说明发布',
        'assets': [],
      });
      final found = Updater.parseLatest(body, '1.08.0');
      expect(found, isNotNull);
      expect(found!.downloadUrl, isEmpty);
      expect(
        found.targetReleaseUrl,
        'https://github.com/ashshay/hobo/releases/tag/v1.09.0',
      );
    });

    test('缓存命中时遵守自动开关与「不再提醒」记录', () async {
      final now = DateTime(2026, 11, 24, 22).millisecondsSinceEpoch;
      final cachedJson = jsonEncode([
        {
          'tag_name': 'v1.09.0',
          'prerelease': false,
          'draft': false,
          'html_url': 'https://github.com/ashshay/hobo/releases/tag/v1.09.0',
          'body': '- 修复实况图',
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'auto_check_update': true,
        'update_checked_at': now - 60 * 1000,
        'update_cache': cachedJson,
      });
      final prefs = await SharedPreferences.getInstance();
      final settings = Settings(prefs);

      // 未跳过时应提示弹窗。
      final first = await Updater.checkForUpdate(
        settings: settings,
        currentVersionOverride: '1.08.0',
        nowMillis: now,
      );
      expect(first.hasUpdate, isTrue);
      expect(first.shouldPrompt, isTrue);

      // 勾选不再提醒此版本后，不再弹出。
      settings.applySkippedUpdate('1.09.0');
      final skipped = await Updater.checkForUpdate(
        settings: settings,
        currentVersionOverride: '1.08.0',
        nowMillis: now,
      );
      expect(skipped.hasUpdate, isTrue);
      expect(skipped.skipped, isTrue);
      expect(skipped.shouldPrompt, isFalse);

      // 关闭自动检查更新开关后，自动检查直接跳过。
      settings.applyAutoCheckUpdate(false);
      final disabled = await Updater.checkForUpdate(
        settings: settings,
        currentVersionOverride: '1.08.0',
        nowMillis: now,
      );
      expect(disabled.hasUpdate, isFalse);
      expect(disabled.shouldPrompt, isFalse);
    });
  });

  group('更新弹窗交互', () {
    const sample = UpdateInfo(
      version: '1.09.0',
      tag: 'v1.09.0',
      notes: '- 超话入口\n- 实况图修复',
      pageUrl: 'https://github.com/ashshay/hobo/releases/tag/v1.09.0',
      size: 21500000,
    );

    testWidgets('勾选「此版本不再提醒」后点稍后返回 dontRemind=true', (tester) async {
      UpdateDialogResult? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showUpdateDialog(
                    context,
                    sample,
                    currentVersion: '1.08.0',
                    showDontRemind: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 v1.09.0'), findsOneWidget);
      expect(find.text('此版本不再提醒'), findsOneWidget);

      await tester.tap(find.text('此版本不再提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.update, isFalse);
      expect(result!.dontRemind, isTrue);
    });

    testWidgets('点击「立即更新」返回 update=true', (tester) async {
      UpdateDialogResult? result;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showUpdateDialog(
                    context,
                    sample,
                    currentVersion: '1.08.0',
                    showDontRemind: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.update, isTrue);
      expect(result!.dontRemind, isFalse);
    });
  });
}
