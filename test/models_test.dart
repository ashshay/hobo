import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/cookie_vault.dart';
import 'package:hobo/data/html_text.dart';
import 'package:hobo/data/links.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/data/super_topic_id.dart';

Map<String, dynamic> json(String text) {
  final decoded = jsonDecode(text);
  return {for (final e in (decoded as Map).entries) e.key.toString(): e.value};
}

void main() {
  group('卡片解析', () {
    test('mblog 与转发都解析，推广博被丢掉', () {
      final root = json('''
      {
        "ok": 1,
        "data": {
          "cardlistInfo": {"since_id": "123"},
          "cards": [
            {"card_type": 9, "mblog": {
              "id": "5001", "mid": "5001", "created_at": "Mon Nov 17 10:23:45 +0800 2025",
              "text": "<a href=\\"https://m.weibo.cn/u/1\\">@小明</a> 你好 #话题# <img alt=\\"[可爱]\\" src=\\"https://img.example/emoji.png\\">",
              "source": "<a>iPhone</a>",
              "user": {"id": "1", "screen_name": "小明", "avatar_large": "https://a.example/1.jpg", "verified": true,
                       "followers_count": "72.3万", "follow_count": 12, "statuses_count": 34},
              "pics": [{"url": "https://wx1.sinaimg.cn/orj360/a.jpg"}],
              "reposts_count": 2, "comments_count": 3, "attitudes_count": 4,
              "retweeted_status": {"id": "4001", "text": "原文", "user": {"id": "2", "screen_name": "小红"}}
            }},
            {"card_type": 9, "mblog": {"id": "5002", "text": "广告", "mark": "999_reallog_mark_ad:999|WeiboAD"}}
          ]
        }
      }
      ''');
      final page = parseCards(root);
      expect(page.items.length, 1);
      expect(page.items.first.id, '5001');
      expect(page.items.first.user?.name, '小明');
      expect(page.items.first.user?.followers, 723000);
      expect(page.items.first.user?.verified, true);
      expect(page.items.first.pics.length, 1);
      expect(page.items.first.retweeted?.id, '4001');
      expect(page.items.first.source, 'iPhone');
      expect(page.items.first.mid, '5001');
      expect(page.sinceId, '123');
    });

    test('pic_ids + pic_infos 兜底、视频与投票识别', () {
      final status = Status.from(json('''
      {
        "id": "6001",
        "text": "看视频 vote_id=abc123",
        "user": {"id": "3", "screen_name": "阿强"},
        "pic_ids": ["pid1"],
        "page_info": {"type": "video", "page_title": "v", "media_info": {"stream_url_hd": "https://video.example/v.mp4"},
                      "page_pic": {"url": "https://cover.example/c.jpg"}}
      }
      '''));
      expect(status, isNotNull);
      expect(status!.pics.single.large, 'https://wx1.sinaimg.cn/large/pid1.jpg');
      expect(status.video?.url, 'https://video.example/v.mp4');
      expect(status.isVote, true);
      expect(status.voteId, 'abc123');
    });

    test('热搜广告位被跳过，排名顺延', () {
      final hot = parseHotItems(json('''
      {"data": {"cards": [{"card_group": [
        {"desc": "第一条", "card_type_name": "热"},
        {"desc": "广告位", "itemid": "is_ad_pos:1|adid:9"},
        {"desc": "第二条"}
      ]}]}}
      '''));
      expect(hot.length, 2);
      expect(hot[0].rank, 1);
      expect(hot[1].title, '第二条');
      expect(hot[1].rank, 2);
    });
  });

  group('富文本', () {
    test('链接、表情与实体都还原', () {
      final segments = parseWeiboHtml(
        '<a href="https://m.weibo.cn/u/1">@小明</a> 你好&amp;#10;'
        '<img alt="[可爱]" src="https://img.example/e.png">',
      );
      expect(segments.first, isA<WeiboLinkSegment>());
      expect((segments.first as WeiboLinkSegment).text, '@小明');
      final emoji = segments.whereType<WeiboEmojiSegment>().single;
      expect(emoji.alt, '[可爱]');
      expect(emoji.url, 'https://img.example/e.png');
      expect(
        stripHtml('<p>a</p><p>b<br>c</p>'),
        'a\nb\nc',
      );
    });

    test('链接归一化与超话身份', () {
      expect(resolveWeiboLink('/status/123'), 'https://m.weibo.cn/status/123');
      expect(
        resolveWeiboLink('sinaweibo://detail?mblogid=456'),
        'https://m.weibo.cn/detail/456',
      );
      expect(weiboStatusId('https://m.weibo.cn/detail/789'), '789');
      expect(weiboUserId('https://m.weibo.cn/u/42'), '42');
      expect(weiboMentionName('https://m.weibo.cn/n/%E5%B0%8F%E6%98%8E'), '小明');
      expect(
        superTopicId(
          'https://m.weibo.cn/p/index?containerid=1008080123456789abcdef0123456789abcdef',
        ),
        '1008080123456789abcdef0123456789abcdef',
      );
      expect(superTopicId('https://m.weibo.cn/search?containerid=100103type%3D1'), isNull);
      expect(
        normalizedSuperTopicId('1008080123456789abcdef0123456789abcdef_-_feed'),
        '1008080123456789abcdef0123456789abcdef',
      );
    });

    test('「查看图片」链接解出图片直链', () {
      // 真实数据：正文里的「查看图片」是 sinaurl 包着的 sinaimg 直链，
      // 这条微博自己的 pic_ids 是空的，所以必须用链接指向的那张图。
      const href =
          'https://weibo.cn/sinaurl?u=https%3A%2F%2Fwx3.sinaimg.cn%2Flarge%2F'
          '005F1trVly1ij8dip16lcj30u618pkdz.jpg';
      final resolved = unwrapSinaUrl(href);
      expect(
        resolved,
        'https://wx3.sinaimg.cn/large/005F1trVly1ij8dip16lcj30u618pkdz.jpg',
      );
      expect(isImageLink(resolved!), true);
      expect(isImageLink(href), false);
    });

    test('评论配图走 pic_ids + pic_infos', () {
      final comment = Comment.from(
        json('''
      {
        "id": "c1",
        "text": "看图",
        "user": {"id": "9", "screen_name": "评论者"},
        "pic_ids": ["pid9"],
        "pic_infos": {
          "pid9": {
            "thumbnail": {"url": "https://wx1.sinaimg.cn/thumbnail/pid9.jpg"},
            "large": {"url": "https://wx1.sinaimg.cn/large/pid9.jpg",
                      "geo": {"width": 1200, "height": 900}}
          }
        }
      }
      '''),
      );
      expect(comment, isNotNull);
      expect(comment!.pics.length, 1);
      expect(comment.pics.first.large, 'https://wx1.sinaimg.cn/large/pid9.jpg');
      expect(comment.pics.first.width, 1200);
      expect(comment.pics.first.height, 900);
      // 没有图的评论不能凭空多出东西。
      final plain = Comment.from(json('{"id": "c2", "text": "只有字"}'));
      expect(plain!.pics, isEmpty);
    });

    test('时间格式化', () {
      final now = DateTime.now();
      final recent = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ).subtract(const Duration(minutes: 5));
      final raw =
          '${_weekday(recent)} ${_month(recent)} ${recent.day.toString().padLeft(2, '0')} '
          '${recent.hour.toString().padLeft(2, '0')}:${recent.minute.toString().padLeft(2, '0')}:00 '
          '+0800 ${recent.year}';
      expect(formatWeiboTime(raw), contains('分钟前'));
      expect(formatWeiboTime(''), '');
      expect(formatWeiboTime('随便什么'), '随便什么');
    });
  });

  group('时间与视频', () {
    test('相对时间换算成绝对时间戳', () {
      final millis = weiboTimeMillis('1小时前');
      expect(millis, isNotNull);
      final diff = DateTime.now().millisecondsSinceEpoch - millis!;
      expect(diff, inInclusiveRange(3590000, 3610000));
      expect(weiboTimeMillis('刚刚'), isNotNull);
      expect(weiboTimeMillis('今天 10:23'), isNotNull);
      expect(weiboTimeMillis('11-19 10:23'), isNotNull);
      expect(weiboTimeMillis('2025-11-19 10:23'), isNotNull);
      // 超话视频卡片把时长放在 created_at 里，不能被当成时间。
      expect(weiboTimeMillis('01:23'), isNull);
      expect(weiboTimeMillis('随便什么'), isNull);
    });

    test('相对时间串解析后不再原样显示', () {
      final normalized = normalizeWeiboTime('1小时前');
      expect(int.tryParse(normalized), isNotNull);
      expect(formatWeiboTime(normalized), contains('小时前'));
      // 凌晨跑时「1小时前」会落到昨天，这时带日期也是对的。
      expect(
        formatWeiboTimeExact(normalized),
        matches(RegExp(r'^(\d{2}:\d{2}|\d{2}-\d{2} \d{2}:\d{2})$')),
      );
      expect(isRelativeWeiboTime(normalized), true);
      expect(formatWeiboTime('01:23'), '01:23');
    });

    test('视频多清晰度按分辨率从高到低', () {
      final status = Status.from(
        json('''
      {
        "id": "7001",
        "text": "视频",
        "page_info": {
          "type": "video",
          "page_title": "v",
          "media_info": {
            "stream_url_hd": "https://video.example/hd.mp4",
            "stream_url": "https://video.example/sd.mp4",
            "playback_list": [
              {"play_info": {"url": "https://video.example/1080.mp4", "label": "超清 1080P",
                             "width": 1920, "height": 1080, "size": 10485760}},
              {"play_info": {"url": "https://video.example/720.mp4", "label": "高清 720P",
                             "width": 1280, "height": 720}}
            ]
          }
        }
      }
      '''),
      );
      expect(status, isNotNull);
      final video = status!.video!;
      expect(video.qualities.first.label, '超清 1080P');
      expect(video.qualities.first.height, 1080);
      expect(
        video.qualities.map((quality) => quality.url),
        contains('https://video.example/sd.mp4'),
      );
      expect(video.current?.url, 'https://video.example/hd.mp4');
    });
  });

  group('Cookie 表', () {
    test('Set-Cookie 按域名合并，同名覆盖，空值删除', () {
      var table = CookieVault.seed('SUB=abc; SUBP=def');
      expect(CookieVault.header(table, 'm.weibo.cn'), 'SUB=abc; SUBP=def');
      table = CookieVault.absorb(
        table,
        Uri.parse('https://m.weibo.cn/api/config'),
        ['SUB=new; Domain=.weibo.cn; Path=/', '_T_WM=t1'],
      );
      expect(CookieVault.header(table, 'm.weibo.cn'), contains('_T_WM=t1'));
      expect(table['.weibo.cn'], contains('SUB=new'));
      expect(table['.m.weibo.cn'], contains('_T_WM=t1'));
      table = CookieVault.absorb(
        table,
        Uri.parse('https://weibo.com/'),
        ['XSRF-TOKEN=x; Domain=.weibo.com; Path=/'],
      );
      expect(CookieVault.desktopAuthHeader(table, 'weibo.com'), contains('XSRF-TOKEN=x'));
      expect(CookieVault.authHeader(table, 'm.weibo.cn'), contains('SUB=new'));
      table = CookieVault.absorb(
        table,
        Uri.parse('https://m.weibo.cn/api/config'),
        ['SUB=; Domain=.weibo.cn; Max-Age=0'],
      );
      expect(CookieVault.header(table, 'm.weibo.cn'), isNot(contains('SUB=')));
    });
  });

  group('评论配图', () {
    // 真实样本：m.weibo.cn/comments/hotflow 的图片评论。
    // 关键点是 `pics` 里只有一条视频占位（url 是 `&690`，请求 404），
    // 真正的图在 `pic` 里。以前优先读 `pics` 就永远拿到那个 404 地址。
    const imageComment = '''
    {
      "id": "5367005964402716",
      "text": "原曲原唱还蛮好听的",
      "pic": {
        "pid": "0092j2IYgy1ij7ljfblb3j30j60tr7e4",
        "url": "https://wx1.sinaimg.cn/orj360/0092j2IYgy1ij7ljfblb3j30j60tr7e4.jpg",
        "size": "orj360",
        "geo": {"width": 360, "height": 558, "croped": false},
        "large": {
          "size": "large",
          "url": "https://wx1.sinaimg.cn/large/0092j2IYgy1ij7ljfblb3j30j60tr7e4.jpg",
          "geo": {"width": "690", "height": "1071", "croped": false}
        }
      },
      "pics": [{
        "pid": null,
        "url": "https://ss1.sinaimg.cn/orj360/&690",
        "size": "orj360",
        "geo": false,
        "large": {"size": "large", "url": "https://ss1.sinaimg.cn/large/&690", "geo": false},
        "duration": 0,
        "type": "video"
      }]
    }
    ''';

    test('图片评论走 pic 字段，跳过 pics 里的视频占位', () {
      final comment = Comment.from(json(imageComment));
      expect(comment, isNotNull);
      expect(comment!.pics.length, 1);
      final pic = comment.pics.first;
      expect(pic.thumb, contains('0092j2IYgy1ij7ljfblb3j30j60tr7e4'));
      expect(pic.large, contains('/large/'));
      expect(pic.thumb, isNot(contains('&690')));
      expect(pic.large, isNot(contains('&690')));
      // 尺寸取 large.geo（字符串数字也要能读）。
      expect(pic.width, 690);
      expect(pic.height, 1071);
    });

    test('只有视频占位时不产出图片', () {
      final comment = Comment.from(json('''
      {
        "id": "1",
        "text": "纯视频评论",
        "pics": [{
          "pid": null,
          "url": "https://ss1.sinaimg.cn/orj360/&690",
          "large": {"url": "https://ss1.sinaimg.cn/large/&690"},
          "type": "video"
        }]
      }
      '''));
      expect(comment!.pics, isEmpty);
    });

    test('pic 与 pics 指向同一张图时只留一张', () {
      final comment = Comment.from(json('''
      {
        "id": "2",
        "text": "重复",
        "pic": {
          "url": "https://wx1.sinaimg.cn/orj360/abc.jpg",
          "large": {"url": "https://wx1.sinaimg.cn/large/abc.jpg"}
        },
        "pics": [{
          "url": "https://wx1.sinaimg.cn/orj360/abc.jpg",
          "large": {"url": "https://wx1.sinaimg.cn/large/abc.jpg"}
        }]
      }
      '''));
      expect(comment!.pics.length, 1);
    });

    test('正文的 pics 数组照常解析', () {
      final pics = picsOf(json('''
      {
        "pics": [
          {"url": "https://wx1.sinaimg.cn/orj360/a.jpg", "large": {"url": "https://wx1.sinaimg.cn/large/a.jpg"}},
          {"url": "https://wx1.sinaimg.cn/orj360/b.jpg", "large": {"url": "https://wx1.sinaimg.cn/large/b.jpg"}}
        ]
      }
      '''));
      expect(pics.length, 2);
      expect(pics[0].large, contains('/large/a.jpg'));
      expect(pics[1].large, contains('/large/b.jpg'));
    });

    test('pic_ids + pic_infos 缺项时按 id 拼地址', () {
      final pics = picsOf(json('''
      {
        "pic_ids": ["abc", "def"],
        "pic_infos": {
          "abc": {"url": "https://wx1.sinaimg.cn/orj360/abc.jpg", "large": {"url": "https://wx1.sinaimg.cn/large/abc.jpg"}}
        }
      }
      '''));
      expect(pics.length, 2);
      expect(pics[0].large, contains('/large/abc.jpg'));
      expect(pics[1].large, 'https://wx1.sinaimg.cn/large/def.jpg');
    });
  });
}

String _weekday(DateTime date) => const [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
][date.weekday - 1];

String _month(DateTime date) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][date.month - 1];
