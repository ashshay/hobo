import 'dart:async';
import 'dart:io';
import 'dart:ui' show lerpDouble;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/media_saver.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';
import '../widgets/status_card.dart' show picHeroTag;

enum _LiveState { idle, loading, ready, failed }

/// 专用于看图页的半透明淡入路由：
///
/// 相比通用的 [CardPageRoute] 侧滑推入，看图路由保持底层页面静止，背景蒙层随 Hero
/// 展开平滑变黑，退出或下拉拖拽关闭时无缝飞回缩略图原位。
class ImageViewerRoute extends PageRoute<void> {
  ImageViewerRoute({
    required this.pics,
    this.initialIndex = 0,
    this.sourceCornerRadius = AppCorner.md,
  });

  final List<Pic> pics;
  final int initialIndex;
  final double sourceCornerRadius;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return ImageViewerPage(
      pics: pics,
      initialIndex: initialIndex,
      routeAnimation: animation,
      sourceCornerRadius: sourceCornerRadius,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// 看图：左右翻页 + 双指缩放 + 双击放大 / 复原 + 下拉手势关闭 + 实况图查看与保存。
///
/// 展开与收起动画：
/// - 配合 [ImageViewerRoute] 做透明背景渐暗与线性 Hero 展开，避免侧滑与 Hero 互相打架；
/// - 穿梭层同时叠放已解码缩略图与高清原图，且平滑插值超椭圆圆角（缩略图圆角 → 0），
///   首帧无灰块闪烁、落位无圆角跳变；
/// - 未放大时支持单指上下拖拽跟手缩放并动态透出底层页面，松手超过阈值直接飞回原位。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.pics,
    this.initialIndex = 0,
    this.routeAnimation,
    this.sourceCornerRadius = AppCorner.md,
  });

  final List<Pic> pics;
  final int initialIndex;
  final Animation<double>? routeAnimation;
  final double sourceCornerRadius;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with TickerProviderStateMixin {
  static const _dismissDistance = 108.0;
  static const _dismissVelocity = 680.0;
  static const _maxDragExtent = 320.0;

  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  final Map<int, TransformationController> _controllers = {};
  final Map<int, double> _resolvedAspects = {};

  late final AnimationController _zoomController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _zoomCurve = CurvedAnimation(
    parent: _zoomController,
    curve: Curves.easeOutCubic,
  );
  Matrix4 _zoomFrom = Matrix4.identity();
  Matrix4 _zoomTo = Matrix4.identity();
  int? _zoomingIndex;

  // 下拉关闭跟手状态与未达阈值时的回弹动画。
  late final AnimationController _dragResetController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _dragResetCurve = CurvedAnimation(
    parent: _dragResetController,
    curve: Curves.easeOutCubic,
  );
  Offset _dragOffset = Offset.zero;
  Offset _dragResetFrom = Offset.zero;
  bool _draggingDismiss = false;
  bool _dismissing = false;
  int _activePointers = 0;

  late int _index = widget.initialIndex;
  bool _chrome = true;
  bool _saving = false;
  bool _currentZoomed = false;

  // 实况图播放状态（仅维护当前页的一路播放器，切页或退出立即释放）。
  int _liveGen = 0;
  int? _livePageIndex;
  _LiveState _liveState = _LiveState.idle;
  File? _liveFile;
  VideoPlayerController? _liveController;
  bool _livePlaying = false;
  bool _liveHolding = false;
  bool _liveMuted = false;

  Pic get _currentPic => widget.pics[_index.clamp(0, widget.pics.length - 1)];

  double get _dragProgress =>
      (_dragOffset.dy.abs() / _maxDragExtent).clamp(0.0, 1.0);

  double get _dragScale => (1.0 - _dragProgress * 0.34).clamp(0.64, 1.0);

  double get _dragBackdropFactor =>
      (1.0 - _dragProgress * 0.85).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_applyZoom);
    _dragResetController.addListener(_applyDragReset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareLiveFor(_index));
    });
  }

  @override
  void dispose() {
    _liveGen++;
    _disposeLiveController();
    _zoomController.dispose();
    _dragResetController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _disposeLiveController() {
    final ctrl = _liveController;
    _liveController = null;
    if (ctrl != null) {
      ctrl.removeListener(_onLiveVideoTick);
      unawaited(ctrl.dispose());
    }
  }

  void _resetLiveState() {
    _liveGen++;
    _disposeLiveController();
    _livePageIndex = null;
    _liveState = _LiveState.idle;
    _liveFile = null;
    _livePlaying = false;
    _liveHolding = false;
  }

  Future<void> _prepareLiveFor(int index, {bool forceRetry = false}) async {
    if (!mounted || index < 0 || index >= widget.pics.length) return;
    final pic = widget.pics[index];
    if (!pic.isLive) {
      if (_liveController != null || _liveState != _LiveState.idle) {
        setState(_resetLiveState);
      }
      return;
    }
    if (!forceRetry &&
        _livePageIndex == index &&
        (_liveState == _LiveState.loading || _liveState == _LiveState.ready)) {
      return;
    }

    _disposeLiveController();
    final gen = ++_liveGen;
    setState(() {
      _livePageIndex = index;
      _liveState = _LiveState.loading;
      _liveFile = null;
      _livePlaying = false;
    });

    try {
      final cookie = context.read<Repo>().cookie();
      final file = await MediaSaver.cacheLiveVideo(
        pic.live,
        cookie: cookie,
        force: forceRetry,
      );
      if (!mounted || gen != _liveGen) return;
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      if (!mounted || gen != _liveGen) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(false);
      await ctrl.setVolume(_liveMuted ? 0 : 1);
      ctrl.addListener(_onLiveVideoTick);
      setState(() {
        _liveFile = file;
        _liveController = ctrl;
        _liveState = _LiveState.ready;
      });
      if (_liveHolding) {
        unawaited(_startLivePlayback());
      }
    } on Object {
      if (!mounted || gen != _liveGen) return;
      setState(() {
        _liveState = _LiveState.failed;
        _livePlaying = false;
        _liveHolding = false;
      });
    }
  }

  void _onLiveVideoTick() {
    final ctrl = _liveController;
    if (ctrl == null || !mounted || !_livePlaying) return;
    final value = ctrl.value;
    final duration = value.duration;
    if (duration > Duration.zero &&
        !value.isPlaying &&
        value.position >= duration - const Duration(milliseconds: 60)) {
      if (_liveHolding) {
        return;
      }
      setState(() => _livePlaying = false);
      unawaited(ctrl.seekTo(Duration.zero));
    }
  }

  Future<void> _startLivePlayback() async {
    final ctrl = _liveController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    HapticFeedback.lightImpact();
    await ctrl.setVolume(_liveMuted ? 0 : 1);
    await ctrl.seekTo(Duration.zero);
    if (!mounted || !identical(ctrl, _liveController)) return;
    setState(() => _livePlaying = true);
    await ctrl.play();
  }

  Future<void> _stopLivePlayback() async {
    final ctrl = _liveController;
    if (_livePlaying && mounted) {
      setState(() => _livePlaying = false);
    }
    if (ctrl == null) return;
    await ctrl.pause();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted || !identical(ctrl, _liveController) || _livePlaying) return;
    await ctrl.seekTo(Duration.zero);
  }

  void _onLiveHoldStart(int index) {
    if (index != _index || _draggingDismiss) return;
    if (_controllerFor(index).value.getMaxScaleOnAxis() > 1.05) return;
    _liveHolding = true;
    if (_liveState == _LiveState.ready) {
      unawaited(_startLivePlayback());
    } else if (_liveState == _LiveState.failed || _liveState == _LiveState.idle) {
      unawaited(_prepareLiveFor(index, forceRetry: true));
    }
  }

  void _onLiveHoldEnd() {
    if (!_liveHolding) return;
    _liveHolding = false;
    unawaited(_stopLivePlayback());
  }

  void _onLivePillTap() {
    if (!_currentPic.isLive) return;
    switch (_liveState) {
      case _LiveState.ready:
        if (_livePlaying) {
          _liveHolding = false;
          unawaited(_stopLivePlayback());
        } else {
          unawaited(_startLivePlayback());
        }
      case _LiveState.failed:
      case _LiveState.idle:
        unawaited(_prepareLiveFor(_index, forceRetry: true));
      case _LiveState.loading:
        break;
    }
  }

  void _toggleLiveMute() {
    final next = !_liveMuted;
    setState(() => _liveMuted = next);
    unawaited(_liveController?.setVolume(next ? 0 : 1));
  }

  TransformationController _controllerFor(int index) {
    return _controllers.putIfAbsent(index, () {
      final ctrl = TransformationController();
      ctrl.addListener(() {
        if (!mounted || index != _index) return;
        final zoomed = ctrl.value.getMaxScaleOnAxis() > 1.03;
        if (zoomed != _currentZoomed) {
          setState(() => _currentZoomed = zoomed);
        }
      });
      return ctrl;
    });
  }

  void _applyZoom() {
    final index = _zoomingIndex;
    if (index == null) return;
    final controller = _controllers[index];
    if (controller == null) return;
    controller.value = Matrix4Tween(
      begin: _zoomFrom,
      end: _zoomTo,
    ).transform(_zoomCurve.value);
  }

  void _animateZoom(int index, Matrix4 target) {
    _zoomingIndex = index;
    _zoomFrom = _controllerFor(index).value;
    _zoomTo = target;
    _zoomController
      ..stop()
      ..value = 0
      ..forward();
  }

  void _onDoubleTap(int index, TapDownDetails details) {
    if (_livePlaying) unawaited(_stopLivePlayback());
    final controller = _controllerFor(index);
    final scale = controller.value.getMaxScaleOnAxis();
    if (scale > 1.05) {
      _animateZoom(index, Matrix4.identity());
      return;
    }
    const target = 2.5;
    final point = details.localPosition;
    final matrix = Matrix4.identity()
      ..translate(-point.dx * (target - 1), -point.dy * (target - 1))
      ..scale(target);
    _animateZoom(index, matrix);
  }

  void _applyDragReset() {
    if (!mounted) return;
    setState(() {
      _dragOffset = Offset.lerp(
        _dragResetFrom,
        Offset.zero,
        _dragResetCurve.value,
      )!;
    });
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_currentZoomed || _activePointers > 1 || _dismissing) return;
    if (_livePlaying) unawaited(_stopLivePlayback());
    _dragResetController.stop();
    setState(() => _draggingDismiss = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_draggingDismiss || _currentZoomed || _activePointers > 1) return;
    setState(() {
      _dragOffset += Offset(details.delta.dx * 0.55, details.delta.dy);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_draggingDismiss) return;
    final velocityY = details.velocity.pixelsPerSecond.dy;
    final shouldDismiss =
        _dragOffset.dy.abs() >= _dismissDistance ||
        (velocityY.abs() >= _dismissVelocity &&
            velocityY.sign == _dragOffset.dy.sign);
    if (shouldDismiss) {
      _dismissing = true;
      Navigator.of(context).maybePop();
      return;
    }
    _springDragBack();
  }

  void _springDragBack() {
    if (!_draggingDismiss && _dragOffset == Offset.zero) return;
    _dragResetFrom = _dragOffset;
    setState(() => _draggingDismiss = false);
    if (_dragResetFrom == Offset.zero) return;
    _dragResetController
      ..stop()
      ..value = 0
      ..forward();
  }

  void _recordResolvedAspect(int index, double aspect) {
    if (aspect <= 0 || !aspect.isFinite) return;
    final prev = _resolvedAspects[index];
    if (prev != null && (prev - aspect).abs() < 0.005) return;
    _resolvedAspects[index] = aspect;
    if (mounted && index == _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 保存当前这张图到系统相册：实况图默认封装为 Motion Photo，静图直接存原图。
  Future<void> _saveCurrent() async {
    final pic = _currentPic;
    if (pic.isLive) {
      await _saveCurrentLivePhoto();
    } else {
      await _saveCurrentStill();
    }
  }

  Future<void> _saveCurrentStill() async {
    if (_saving) return;
    final pic = _currentPic;
    final url = pic.large.isNotEmpty ? pic.large : pic.thumb;
    if (url.isEmpty) return;
    setState(() => _saving = true);
    try {
      await MediaSaver.saveImage(url, cookie: context.read<Repo>().cookie());
      if (mounted) showHoboToast(context, '已保存到相册');
    } on Object catch (e) {
      if (mounted) {
        showHoboToast(context, '保存失败：$e', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCurrentLivePhoto() async {
    if (_saving) return;
    final pic = _currentPic;
    final imageUrl = pic.large.isNotEmpty ? pic.large : pic.thumb;
    if (imageUrl.isEmpty || !pic.isLive) return;
    setState(() => _saving = true);
    try {
      await MediaSaver.saveLivePhoto(
        imageUrl: imageUrl,
        liveUrl: pic.live,
        cookie: context.read<Repo>().cookie(),
        cachedVideo: _livePageIndex == _index ? _liveFile : null,
      );
      if (mounted) showHoboToast(context, '已保存实况图到相册');
    } on Object catch (e) {
      if (mounted) {
        showHoboToast(context, '保存实况图失败：$e', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCurrentLiveVideo() async {
    if (_saving) return;
    final pic = _currentPic;
    if (!pic.isLive) return;
    setState(() => _saving = true);
    try {
      await MediaSaver.saveLiveVideo(
        pic.live,
        cookie: context.read<Repo>().cookie(),
        cachedVideo: _livePageIndex == _index ? _liveFile : null,
      );
      if (mounted) showHoboToast(context, '已保存实况视频到相册');
    } on Object catch (e) {
      if (mounted) {
        showHoboToast(context, '保存实况视频失败：$e', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 更多操作菜单：静图由长按触发，实况图由顶栏「更多」触发（长按让给实况播放）。
  Future<void> _showActions(int index) async {
    final pic = widget.pics[index.clamp(0, widget.pics.length - 1)];
    final url = pic.large.isNotEmpty ? pic.large : pic.thumb;
    final title = widget.pics.length > 1
        ? '${pic.isLive ? '实况图' : '图片'} ${index + 1}/${widget.pics.length}'
        : (pic.isLive ? '实况图' : '图片');
    await showHoboActionSheet(
      context,
      title: title,
      actions: [
        if (pic.isLive) ...[
          ('保存实况图', _saveCurrentLivePhoto),
          ('仅保存静图', _saveCurrentStill),
          ('仅保存实况视频', _saveCurrentLiveVideo),
        ] else
          ('保存图片', _saveCurrentStill),
        (
          '复制图片链接',
          () {
            Clipboard.setData(ClipboardData(text: url));
            showHoboToast(context, '图片链接已复制');
          },
        ),
        if (pic.isLive)
          (
            '复制实况视频链接',
            () {
              Clipboard.setData(ClipboardData(text: pic.live));
              showHoboToast(context, '实况视频链接已复制');
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentPic;
    final routeAnim = widget.routeAnimation ?? kAlwaysCompleteAnimation;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final showChrome = _chrome && !_draggingDismiss && !_dismissing;

    return Listener(
      onPointerDown: (_) {
        _activePointers++;
        if (_activePointers > 1 && _draggingDismiss) {
          _springDragBack();
        }
      },
      onPointerUp: (_) {
        _activePointers = (_activePointers - 1).clamp(0, 10);
      },
      onPointerCancel: (_) {
        _activePointers = (_activePointers - 1).clamp(0, 10);
      },
      child: AnimatedBuilder(
        animation: routeAnim,
        builder: (context, child) {
          final rawT = disableAnimations ? 1.0 : routeAnim.value;
          final scrimT = Curves.easeOutCubic.transform(rawT.clamp(0.0, 1.0));
          final backdropAlpha = (scrimT * _dragBackdropFactor).clamp(0.0, 1.0);
          final chromeRouteOpacity = disableAnimations
              ? 1.0
              : ((rawT - 0.35) / 0.65).clamp(0.0, 1.0);
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Color.fromRGBO(0, 0, 0, backdropAlpha),
                ),
              ),
              Positioned.fill(
                child: _wrapNonHeroEntrance(
                  rawT: rawT,
                  disableAnimations: disableAnimations,
                  child: child!,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  ignoring: !showChrome || chromeRouteOpacity < 0.2,
                  child: Opacity(
                    opacity: chromeRouteOpacity,
                    child: AnimatedOpacity(
                      opacity: showChrome ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: _TopBar(
                        index: _index,
                        total: widget.pics.length,
                        pic: current,
                        saving: _saving,
                        onSave: _saveCurrent,
                        onMore: () => _showActions(_index),
                      ),
                    ),
                  ),
                ),
              ),
              if (current.isLive)
                Positioned(
                  left: 14,
                  bottom:
                      MediaQuery.paddingOf(context).bottom +
                      (widget.pics.length > 1 ? 34 : 16),
                  child: IgnorePointer(
                    ignoring: !showChrome || chromeRouteOpacity < 0.2,
                    child: Opacity(
                      opacity: chromeRouteOpacity,
                      child: AnimatedOpacity(
                        opacity: showChrome ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: _LiveControls(
                          state: _liveState,
                          playing: _livePlaying,
                          muted: _liveMuted,
                          onTogglePlay: _onLivePillTap,
                          onToggleMute: _toggleLiveMute,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.pics.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 16,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: chromeRouteOpacity,
                      child: AnimatedOpacity(
                        opacity: showChrome ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < widget.pics.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                width: i == _index ? 16 : 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                decoration: ShapeDecoration(
                                  color: i == _index
                                      ? const Color(0xFFFFFFFF)
                                      : const Color(0x66FFFFFF),
                                  shape: AppShape.full,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: Transform.translate(
          offset: _dragOffset,
          child: Transform.scale(
            scale: _dragScale,
            child: PageView.builder(
              controller: _pageController,
              physics: _currentZoomed || _draggingDismiss
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              itemCount: widget.pics.length,
              onPageChanged: (index) {
                if (index == _index) return;
                final zoomed =
                    _controllers[index]?.value.getMaxScaleOnAxis() ?? 1.0;
                setState(() {
                  _index = index;
                  _currentZoomed = zoomed > 1.03;
                  _resetLiveState();
                });
                unawaited(_prepareLiveFor(index));
              },
              itemBuilder: (context, index) => _buildPage(context, index),
            ),
          ),
        ),
      ),
    );
  }

  /// 从无 Hero 入口（如正文「查看图片」文字链、私信图）打开时，走顺滑缩放 + 渐显兜底。
  Widget _wrapNonHeroEntrance({
    required double rawT,
    required bool disableAnimations,
    required Widget child,
  }) {
    if (disableAnimations || _currentPic.heroTag.isNotEmpty || rawT >= 1.0) {
      return child;
    }
    final curved = Curves.easeOutCubic.transform(rawT.clamp(0.0, 1.0));
    return Opacity(
      opacity: curved,
      child: Transform.scale(scale: lerpDouble(0.92, 1.0, curved)!, child: child),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final pic = widget.pics[index];
    final original =
        context.read<Settings>().imageBrowseQuality ==
        ImageBrowseQuality.original;
    final largeUrl = original && pic.large.isNotEmpty
        ? pic.large
        : (pic.large.isNotEmpty ? pic.large : pic.thumb);
    final isCurrentLive =
        pic.isLive && index == _index && _livePageIndex == index;
    final liveCtrl = isCurrentLive ? _liveController : null;

    final knownAspect = pic.width > 0 && pic.height > 0
        ? pic.width / pic.height
        : (_resolvedAspects[index] ??
              (liveCtrl != null &&
                      liveCtrl.value.isInitialized &&
                      liveCtrl.value.aspectRatio > 0
                  ? liveCtrl.value.aspectRatio
                  : null));

    Widget imageLayer = _ProgressiveViewerImage(
      thumbUrl: pic.thumb,
      largeUrl: largeUrl,
      fit: knownAspect != null ? BoxFit.cover : BoxFit.contain,
      onResolvedSize: (width, height) {
        if (width > 0 && height > 0) {
          _recordResolvedAspect(index, width / height);
        }
      },
    );

    Widget heroWidget = Hero(
      tag: picHeroTag(pic),
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        return _ImageHeroShuttle(
          animation: animation,
          flightDirection: flightDirection,
          fromHeroContext: fromHeroContext,
          toHeroContext: toHeroContext,
          largeUrl: largeUrl,
          thumbUrl: pic.thumb,
          sourceCornerRadius: widget.sourceCornerRadius,
        );
      },
      child: imageLayer,
    );

    Widget content = heroWidget;

    if (pic.isLive) {
      final videoReady = liveCtrl != null && liveCtrl.value.isInitialized;
      Widget liveOverlay() {
        if (!videoReady) return const SizedBox.shrink();
        final size = liveCtrl.value.size;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: _livePlaying ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size.width > 0 ? size.width : 1,
                  height: size.height > 0 ? size.height : 1,
                  child: VideoPlayer(liveCtrl),
                ),
              ),
            ),
          ),
        );
      }

      if (knownAspect != null && knownAspect > 0) {
        content = AspectRatio(
          aspectRatio: knownAspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              heroWidget,
              if (videoReady) liveOverlay(),
            ],
          ),
        );
      } else if (videoReady) {
        content = Stack(
          alignment: Alignment.center,
          children: [
            heroWidget,
            AspectRatio(
              aspectRatio: liveCtrl.value.aspectRatio > 0
                  ? liveCtrl.value.aspectRatio
                  : 3 / 4,
              child: liveOverlay(),
            ),
          ],
        );
      }
    } else if (knownAspect != null && knownAspect > 0) {
      // 将目标 Hero 精确约束到图片原始宽高比：展开/收起时 `BoxFit.cover` 与最终画面
      // 严丝合缝，不会出现跳变或拉伸黑边。
      content = AspectRatio(aspectRatio: knownAspect, child: heroWidget);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _chrome = !_chrome),
      onLongPress: pic.isLive ? null : () => _showActions(index),
      onLongPressStart: pic.isLive ? (_) => _onLiveHoldStart(index) : null,
      onLongPressEnd: pic.isLive ? (_) => _onLiveHoldEnd() : null,
      onLongPressCancel: pic.isLive ? _onLiveHoldEnd : null,
      onDoubleTapDown: (details) => _onDoubleTap(index, details),
      onDoubleTap: () {},
      onVerticalDragStart: _currentZoomed ? null : _onVerticalDragStart,
      onVerticalDragUpdate: _currentZoomed ? null : _onVerticalDragUpdate,
      onVerticalDragEnd: _currentZoomed ? null : _onVerticalDragEnd,
      onVerticalDragCancel: _currentZoomed ? null : _springDragBack,
      child: InteractiveViewer(
        transformationController: _controllerFor(index),
        panEnabled: _currentZoomed,
        minScale: 1.0,
        maxScale: 4.0,
        onInteractionStart: (_) {
          if (_liveHolding) _onLiveHoldEnd();
        },
        child: Center(child: content),
      ),
    );
  }
}

/// 渐进式看图组件：底层先用已缓存缩略图秒开占位，高清原图就绪后无缝淡入覆盖。
class _ProgressiveViewerImage extends StatefulWidget {
  const _ProgressiveViewerImage({
    required this.thumbUrl,
    required this.largeUrl,
    required this.fit,
    this.onResolvedSize,
  });

  final String thumbUrl;
  final String largeUrl;
  final BoxFit fit;
  final void Function(int width, int height)? onResolvedSize;

  @override
  State<_ProgressiveViewerImage> createState() =>
      _ProgressiveViewerImageState();
}

class _ProgressiveViewerImageState extends State<_ProgressiveViewerImage> {
  bool _largeLoaded = false;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveNaturalSize();
  }

  @override
  void didUpdateWidget(covariant _ProgressiveViewerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.largeUrl != widget.largeUrl ||
        oldWidget.thumbUrl != widget.thumbUrl) {
      _largeLoaded = false;
      _resolveNaturalSize();
    }
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  void _detachStream() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  Map<String, String>? _headersFor(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isEmpty) return null;
    if (!(host == 'weibo.com' || host.endsWith('.weibo.com'))) return null;
    final cookie = context.read<Repo>().cookie();
    if (cookie == null || cookie.isEmpty) return null;
    return {'Cookie': cookie, 'User-Agent': 'Mozilla/5.0'};
  }

  void _resolveNaturalSize() {
    _detachStream();
    if (widget.onResolvedSize == null || widget.largeUrl.isEmpty) return;
    final provider = NetworkImage(
      widget.largeUrl,
      headers: _headersFor(widget.largeUrl),
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      widget.onResolvedSize?.call(info.image.width, info.image.height);
    }, onError: (_, _) {});
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  @override
  Widget build(BuildContext context) {
    final hasSeparateThumb =
        widget.thumbUrl.isNotEmpty && widget.thumbUrl != widget.largeUrl;
    final largeUrl = widget.largeUrl;
    if (largeUrl.isEmpty) {
      return const ColoredBox(color: Color(0xFF111111));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasSeparateThumb && !_largeLoaded)
          RemoteImage(
            url: widget.thumbUrl,
            fit: widget.fit,
            placeholderColor: const Color(0xFF111111),
            filterQuality: FilterQuality.medium,
          ),
        Image.network(
          largeUrl,
          fit: widget.fit,
          headers: _headersFor(largeUrl),
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              if (!_largeLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_largeLoaded) {
                    setState(() => _largeLoaded = true);
                  }
                });
              }
              return child;
            }
            if (hasSeparateThumb) {
              return const SizedBox.shrink();
            }
            return const ColoredBox(
              color: Color(0xFF111111),
              child: Center(
                child: ActivityIndicator(size: 22, color: Color(0x99FFFFFF)),
              ),
            );
          },
          errorBuilder: (context, error, stack) {
            if (hasSeparateThumb) {
              return RemoteImage(
                url: widget.thumbUrl,
                fit: widget.fit,
                placeholderColor: const Color(0xFF111111),
                filterQuality: FilterQuality.medium,
              );
            }
            return const ColoredBox(
              color: Color(0xFF111111),
              child: Center(
                child: GlyphIcon(
                  Glyphs.eyeOff,
                  size: 24,
                  color: Color(0x99FFFFFF),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Hero 展开/收起穿梭层：实时插值超椭圆圆角并保底显示已缓存图像，杜绝首帧闪烁与跳变。
class _ImageHeroShuttle extends StatelessWidget {
  const _ImageHeroShuttle({
    required this.animation,
    required this.flightDirection,
    required this.fromHeroContext,
    required this.toHeroContext,
    required this.largeUrl,
    required this.thumbUrl,
    required this.sourceCornerRadius,
  });

  final Animation<double> animation;
  final HeroFlightDirection flightDirection;
  final BuildContext fromHeroContext;
  final BuildContext toHeroContext;
  final String largeUrl;
  final String thumbUrl;
  final double sourceCornerRadius;

  @override
  Widget build(BuildContext context) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;
    final thumbChild = flightDirection == HeroFlightDirection.push
        ? fromHero.child
        : toHero.child;
    final fullChild = flightDirection == HeroFlightDirection.push
        ? toHero.child
        : fromHero.child;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final raw = animation.value.clamp(0.0, 1.0);
        final t = flightDirection == HeroFlightDirection.push
            ? Curves.easeOutCubic.transform(raw)
            : Curves.easeInCubic.transform(raw);
        final radius = lerpDouble(sourceCornerRadius, 0.0, t) ?? 0.0;
        if (radius <= 0.1) return child!;
        return ClipRSuperellipse(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumbChild,
          if (flightDirection == HeroFlightDirection.pop) fullChild,
        ],
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({
    required this.state,
    required this.playing,
    required this.muted,
    required this.onTogglePlay,
    required this.onToggleMute,
  });

  final _LiveState state;
  final bool playing;
  final bool muted;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      _LiveState.loading => '实况加载中',
      _LiveState.failed => '实况失败 · 重试',
      _LiveState.ready => playing ? '实况播放中' : '实况',
      _LiveState.idle => '实况',
    };
    final activeColor = context.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTogglePlay,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: ShapeDecoration(
              color: playing
                  ? activeColor.withValues(alpha: 0.85)
                  : const Color(0x8A141414),
              shape: AppShape.full,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state == _LiveState.loading)
                  const ActivityIndicator(size: 14, color: Color(0xFFFFFFFF))
                else
                  const GlyphIcon(
                    HoboGlyphs.livePhoto,
                    size: 16,
                    color: Color(0xFFFFFFFF),
                  ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyle.caption1.of(context).copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (state == _LiveState.ready) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onToggleMute,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const ShapeDecoration(
                color: Color(0x8A141414),
                shape: AppShape.full,
              ),
              child: GlyphIcon(
                muted ? HoboGlyphs.volumeOff : HoboGlyphs.volumeOn,
                size: 17,
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.total,
    required this.pic,
    required this.saving,
    required this.onSave,
    required this.onMore,
  });

  final int index;
  final int total;
  final Pic pic;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, top + 4, 8, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const GlyphIcon(
              Glyphs.close,
              size: 24,
              color: Color(0xFFFFFFFF),
            ),
          ),
          const Spacer(),
          Text(
            '${index + 1} / $total',
            style: AppTextStyle.footnote.of(context).copyWith(
              fontSize: 13,
              color: const Color(0xFFFFFFFF),
            ),
          ),
          const Spacer(),
          IconButton(
            // 保持可点：prism 的按钮在 onPressed 于 null / 非 null 之间来回切时，
            // 会在自己 build 的过程中把状态控制器改脏，触发框架断言。重复点击由
            // _saveCurrent 里的 _saving 挡住。
            onPressed: onSave,
            icon: saving
                ? const ActivityIndicator(size: 20, color: Color(0xFFFFFFFF))
                : const GlyphIcon(
                    HoboGlyphs.download,
                    size: 22,
                    color: Color(0xFFFFFFFF),
                  ),
            tooltip: pic.isLive ? '保存实况图' : '保存图片',
          ),
          if (pic.isLive)
            IconButton(
              onPressed: onMore,
              icon: const GlyphIcon(
                HoboGlyphs.more,
                size: 22,
                color: Color(0xFFFFFFFF),
              ),
              tooltip: '更多保存选项',
            )
          else
            IconButton(
              onPressed: () => _copyLink(context),
              icon: const GlyphIcon(
                HoboGlyphs.link,
                size: 22,
                color: Color(0xFFFFFFFF),
              ),
              tooltip: '复制图片链接',
            ),
        ],
      ),
    );
  }

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: pic.large));
    showHoboToast(context, '图片链接已复制');
  }
}
