import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/ui/widgets/profile_tabs.dart';

Status status(
  String id, {
  List<Pic> pics = const [],
  VideoInfo? video,
  Status? retweeted,
}) {
  return Status(
    id: id,
    mid: id,
    textHtml: '第 $id 条',
    createdAt: '',
    source: '',
    pics: pics,
    video: video,
    retweeted: retweeted,
  );
}

void main() {
  group('相册照片', () {
    test('pid / mid / 月份一起解析', () {
      final photo = AlbumPhoto.from({
        'pid': '001Lvb9ugy1ijeqvz4uw9j615e0nu7ey02',
        'mid': '5369249474548059',
        'type': 'PIC',
        'timeline_year': '2026',
        'timeline_month': '11',
      });
      expect(photo, isNotNull);
      expect(photo!.pid, '001Lvb9ugy1ijeqvz4uw9j615e0nu7ey02');
      expect(photo.mid, '5369249474548059');
      expect(photo.type, 'pic');
      expect(photo.year, 2026);
      expect(photo.month, 11);
    });

    test('没有 pid 的照片直接丢掉', () {
      expect(AlbumPhoto.from({'mid': '1', 'type': 'pic'}), isNull);
      expect(AlbumPhoto.from(null), isNull);
    });

    test('缩略图与原图地址按 pid 拼', () {
      const photo = AlbumPhoto(pid: 'abc');
      expect(photo.thumb, 'https://wx1.sinaimg.cn/orj360/abc.jpg');
      expect(photo.large, 'https://wx1.sinaimg.cn/large/abc.jpg');
      expect(photo.toPic().large, photo.large);
    });

    test('视频封面认 type', () {
      const photo = AlbumPhoto(pid: 'abc', type: 'video');
      expect(photo.isVideo, isTrue);
    });
  });

  group('相册按月分组', () {
    test('月份标记只出现一次，后面的空串归到当前月', () {
      final sections = groupAlbumPhotos(const [
        AlbumPhoto(pid: '1', year: 2026, month: 11),
        AlbumPhoto(pid: '2'),
        AlbumPhoto(pid: '3'),
        AlbumPhoto(pid: '4', year: 2026, month: 10),
        AlbumPhoto(pid: '5'),
      ]);
      expect(sections.map((section) => section.title), [
        '2026年11月',
        '2026年10月',
      ]);
      expect(sections[0].photos.map((photo) => photo.pid), ['1', '2', '3']);
      expect(sections[1].photos.map((photo) => photo.pid), ['4', '5']);
    });

    test('开头就没有月份时归到「更早」', () {
      final sections = groupAlbumPhotos(const [
        AlbumPhoto(pid: '1'),
        AlbumPhoto(pid: '2'),
      ]);
      expect(sections.single.title, '更早');
      expect(sections.single.photos.length, 2);
    });

    test('空列表不分段', () {
      expect(groupAlbumPhotos(const []), isEmpty);
    });
  });

  group('微博筛选', () {
    final pic = Pic(thumb: 'https://img/thumb.jpg', large: 'https://img/l.jpg');
    final video = VideoInfo(title: '', cover: '', url: 'https://video/1.mp4');
    final plain = status('plain');
    final original = status('original', pics: [pic]);
    final withVideo = status('video', video: video);
    final repost = status('repost', retweeted: status('quoted', pics: [pic]));
    final items = [plain, original, withVideo, repost];

    test('全部保留', () {
      expect(ProfileFilter.all.apply(items).length, 4);
    });

    test('原创去掉转发', () {
      expect(ProfileFilter.original.apply(items).map((item) => item.id), [
        'plain',
        'original',
        'video',
      ]);
    });

    test('图片看正文或转发的原博', () {
      expect(ProfileFilter.image.apply(items).map((item) => item.id), [
        'original',
        'repost',
      ]);
    });

    test('视频看正文或转发的原博', () {
      expect(ProfileFilter.video.apply(items).map((item) => item.id), [
        'video',
      ]);
      expect(
        ProfileFilter.video.apply([
          status('r', retweeted: status('v', video: video)),
        ]).length,
        1,
      );
    });
  });

  test('User 解析认证说明', () {
    final user = User.from({
      'id': '1',
      'screen_name': '小明',
      'verified_reason': '微博2022最具影响力互联网科技大V',
    });
    expect(user?.verifiedReason, '微博2022最具影响力互联网科技大V');
  });
}
