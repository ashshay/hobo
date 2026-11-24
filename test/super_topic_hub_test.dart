import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/store.dart';
import 'package:hobo/data/super_topic.dart';
import 'package:hobo/data/super_topic_id.dart';

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
}
