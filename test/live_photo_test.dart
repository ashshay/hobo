import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/media_saver.dart';
import 'package:hobo/data/models.dart';

Map<String, dynamic> _json(String text) {
  final decoded = jsonDecode(text);
  return {for (final e in (decoded as Map).entries) e.key.toString(): e.value};
}

void main() {
  group('实况图解析与序列化', () {
    test('m.weibo.cn 实况图保留播放页地址，静图与 GIF 不误判', () {
      final status = Status.from(_json('''
      {
        "id": "100",
        "text": "实况测试",
        "pics": [
          {
            "url": "https://wx1.sinaimg.cn/orj360/a.jpg",
            "type": "livephoto",
            "videoSrc": "https://video.weibo.com/media/play?livephoto=https%3A%2F%2Flivephoto.us.sinaimg.cn%2Fa.mov",
            "large": {"url": "https://wx1.sinaimg.cn/large/a.jpg", "geo": {"width": 2048, "height": 1536}}
          },
          {
            "url": "https://wx1.sinaimg.cn/orj360/b.jpg",
            "large": {"url": "https://wx1.sinaimg.cn/large/b.jpg"}
          }
        ]
      }
      '''))!;

      expect(status.pics.length, 2);
      expect(status.pics[0].isLive, isTrue);
      expect(
        status.pics[0].live,
        'https://video.weibo.com/media/play?livephoto=https%3A%2F%2Flivephoto.us.sinaimg.cn%2Fa.mov',
      );
      expect(status.pics[0].width, 2048);
      expect(status.pics[0].height, 1536);
      expect(status.pics[1].isLive, isFalse);

      // 本地收藏 JSON 往返后仍保留实况信息。
      final roundTrip = Status.from(status.toJson())!;
      expect(roundTrip.pics[0].isLive, isTrue);
      expect(roundTrip.pics[0].live, status.pics[0].live);
    });

    test('weibo.com pic_infos 裸 mov 补齐播放页包装，GIF 保持静图', () {
      final status = Status.from(_json('''
      {
        "id": "101",
        "text": "pic_infos",
        "pic_ids": ["live1", "gif1"],
        "pic_infos": {
          "live1": {
            "type": "livephoto",
            "video": "//livephoto.us.sinaimg.cn/c.mov",
            "bmiddle": {"url": "https://wx1.sinaimg.cn/bmiddle/c.jpg"},
            "original": {"url": "https://wx1.sinaimg.cn/large/c.jpg"}
          },
          "gif1": {
            "type": "gif",
            "video": "https://wx1.sinaimg.cn/large/d.mp4",
            "largest": {"url": "https://wx1.sinaimg.cn/large/d.gif"}
          }
        }
      }
      '''))!;

      expect(status.pics.length, 2);
      expect(status.pics[0].isLive, isTrue);
      expect(
        status.pics[0].live,
        'https://video.weibo.com/media/play?livephoto=https%3A%2F%2Flivephoto.us.sinaimg.cn%2Fc.mov',
      );
      expect(status.pics[0].large, 'https://wx1.sinaimg.cn/large/c.jpg');
      expect(status.pics[0].thumb, 'https://wx1.sinaimg.cn/bmiddle/c.jpg');
      expect(status.pics[1].isLive, isFalse);
    });

    test('已签名 mov 地址原样保留，不二次包装', () {
      const signed =
          'https://livephoto.us.sinaimg.cn/f.mov?Expires=1&ssig=abc&KID=unistore,video';
      expect(livePlayUrl(signed), signed);
    });
  });

  group('实况视频校验与解包', () {
    test('识别 MP4 / QuickTime 容器头，拒绝 HTML 报错页', () {
      final mp4Header = [0, 0, 0, 24, ...'ftypisom'.codeUnits];
      final movHeader = [0, 0, 0, 20, ...'ftypqt  '.codeUnits];
      final htmlHeader = '<!DOCTYPE html>'.codeUnits;

      expect(MediaSaver.isValidVideoHeaderBytes(mp4Header), isTrue);
      expect(MediaSaver.isValidVideoHeaderBytes(movHeader), isTrue);
      expect(MediaSaver.isValidVideoHeaderBytes(htmlHeader), isFalse);
      expect(MediaSaver.isValidVideoHeaderBytes([1, 2, 3]), isFalse);
    });

    test('从播放页参数解出内部 mov 直链', () {
      expect(
        MediaSaver.unwrapLivePhotoParam(
          'https://video.weibo.com/media/play?livephoto=https%3A%2F%2Flivephoto.us.sinaimg.cn%2Fx.mov',
        ),
        'https://livephoto.us.sinaimg.cn/x.mov',
      );
      expect(
        MediaSaver.unwrapLivePhotoParam('https://livephoto.us.sinaimg.cn/x.mov'),
        isNull,
      );
    });
  });
}
