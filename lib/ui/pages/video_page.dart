import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/media_saver.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';

/// 视频播放。微博 CDN 只认带 Referer 的请求，所以给播放器带上请求头；
/// 如果拿到的不是直链（视频页 / 第三方站点），退回内置浏览器。
class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.video});

  final VideoInfo video;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  late VideoQuality? _quality = widget.video.current;
  bool _saving = false;
  double _saveProgress = 0;

  String get _url => _quality?.url ?? widget.video.url;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool _looksLikeMedia(String url) {
    final path = url.split('?').first.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.m4v') ||
        path.endsWith('.mov') ||
        path.endsWith('.m3u8') ||
        path.endsWith('.webm');
  }

  Future<bool> _init({Duration? startAt, bool play = true}) async {
    final url = _url;
    if (!_looksLikeMedia(url)) {
      setState(() {
        _loading = false;
        _error = '这一条不是视频直链';
      });
      return false;
    }
    final repo = context.read<Repo>();
    final cookie = repo.cookie();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {
        'Referer': 'https://m.weibo.cn/',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; MI 9) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
      },
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return false;
      }
      final previous = _controller;
      setState(() {
        _controller = controller;
        _loading = false;
        _error = null;
      });
      await previous?.dispose();
      if (startAt != null && startAt > Duration.zero) {
        await controller.seekTo(startAt);
      }
      if (play) await controller.play();
      return true;
    } on Object catch (e) {
      await controller.dispose();
      if (!mounted) return false;
      // 换清晰度失败时保留原来那一档，别把正在看的画面弄没。
      if (_controller != null) {
        setState(() => _loading = false);
        showHoboToast(context, '切换清晰度失败：$e', level: BannerLevel.error);
        return false;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      return false;
    }
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  Future<void> _pickQuality() async {
    final qualities = widget.video.qualities;
    if (qualities.length < 2) return;
    final picked = await showHoboChoices<VideoQuality>(
      context,
      title: '清晰度',
      choices: [
        for (final quality in qualities)
          HoboChoice(
            value: quality,
            label: quality.label,
            subtitle: quality.detail.isEmpty ? null : quality.detail,
            selected: quality.url == _url,
          ),
      ],
    );
    if (picked == null || !mounted || picked.url == _url) return;
    final position = _controller?.value.position ?? Duration.zero;
    final wasPlaying = _controller?.value.isPlaying ?? true;
    final previous = _quality;
    setState(() {
      _quality = picked;
      _loading = true;
    });
    final ok = await _init(startAt: position, play: wasPlaying);
    if (!ok && mounted) setState(() => _quality = previous);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveProgress = 0;
    });
    try {
      await MediaSaver.saveVideo(
        _url,
        cookie: context.read<Repo>().cookie(),
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _saveProgress = received / total);
        },
      );
      if (mounted) showHoboToast(context, '已保存视频到相册');
    } on Object catch (e) {
      if (mounted) {
        showHoboToast(context, '保存失败：$e', level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        children: [
          Positioned.fill(child: _buildVideo()),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8,
                MediaQuery.paddingOf(context).top + 4,
                8,
                12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const GlyphIcon(
                      Glyphs.chevronBack,
                      size: 24,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _saving
                          ? '正在下载 ${(_saveProgress * 100).round()}%'
                          : (widget.video.title.isEmpty
                                ? '视频'
                                : widget.video.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.footnote.of(context).copyWith(
                        fontSize: 14,
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                  if (widget.video.qualities.length > 1)
                    TextButton(
                      onPressed: _pickQuality,
                      child: Text(
                        _quality?.label ?? '清晰度',
                        style: AppTextStyle.footnote.of(context).copyWith(
                          fontSize: 13,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: _saving ? null : _save,
                    tooltip: '保存视频',
                    icon: _saving
                        ? const ActivityIndicator(
                            size: 20,
                            color: Color(0xFFFFFFFF),
                          )
                        : const GlyphIcon(
                            HoboGlyphs.download,
                            size: 20,
                            color: Color(0xFFFFFFFF),
                          ),
                  ),
                  IconButton(
                    onPressed: () => openWeb(
                      context,
                      _url,
                      title: widget.video.title,
                    ),
                    tooltip: '用网页打开',
                    icon: const GlyphIcon(
                      HoboGlyphs.link,
                      size: 20,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Controls(
                controller: _controller!,
                onToggle: _toggle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _controller;
    if (controller == null) {
      if (_loading) {
        return const Center(
          child: ActivityIndicator(size: 28, color: Color(0xFFFFFFFF)),
        );
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? '视频加载失败',
                textAlign: TextAlign.center,
                style: AppTextStyle.footnote.of(context).copyWith(
                  color: const Color(0xFFFFFFFF),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => openWeb(
                  context,
                  _url,
                  title: widget.video.title,
                ),
                child: const Text('用网页打开'),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: GestureDetector(
        onTap: _toggle,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          // 播放状态要跟着控制器走：换清晰度后 play() 不会触发本页重建，
          // 不监听的话暂停图标会一直挂在那儿。
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, child) => Stack(
              fit: StackFit.expand,
              children: [
                child!,
                if (!value.isPlaying) const Center(child: _PlayOverlay()),
                if (_loading)
                  const Center(
                    child: ActivityIndicator(
                      size: 28,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
              ],
            ),
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _PlayOverlay extends StatelessWidget {
  const _PlayOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: const ShapeDecoration(
        color: Color(0x73000000),
        shape: AppShape.full,
      ),
      child: const Padding(
        padding: EdgeInsets.only(left: 4),
        child: GlyphIcon(HoboGlyphs.play, size: 26, color: Color(0xFFFFFFFF)),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onToggle});

  final VideoPlayerController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x99000000), Color(0x00000000)],
        ),
      ),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final duration = value.duration;
          final position = value.position;
          final total = duration.inMilliseconds;
          final progress = total <= 0
              ? 0.0
              : (position.inMilliseconds / total).clamp(0.0, 1.0);
          return Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                child: GlyphIcon(
                  value.isPlaying ? HoboGlyphs.play : HoboGlyphs.play,
                  size: 20,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _time(position),
                style: AppTextStyle.caption1.of(context).copyWith(
                  fontSize: 11,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final width = context.size?.width ?? 1;
                    final ratio = (details.localPosition.dx / width).clamp(
                      0.0,
                      1.0,
                    );
                    controller.seekTo(
                      Duration(milliseconds: (total * ratio).round()),
                    );
                  },
                  child: Container(
                    height: 4,
                    decoration: ShapeDecoration(
                      color: const Color(0x4DFFFFFF),
                      shape: AppShape.full,
                    ),
                    child: FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: progress == 0 ? 0.0001 : progress,
                      child: DecoratedBox(
                        decoration: const ShapeDecoration(
                          color: Color(0xFFFFFFFF),
                          shape: AppShape.full,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _time(duration),
                style: AppTextStyle.caption1.of(context).copyWith(
                  fontSize: 11,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _time(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
