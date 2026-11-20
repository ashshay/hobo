import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/media_saver.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';
import '../widgets/status_card.dart' show picHeroTag;

/// 看图：左右翻页 + 双指缩放 + 双击放大 / 复原。
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

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_applyZoom);
  }

  @override
  void dispose() {
    _zoomController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
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

  /// 保存当前这张图到系统相册。
  Future<void> _saveCurrent() async {
    if (_saving) return;
    final pic = widget.pics[_index];
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

  /// 长按图片：存到相册 / 复制链接。
  Future<void> _showActions(int index) async {
    final pic = widget.pics[index.clamp(0, widget.pics.length - 1)];
    final url = pic.large.isNotEmpty ? pic.large : pic.thumb;
    await showHoboActionSheet(
      context,
      title: widget.pics.length > 1
          ? '图片 ${index + 1}/${widget.pics.length}'
          : '图片',
      actions: [
        ('保存图片', _saveCurrent),
        (
          '复制图片链接',
          () {
            Clipboard.setData(ClipboardData(text: url));
            showHoboToast(context, '图片链接已复制');
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.pics.length,
              onPageChanged: (index) {
                if (index != _index) setState(() => _index = index);
              },
              itemBuilder: (context, index) {
                final pic = widget.pics[index];
                final original =
                    context.read<Settings>().imageBrowseQuality ==
                    ImageBrowseQuality.original;
                final url = original && pic.large.isNotEmpty
                    ? pic.large
                    : (pic.large.isNotEmpty ? pic.large : pic.thumb);
                return GestureDetector(
                  onTap: () => setState(() => _chrome = !_chrome),
                  onLongPress: () => _showActions(index),
                  onDoubleTapDown: (details) => _onDoubleTap(index, details),
                  onDoubleTap: () {},
                  child: InteractiveViewer(
                    transformationController: _controllerFor(index),
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(
                      child: Hero(
                        tag: picHeroTag(pic),
                        child: RemoteImage(
                          url: url,
                          fit: BoxFit.contain,
                          placeholderColor: const Color(0xFF111111),
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                );
              },
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
                pic: widget.pics[_index],
                saving: _saving,
                onSave: _saveCurrent,
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
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.total,
    required this.pic,
    required this.saving,
    required this.onSave,
  });

  final int index;
  final int total;
  final Pic pic;
  final bool saving;
  final VoidCallback onSave;

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
            tooltip: '保存图片',
          ),
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
