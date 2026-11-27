import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/data/models.dart';
import 'package:hobo/ui/widgets/capsule.dart';
import 'package:hobo/ui/widgets/pager.dart';
import 'package:hobo/ui/widgets/profile_tabs.dart';

class _ProfileTabBarHost extends StatefulWidget {
  const _ProfileTabBarHost({
    required this.width,
    required this.weiboCount,
    required this.onReady,
  });

  final double width;
  final int weiboCount;
  final ValueChanged<_ProfileTabBarHostState> onReady;

  @override
  State<_ProfileTabBarHost> createState() => _ProfileTabBarHostState();
}

class _ProfileTabBarHostState extends State<_ProfileTabBarHost>
    with TickerProviderStateMixin {
  ProfileTab selected = ProfileTab.weibo;
  late final HoboPagerController controller = HoboPagerController(
    vsync: this,
    initialPage: selected.index,
    count: ProfileTab.values.length,
  );
  final List<ProfileTab> changes = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onReady(this));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: Size(widget.width, 800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: widget.width,
            child: ProfileTabBar(
              selected: selected,
              weiboCount: widget.weiboCount,
              pageController: controller,
              onSelect: (tab) => setState(() {
                selected = tab;
                changes.add(tab);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_ProfileTabBarHostState> _pumpTabBar(
  WidgetTester tester, {
  double width = 393,
  int weiboCount = 9499,
}) async {
  late _ProfileTabBarHostState host;
  await tester.pumpWidget(
    _ProfileTabBarHost(
      width: width,
      weiboCount: weiboCount,
      onReady: (state) => host = state,
    ),
  );
  await tester.pump();
  return host;
}

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

  group('ProfileTabBar 胶囊分类条', () {
    testWidgets('展示五类胶囊并带微博数，点击可弹簧切换', (tester) async {
      final host = await _pumpTabBar(tester, width: 393, weiboCount: 9499);
      expect(find.byType(HoboCapsule<ProfileTab>), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);
      expect(find.text('微博(9499)'), findsOneWidget);
      expect(find.text('相册'), findsOneWidget);
      expect(find.text('精选'), findsOneWidget);
      expect(find.text('视频'), findsOneWidget);
      expect(host.controller.page, closeTo(1, 0.01));

      await tester.tap(find.text('相册'));
      await tester.pumpAndSettle();

      expect(host.selected, ProfileTab.album);
      expect(host.changes, [ProfileTab.album]);
      expect(host.controller.page, closeTo(ProfileTab.album.index, 0.01));
    });

    testWidgets('常规屏宽下可直接按住胶囊滑块拖拽切换分类', (tester) async {
      final host = await _pumpTabBar(tester, width: 393, weiboCount: 9499);
      final start = tester.getCenter(find.text('微博(9499)'));
      final end = tester.getCenter(find.text('相册'));

      final gesture = await tester.startGesture(start);
      // 超过 kTouchSlop (18px) 触发拖拽，再滑向相邻分段验证实时跟手。
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(Offset(end.dx - start.dx, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      expect(host.controller.isDragging, isTrue);
      expect(host.controller.page, greaterThan(1.5));

      await gesture.up();
      await tester.pumpAndSettle();

      expect(host.selected.index, greaterThan(ProfileTab.weibo.index));
      expect(host.controller.page, closeTo(host.selected.index, 0.01));
    });

    testWidgets('窄屏超出宽度时自动切换为可横向滚动且无溢出异常', (tester) async {
      await _pumpTabBar(tester, width: 260, weiboCount: 106000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('微博(10.6万)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HoboCapsule<ProfileTab>),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );

      await tester.drag(
        find.byType(HoboCapsule<ProfileTab>),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
