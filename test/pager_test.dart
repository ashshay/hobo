import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hobo/ui/widgets/pager.dart';

/// 800×600 的画布，三页各一块纯色，方便断言翻到了哪一页。
class _PagerHost extends StatefulWidget {
  const _PagerHost({required this.onReady, this.disableAnimations = false});

  final ValueChanged<_PagerHostState> onReady;
  final bool disableAnimations;

  @override
  State<_PagerHost> createState() => _PagerHostState();
}

class _PagerHostState extends State<_PagerHost> with TickerProviderStateMixin {
  late final HoboPagerController controller = HoboPagerController(
    vsync: this,
    count: 3,
  );
  int index = 0;

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
        child: SizedBox(
          width: 800,
          height: 600,
          child: HoboPager(
            controller: controller,
            index: index,
            onIndexChanged: (next) => setState(() => index = next),
            children: const [
              ColoredBox(color: Color(0xFFAA0000), child: SizedBox.expand()),
              ColoredBox(color: Color(0xFF00AA00), child: SizedBox.expand()),
              ColoredBox(color: Color(0xFF0000AA), child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
  }
}

Future<_PagerHostState> _pumpHost(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  late _PagerHostState host;
  await tester.pumpWidget(
    _PagerHost(
      disableAnimations: disableAnimations,
      onReady: (state) => host = state,
    ),
  );
  await tester.pump();
  return host;
}

void main() {
  group('HoboPager', () {
    testWidgets('从左往右拖过半屏就翻一页', (tester) async {
      final host = await _pumpHost(tester);
      expect(host.controller.page, 0);

      await tester.drag(find.byType(HoboPager), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(host.index, 1);
      expect(host.controller.page, closeTo(1, 0.01));
    });

    testWidgets('拖一点点松手弹回原页', (tester) async {
      final host = await _pumpHost(tester);
      await tester.drag(find.byType(HoboPager), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(host.index, 0);
      expect(host.controller.page, closeTo(0, 0.01));
    });

    testWidgets('第一页再往右拖，两端有橡皮筋但不越界', (tester) async {
      final host = await _pumpHost(tester);
      final gesture = await tester.startGesture(const Offset(400, 300));
      // 第一下只够触发拖拽识别，位移从第二下开始算。
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 120));
      // 跟手时被橡皮筋压住，最多只走一小段。
      expect(host.controller.page, lessThan(0));
      expect(host.controller.page, greaterThan(-0.3));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(host.controller.page, closeTo(0, 0.01));
      expect(host.index, 0);
    });

    testWidgets('点胶囊那种外部改页也会弹簧过去', (tester) async {
      final host = await _pumpHost(tester);
      host.controller.goToPage(2);
      await tester.pump();
      // 中途一定是连续位置，不是瞬间跳过去。
      await tester.pump(const Duration(milliseconds: 60));
      expect(host.controller.page, greaterThan(0));
      expect(host.controller.page, lessThan(2));

      await tester.pumpAndSettle();
      expect(host.controller.page, closeTo(2, 0.01));
    });

    testWidgets('快速连点会带着当前速度改向，不会卡在原地', (tester) async {
      final host = await _pumpHost(tester);
      host.controller.goToPage(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final midway = host.controller.page;
      expect(midway, greaterThan(0));

      host.controller.goToPage(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(host.controller.page, isNot(closeTo(midway, 0.001)));

      await tester.pumpAndSettle();
      expect(host.controller.page, closeTo(0, 0.01));
    });

    testWidgets('系统关闭动画时直接落位', (tester) async {
      final host = await _pumpHost(tester, disableAnimations: true);
      await tester.drag(find.byType(HoboPager), const Offset(-500, 0));
      await tester.pump();

      expect(host.index, 1);
      expect(host.controller.page, 1);
    });
  });
}
