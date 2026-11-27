import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/ui/widgets/capsule.dart';
import 'package:hobo/ui/widgets/pager.dart';

const _segments = <(int, String)>[(0, '关注'), (1, '推荐'), (2, '好友圈')];

/// 800×600 画布中央一块 320×44 的胶囊：轨道 244–556，每格 104。
class _CapsuleHost extends StatefulWidget {
  const _CapsuleHost({required this.onReady, this.disableAnimations = false});

  final ValueChanged<_CapsuleHostState> onReady;
  final bool disableAnimations;

  @override
  State<_CapsuleHost> createState() => _CapsuleHostState();
}

class _CapsuleHostState extends State<_CapsuleHost>
    with TickerProviderStateMixin {
  late final HoboPagerController controller = HoboPagerController(
    vsync: this,
    count: _segments.length,
  );
  int value = 0;
  final List<int> changes = [];

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
      data: MediaQueryData(
        size: const Size(800, 600),
        disableAnimations: widget.disableAnimations,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 44,
            child: HoboCapsule<int>(
              segments: _segments,
              value: value,
              pageController: controller,
              onChanged: (next) => setState(() {
                value = next;
                changes.add(next);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_CapsuleHostState> _pumpHost(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  late _CapsuleHostState host;
  await tester.pumpWidget(
    _CapsuleHost(
      disableAnimations: disableAnimations,
      onReady: (state) => host = state,
    ),
  );
  await tester.pump();
  return host;
}

void main() {
  group('HoboCapsule', () {
    testWidgets('点第二格：回调选中项，滑块弹簧过去', (tester) async {
      final host = await _pumpHost(tester);
      expect(host.controller.page, 0);

      // 轨道 244–556，每格 104：第二格中心 ≈ 400。
      await tester.tapAt(const Offset(402, 300));
      await tester.pump();
      expect(host.changes, [1]);
      expect(host.value, 1);

      await tester.pumpAndSettle();
      expect(host.controller.page, closeTo(1, 0.01));
    });

    testWidgets('按住滑块拖：滑块跟着手指走，松手落到附近的格子', (tester) async {
      final host = await _pumpHost(tester);

      final gesture = await tester.startGesture(const Offset(290, 300));
      // 第一下只够触发拖拽识别，位移从第二下开始算。
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 80));

      // 跟手：手指已经从第一格滑到第二格，滑块得跟过去。
      expect(host.controller.page, greaterThan(0.8));
      expect(host.controller.isDragging, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(host.changes, isNotEmpty);
      expect(host.controller.page, greaterThan(0));
      expect(host.controller.page, lessThanOrEqualTo(2));
    });

    testWidgets('系统关闭动画时点胶囊直接落位', (tester) async {
      final host = await _pumpHost(tester, disableAnimations: true);
      await tester.tapAt(const Offset(402, 300));
      await tester.pump();

      expect(host.changes, [1]);
      expect(host.controller.page, 1);
    });

    testWidgets('滚动模式超过可视宽度时首帧不抛空指针异常', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(360, 600)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 300,
                height: 44,
                child: HoboCapsule<int>(
                  segments: const [
                    (0, '最新评论'),
                    (1, '最新发帖'),
                    (2, '热门'),
                    (3, '精华'),
                    (4, '视频'),
                    (5, '相册'),
                  ],
                  value: 0,
                  scrollable: true,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('自适应模式未超出可视宽度时支持直接按住滑块跨不等宽分段拖拽', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MediaQuery(
            data: const MediaQueryData(size: Size(400, 600)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 380,
                  height: 40,
                  child: HoboCapsule<int>(
                    segments: const [(0, '关于'), (1, '微博(9499)'), (2, '相册')],
                    value: selected,
                    scrollable: true,
                    minSegmentWidth: 56,
                    segmentHorizontalPadding: 24,
                    onChanged: (next) => setState(() => selected = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final start = tester.getCenter(find.text('关于'));
      final target = tester.getCenter(find.text('微博(9499)'));
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(Offset(target.dx - start.dx, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selected, 1);
    });
  });
}
