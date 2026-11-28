import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/api.dart';
import 'package:hobo/data/store.dart';
import 'package:hobo/data/super_topic.dart';
import 'package:hobo/data/super_topic_id.dart';
import 'package:hobo/ui/theme.dart';
import 'package:hobo/ui/widgets/common.dart';
import 'package:hobo/ui/widgets/super_topic_checkin_button.dart';
import 'package:prism_ui/prism_ui.dart';

Map<String, dynamic> _json(String text) {
  final decoded = jsonDecode(text);
  return {for (final e in (decoded as Map).entries) e.key.toString(): e.value};
}

void main() {
  group('超话 ID 与列表解析', () {
    const cid1 = '1008080123456789abcdef0123456789abcdef';
    const cid2 = '100808fedcba9876543210fedcba9876543210';

    test('兼容 oid 前缀、桌面 /p/ 链接和任意栏目标记后缀', () {
      expect(normalizedSuperTopicId('1022:$cid1'), cid1);
      expect(normalizedSuperTopicId('${cid1}_-_sort_time'), cid1);
      expect(superTopicId('https://weibo.com/p/$cid1/super_index'), cid1);
      expect(superTopicId('1022:$cid2'), cid2);
      expect(superTopicId('https://weibo.com/p/not_a_supertopic'), isNull);
    });

    test('解析 m.weibo.cn 关注的超话列表与分页游标', () {
      final root = _json('''
      {
        "ok": 1,
        "data": {
          "cardlistInfo": {"since_id": "cursor_2"},
          "cards": [
            {
              "card_type": 11,
              "card_group": [
                {
                  "card_type": 8,
                  "title_sub": "#数码超话#",
                  "pic": "//wx1.sinaimg.cn/thumb/st1.jpg",
                  "desc1": "LV.6 · 12.3万帖子",
                  "desc2": "今天已签到",
                  "scheme": "https://m.weibo.cn/p/index?containerid=$cid1"
                },
                {
                  "card_type": 8,
                  "title_sub": "重复项",
                  "scheme": "https://m.weibo.cn/p/index?containerid=$cid1"
                }
              ]
            }
          ]
        }
      }
      ''');

      final page = parseSuperTopicList(root);
      expect(page.items.length, 1);
      expect(page.items.single.containerId, cid1);
      expect(page.items.single.title, '数码超话');
      expect(page.items.single.avatar, 'https://wx1.sinaimg.cn/thumb/st1.jpg');
      expect(page.items.single.desc1, 'LV.6 · 12.3万帖子');
      expect(page.items.single.desc2, '今天已签到');
      expect(page.nextCursor, 'cursor_2');
    });

    test('解析 weibo.com 桌面端关注超话列表（topicContent）', () {
      final root = _json('''
      {
        "ok": 1,
        "data": {
          "max_page": 3,
          "list": [
            {
              "oid": "1022:$cid2",
              "title": "摄影超话",
              "pic": "https://wx2.sinaimg.cn/thumb/st2.jpg",
              "content1": "LV.3",
              "content2": "每日精选摄影",
              "link": "https://weibo.com/p/$cid2"
            }
          ]
        }
      }
      ''');

      final page = parseSuperTopicList(root, currentPage: 1);
      expect(page.items.length, 1);
      expect(page.items.single.containerId, cid2);
      expect(page.items.single.title, '摄影超话');
      expect(page.items.single.desc1, 'LV.3');
      expect(page.items.single.desc2, '每日精选摄影');
      expect(page.nextCursor, 'page:2');
    });

    test('搜索超话卡片同时保留头像', () {
      final root = _json('''
      {
        "ok": 1,
        "data": {
          "cards": [
            {
              "card_group": [
                {
                  "title_sub": "#Flutter#",
                  "pic": "https://wx1.sinaimg.cn/thumb/fl.jpg",
                  "desc1": "10万阅读",
                  "scheme": "https://m.weibo.cn/p/index?containerid=$cid1"
                }
              ]
            }
          ]
        }
      }
      ''');
      final topics = parseSuperTopicSearch(root);
      expect(topics.length, 1);
      expect(topics.single.avatar, 'https://wx1.sinaimg.cn/thumb/fl.jpg');
    });
  });

  group('最近访问超话持久化', () {
    const cid1 = '1008080123456789abcdef0123456789abcdef';
    const cid2 = '100808fedcba9876543210fedcba9876543210';

    test('写入去重、按最近访问置顶与删除清空', () async {
      final dir = await Directory.systemTemp.createTemp('hobo_st_test_');
      try {
        final store = await Store.open(dir);
        expect(store.recentSuperTopics(), isEmpty);

        store.addRecentSuperTopic(
          const SuperTopicSummary(containerId: cid1, title: '超话一'),
        );
        store.addRecentSuperTopic(
          const SuperTopicSummary(containerId: cid2, title: '超话二'),
        );
        // 再访问一次 cid1 应置顶且不重复。
        store.addRecentSuperTopic(
          const SuperTopicSummary(containerId: cid1, title: '超话一更新'),
        );

        final recent = store.recentSuperTopics();
        expect(recent.length, 2);
        expect(recent[0].containerId, cid1);
        expect(recent[0].title, '超话一更新');
        expect(recent[1].containerId, cid2);

        store.removeRecentSuperTopic(cid1);
        expect(store.recentSuperTopics().map((e) => e.containerId), [cid2]);

        store.clearRecentSuperTopics();
        expect(store.recentSuperTopics(), isEmpty);
      } finally {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });
  });

  group('超话签到解析、按日记录与按钮交互', () {
    const cid1 = '100808290e0c067e6f5bb50adbd51088424f68';
    const cid2 = '10080871065004afbba7063823f8b6c51f1edb';

    test('解析 followsuper 卡片中的签到 / 已签按钮状态', () {
      final root = _json('''
      {
        "ok": 1,
        "data": {
          "cards": [
            {
              "card_type": 11,
              "card_group": [
                {
                  "card_type": "8",
                  "title_sub": "明末渊虚之羽",
                  "scheme": "https://m.weibo.cn/p/index?containerid=$cid2",
                  "desc1": "等级 LV.1",
                  "buttons": [
                    {
                      "type": "default",
                      "name": "签到",
                      "scheme": "/api/container/button?sign=1838be&request_url=http%3A%2F%2Fi.chaohua.weibo.com%2Fmobile%2Fshproxy%2Factive_fcheckin"
                    }
                  ]
                },
                {
                  "card_type": "8",
                  "title_sub": "国行switch",
                  "scheme": "https://m.weibo.cn/p/index?containerid=$cid1",
                  "desc1": "等级 LV.2",
                  "buttons": [
                    {
                      "type": "link",
                      "name": "已签",
                      "scheme": false
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
      ''');

      final page = parseSuperTopicList(root);
      expect(page.items.length, 2);
      expect(page.items[0].containerId, cid2);
      expect(page.items[0].checkedIn, isFalse);
      expect(page.items[1].containerId, cid1);
      expect(page.items[1].checkedIn, isTrue);
    });

    test('解析超话详情 pageInfo 中的关注态、粉丝等级与签到进度', () {
      final root = _json('''
      {
        "ok": 1,
        "data": {
          "pageInfo": {
            "containerid": "${cid1}_-_feed",
            "page_title": "国行switch",
            "follow_relation": 1,
            "desc": "国行真香",
            "desc_more": [
              "阅读6524.7万　帖子6533　粉丝4.5万",
              "等级LV.1初级粉丝　连续签到0天 >>"
            ]
          },
          "cards": []
        }
      }
      ''');

      final page = parseSuperTopicPage(root, cid1);
      expect(page.info.following, isTrue);
      expect(page.info.description, '国行真香');
      expect(page.info.levelText, '等级LV.1初级粉丝');
      expect(page.info.checkInText, '连续签到0天');
      expect(page.info.checkedIn, isFalse);

      // 无自定义简介时，微博会把 desc_more 拼回 desc，应去重置空。
      final dupDesc = parseSuperTopicPage(
        _json('''
        {
          "ok": 1,
          "data": {
            "pageInfo": {
              "containerid": "${cid2}_-_feed",
              "page_title": "西瓜酱G",
              "follow_relation": 1,
              "desc": "阅读1198.9万　帖子200　粉丝2.4万 等级LV.2中级粉丝　连续签到1天 >>",
              "desc_more": [
                "阅读1198.9万　帖子200　粉丝2.4万",
                "等级LV.2中级粉丝　连续签到1天 >>"
              ]
            },
            "cards": []
          }
        }
        '''),
        cid2,
      );
      expect(dupDesc.info.description, isEmpty);
      expect(dupDesc.info.levelText, '等级LV.2中级粉丝');
      expect(dupDesc.info.checkInText, '连续签到1天');
    });

    test('解析签到接口：成功、当日已签与业务失败', () {
      final ok = parseSuperTopicCheckIn(
        _json('''
        {
          "code": "100000",
          "msg": "已签到",
          "data": {
            "tipMessage": "今日签到，经验值+4",
            "alert_title": "今日签到 第28名",
            "alert_subtitle": "经验值+4"
          }
        }
        '''),
        cid1,
      );
      expect(ok.alreadyCheckedIn, isFalse);
      expect(ok.message, '今日签到 第28名 · 经验值+4');

      final dup = parseSuperTopicCheckIn(
        _json('{"code":"382004","msg":"今天已签到(382004)"}'),
        cid1,
      );
      expect(dup.alreadyCheckedIn, isTrue);
      expect(dup.message, '今天已签到');

      expect(
        () => parseSuperTopicCheckIn(
          _json('{"code":"382010","msg":"请先关注该超话"}'),
          cid1,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', '请先关注该超话')
              .having((e) => e.errno, 'errno', '382010'),
        ),
      );
    });

    test('北京时间日期键在 UTC 16:00 跨日', () {
      expect(beijingDateKey(DateTime.utc(2026, 11, 28, 15, 59, 59)), '2026-11-28');
      expect(beijingDateKey(DateTime.utc(2026, 11, 28, 16, 0, 0)), '2026-11-29');
    });

    test('Store 按账号与日期隔离保存超话当日签到记录', () async {
      final dir = await Directory.systemTemp.createTemp('hobo_st_checkin_');
      try {
        final store = await Store.open(dir);
        store.markSuperTopicsCheckedIn('1001', [cid1], '2026-11-28');
        expect(store.checkedInSuperTopics('1001', '2026-11-28'), {cid1});
        expect(store.checkedInSuperTopics('1002', '2026-11-28'), isEmpty);
        expect(store.checkedInSuperTopics('1001', '2026-11-29'), isEmpty);

        // 次日写入应清掉前一天残留。
        store.markSuperTopicsCheckedIn('1001', [cid2], '2026-11-29');
        expect(store.checkedInSuperTopics('1001', '2026-11-29'), {cid2});
        expect(store.checkedInSuperTopics('1001', '2026-11-28'), isEmpty);
      } finally {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    testWidgets('卡片内点击签到或已签不会误触发外层卡片跳转', (tester) async {
      var cardTaps = 0;
      var checkInTaps = 0;

      Widget wrap(Widget child) => PrismApp(
        theme: hoboTheme(brightness: Brightness.light, accentArgb: 0xFF1DE9B6),
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: child),
        ),
      );

      await tester.pumpWidget(
        wrap(
          HoboCard(
            onPressed: () => cardTaps++,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('测试超话'),
                const SizedBox(width: 12),
                SuperTopicCheckInButton(
                  checkedIn: false,
                  loading: false,
                  compact: true,
                  onPressed: () => checkInTaps++,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('签到'));
      await tester.pumpAndSettle();
      expect(checkInTaps, 1);
      expect(cardTaps, 0);

      await tester.pumpWidget(
        wrap(
          HoboCard(
            onPressed: () => cardTaps++,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('测试超话'),
                const SizedBox(width: 12),
                SuperTopicCheckInButton(
                  checkedIn: true,
                  loading: false,
                  compact: true,
                  onPressed: () => checkInTaps++,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('已签'));
      await tester.pumpAndSettle();
      expect(checkInTaps, 1);
      expect(cardTaps, 0);
    });

    testWidgets('HoboRemovableChip 点标签文字触发重新搜索，点关闭键才删除', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var pressed = 0;
        var deleted = 0;

        await tester.pumpWidget(
          PrismApp(
            theme: hoboTheme(brightness: Brightness.light, accentArgb: 0xFF1DE9B6),
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: HoboRemovableChip(
                  label: '明末渊虚之羽',
                  onPressed: () => pressed++,
                  onDeleted: () => deleted++,
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('明末渊虚之羽'));
        await tester.pumpAndSettle();
        expect(pressed, 1);
        expect(deleted, 0);

        await tester.tap(find.bySemanticsLabel('删除明末渊虚之羽'));
        await tester.pumpAndSettle();
        expect(pressed, 1);
        expect(deleted, 1);
      } finally {
        semantics.dispose();
      }
    });
  });
}
