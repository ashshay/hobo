import 'dart:async';
import 'dart:io';

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

/// 看图：左右翻页 + 双指缩放 + 双击放大 / 复原 + 实况图查看与保存。
///
/// 实况图交互：
/// - 打开或翻到实况图时自动后台缓存短视频并预热播放器；
/// - 长按画面播放实况，松手平滑淡回静图；点左下角「实况」胶囊也可单次播放/停止；
/// - 顶栏下载按钮默认保存为 Android Motion Photo（系统相册可直接识别播放），
///   更多菜单另提供「仅保存静图」「仅保存实况视频」。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.pics,
    this.initialIndex = 0,
  });

  final List<Pic> pics;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  final Map<int, TransformationController> _controllers = {};
  late final AnimationController _zoomController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _zoomCurve = CurvedAnimation(
    parent: _zoomController,
    curve: Curves.easeOutCubic,
  );
  Matrix4 _zoomFrom = Matrix4.identity();
  Matrix4 _zoomTo = Matrix4.identity();
  int? _zoomingIndex;

  late int _index = widget.initialIndex;
  bool _chrome = true;
  bool _saving = false;

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

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_applyZoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareLiveFor(_index));
    });
  }

  @override
  void dispose() {
    _liveGen++;
    _disposeLiveController();
    _zoomController.dispose();
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
        // 仍按住时停在最后一帧，等松手再淡回静图。
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
    if (index != _index) return;
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

  TransformationController _controllerFor(int index) =>
      _controllers.putIfAbsent(index, TransformationController.new);

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
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.pics.length,
              onPageChanged: (index) {
                if (index == _index) return;
                setState(() {
                  _index = index;
                  _resetLiveState();
                });
                unawaited(_prepareLiveFor(index));
              },
              itemBuilder: (context, index) => _buildPage(context, index),
            ),
          ),
          if (_chrome)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _TopBar(
                index: _index,
                total: widget.pics.length,
                pic: current,
                saving: _saving,
                onSave: _saveCurrent,
                onMore: () => _showActions(_index),
              ),
            ),
          if (_chrome && current.isLive)
            Positioned(
              left: 14,
              bottom:
                  MediaQuery.paddingOf(context).bottom +
                  (widget.pics.length > 1 ? 34 : 16),
              child: _LiveControls(
                state: _liveState,
                playing: _livePlaying,
                muted: _liveMuted,
                onTogglePlay: _onLivePillTap,
                onToggleMute: _toggleLiveMute,
              ),
            ),
          if (_chrome && widget.pics.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.pics.length; i++)
                    Container(
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
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final pic = widget.pics[index];
    final original =
        context.read<Settings>().imageBrowseQuality ==
        ImageBrowseQuality.original;
    final url = original && pic.large.isNotEmpty
        ? pic.large
        : (pic.large.isNotEmpty ? pic.large : pic.thumb);
    final isCurrentLive =
        pic.isLive && index == _index && _livePageIndex == index;
    final liveCtrl = isCurrentLive ? _liveController : null;

    Widget content = Hero(
      tag: picHeroTag(pic),
      child: RemoteImage(
        url: url,
        fit: BoxFit.contain,
        placeholderColor: const Color(0xFF111111),
        filterQuality: FilterQuality.medium,
      ),
    );

    if (pic.isLive) {
      final hasKnownAspect = pic.width > 0 && pic.height > 0;
      final videoReady = liveCtrl != null && liveCtrl.value.isInitialized;
      final aspect = hasKnownAspect
          ? pic.width / pic.height
          : (videoReady && liveCtrl.value.aspectRatio > 0
                ? liveCtrl.value.aspectRatio
                : null);

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

      if (aspect != null && aspect > 0) {
        content = AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              if (videoReady) liveOverlay(),
            ],
          ),
        );
      } else if (videoReady) {
        content = Stack(
          alignment: Alignment.center,
          children: [
            content,
            AspectRatio(
              aspectRatio: liveCtrl.value.aspectRatio > 0
                  ? liveCtrl.value.aspectRatio
                  : 3 / 4,
              child: liveOverlay(),
            ),
          ],
        );
      }
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
      child: InteractiveViewer(
        transformationController: _controllerFor(index),
        minScale: 0.8,
        maxScale: 4,
        onInteractionStart: (_) {
          if (_liveHolding) _onLiveHoldEnd();
        },
        child: Center(child: content),
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
