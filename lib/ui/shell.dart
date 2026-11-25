import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../data/repo.dart';
import '../data/settings.dart';
import '../data/update.dart';
import 'chrome.dart';
import 'pages/feed_page.dart';
import 'pages/messages_page.dart';
import 'pages/profile_page.dart';
import 'pages/search_page.dart';
import 'routes.dart';
import 'widgets/common.dart';
import 'widgets/glyphs.dart';
import 'widgets/remote_image.dart';
import 'widgets/update_dialog.dart';

/// 应用外壳：四栏页面 + 居中的四格底栏。
class HoboShell extends StatefulWidget {
  const HoboShell({super.key});

  @override
  State<HoboShell> createState() => _HoboShellState();
}

class _HoboShellState extends State<HoboShell> {
  int _index = 0;
  final GlobalKey _dockKey = GlobalKey();
  DateTime? _lastHomeTapAt;
  Timer? _longPressTimer;
  Offset? _pressStart;
  bool _autoUpdateTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkAutoUpdate());
    });
  }

  /// 冷启动后在首页静默检测一次更新；有新版本且未勾选「不再提醒」时弹出更新窗口。
  Future<void> _checkAutoUpdate() async {
    if (_autoUpdateTriggered || !mounted) return;
    _autoUpdateTriggered = true;
    final settings = context.read<Settings>();
    if (!settings.autoCheckUpdate) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final result = await Updater.checkForUpdate(settings: settings);
    if (!mounted || !result.shouldPrompt) return;
    // 只在首页本身处于前台顶层时弹窗，避免盖住登录页、看图页或视频页。
    if (_index != 0) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final info = result.update!;
    final action = await showUpdateDialog(
      context,
      info,
      currentVersion: result.currentVersion,
      showDontRemind: true,
    );
    if (!mounted) return;
    if (action.dontRemind) {
      settings.applySkippedUpdate(info.version);
    }
    if (action.update) {
      await openReleasePage(context, info);
    }
  }

  void _onDockSelected(int index) {
    // 换页时顶栏底栏都回来，不然藏在底部就没法再切回去。
    context.read<ChromeController>().setHidden(false);
    setState(() => _index = index);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  /// 按住底栏「我」约半秒：弹出账号切换。移动超过 12px 就当滚动取消。
  void _handleDockPointerDown(PointerDownEvent event) {
    _cancelLongPress();
    final box = _dockKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    _pressStart = event.position;
    if (_dockIndexAt(box.globalToLocal(event.position), box.size) != 3) return;
    if (!context.read<Settings>().quickSwitchAccount) return;
    if (!context.read<Repo>().hasSession()) return;
    _longPressTimer = Timer(const Duration(milliseconds: 480), () {
      _longPressTimer = null;
      _pressStart = null;
      if (mounted) unawaited(_quickSwitchAccount());
    });
  }

  void _handleDockPointerMove(PointerMoveEvent event) {
    final start = _pressStart;
    if (start == null) return;
    if ((event.position - start).distance > 12) _cancelLongPress();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pressStart = null;
  }

  void _handleDockPointerUp(PointerUpEvent event) {
    _cancelLongPress();
    final box = _dockKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    if (_dockIndexAt(box.globalToLocal(event.position), box.size) != 0) {
      _lastHomeTapAt = null;
      return;
    }
    final now = DateTime.now();
    final last = _lastHomeTapAt;
    if (last != null &&
        now.difference(last) <= const Duration(milliseconds: 320)) {
      _lastHomeTapAt = null;
      _refreshHome();
    } else {
      _lastHomeTapAt = now;
    }
  }

  void _refreshHome() {
    final chrome = context.read<ChromeController>();
    chrome.setHidden(false);
    if (_index != 0) setState(() => _index = 0);
    chrome.requestHomeRefresh();
  }

  Future<void> _quickSwitchAccount() async {
    final repo = context.read<Repo>();
    final accounts = repo.store.accounts();
    if (accounts.length < 2) {
      showHoboToast(context, '只有一个账号，可在 设置 → 账号 里添加');
      return;
    }
    HapticFeedback.mediumImpact();
    final current = repo.session?.uid ?? '';
    final picked = await showHoboChoices<int>(
      context,
      title: '切换账号',
      choices: [
        for (var i = 0; i < accounts.length; i++)
          HoboChoice(
            value: i,
            label: accounts[i].name.isEmpty ? accounts[i].uid : accounts[i].name,
            subtitle: accounts[i].uid == current ? '当前账号' : accounts[i].uid,
            leading: Avatar(url: accounts[i].avatar, size: 30),
            selected: accounts[i].uid == current,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    final account = accounts[picked];
    if (account.uid == current) return;
    await repo.switchAccount(account);
    if (!mounted) return;
    context.read<ChromeController>().setHidden(false);
    showHoboToast(
      context,
      '已切换到 ${account.name.isEmpty ? account.uid : account.name}',
    );
  }

  /// 落点属于底栏哪一格。四格等分，常量照抄 prism 的 `_dockLayout`。
  int _dockIndexAt(Offset local, Size size) {
    const count = 4;
    const edge = 21.0;
    const barPadding = 4.0;
    const maxBar = 360.0;
    const minLens = 84.0;
    final barWidth = math.min(size.width - edge * 2, maxBar);
    final barLeft = (size.width - barWidth) / 2;
    final span = barWidth - barPadding * 2;
    final pitch = (span - barPadding * 2) / count;
    final double itemWidth;
    final double inset;
    if (pitch + barPadding * 2 >= minLens) {
      itemWidth = pitch;
      inset = barPadding;
    } else {
      final lens = math.min(minLens, span);
      itemWidth = (span - lens) / (count - 1);
      inset = (lens - itemWidth) / 2;
    }
    final x = local.dx - barLeft - barPadding - inset;
    if (x < 0) return -1;
    return (x / itemWidth).floor().clamp(0, count - 1);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final settings = context.watch<Settings>();
    final chrome = context.watch<ChromeController>();
    final dockAvatar = settings.profileTabAvatar && repo.hasSession()
        ? repo.ownAvatar()
        : '';
    final pages = <Widget>[
      FeedPage(key: ValueKey('feed-${repo.session?.uid ?? ''}')),
      const SearchPage(showBack: false),
      const MessagesPage(),
      repo.hasSession()
          ? ProfilePage(
              key: ValueKey('me-${repo.session?.uid}'),
              showBack: false,
            )
          : const _GuestMePage(),
    ];
    return Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: Stack(
        children: [
          Positioned.fill(
            child: BottomInsetScope(
              inset: NavigationDock.insetOf(context),
              child: IndexedStack(index: _index, children: pages),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: chrome.hidden ? const Offset(0, 1) : Offset.zero,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedLiquidGlassFade(
                opacity: chrome.hidden ? 0 : 1,
                duration: const Duration(milliseconds: 160),
                child: Listener(
                  onPointerDown: _handleDockPointerDown,
                  onPointerMove: _handleDockPointerMove,
                  onPointerUp: _handleDockPointerUp,
                  onPointerCancel: (_) => _cancelLongPress(),
                  child: NavigationDock(
                    key: _dockKey,
                    destinations: [
                      const NavigationDockDestination(
                        glyph: HoboGlyphs.home,
                        label: '微博',
                      ),
                      const NavigationDockDestination(
                        glyph: HoboGlyphs.explore,
                        label: '发现',
                      ),
                      const NavigationDockDestination(
                        glyph: HoboGlyphs.messages,
                        label: '消息',
                      ),
                      NavigationDockDestination(
                        glyph: HoboGlyphs.person,
                        label: '我',
                        icon: dockAvatar.isEmpty
                            ? null
                            : Avatar(url: dockAvatar, size: 28),
                      ),
                    ],
                    selectedIndex: _index,
                    onSelected: _onDockSelected,
                    tintSelection:
                        settings.blurEffects &&
                        settings.dockGlassStyle == DockGlassPreset.crystal,
                    glassStyle: settings.navigationDockGlassStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 未登录时的「我」：提示登录或进入本地模式。
class _GuestMePage extends StatelessWidget {
  const _GuestMePage();

  @override
  Widget build(BuildContext context) {
    return PrismScaffold(
      bar: HoboAppBar(
        title: Text(
          '我',
          style: AppTextStyle.title1
              .of(context)
              .copyWith(
                color: context.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: HoboEmpty(
              title: '还没有登录',
              message: '登录后可以关注、评论、发微博和看私信',
              icon: HoboGlyphs.person,
              action: Column(
                children: [
                  SizedBox(
                    width: 180,
                    child: FilledButton(
                      onPressed: () => openLogin(context),
                      child: const Text('登录微博'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () async {
                      await context.read<Repo>().enterLocalMode();
                      if (context.mounted) {
                        showHoboToast(context, '已进入纯本地浏览');
                      }
                    },
                    child: const Text('不登录，纯本地浏览'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => openSettings(context),
                    child: const Text('设置'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 6,
            child: IconButton(
              onPressed: () => openSettings(context),
              tooltip: '设置',
              icon: const GlyphIcon(HoboGlyphs.wrench, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
