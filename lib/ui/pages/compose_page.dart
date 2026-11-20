import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/composer_models.dart';
import '../../data/repo.dart';
import '../../data/store.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';

/// 发布微博：文字 + 最多 9 张图 + 可见范围，退出时存草稿。
class ComposePage extends StatefulWidget {
  const ComposePage({super.key, this.initialText = ''});

  final String initialText;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );
  final List<XFile> _images = [];
  final List<Uint8List> _previews = [];
  WeiboVisibility _visibility = WeiboVisibility.public;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_images.length >= 9) return;
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 88,
        maxWidth: 2048,
        limit: 9 - _images.length,
      );
      for (final file in picked) {
        if (_images.length >= 9) break;
        final bytes = await file.readAsBytes();
        _images.add(file);
        _previews.add(bytes);
      }
      if (mounted) setState(() {});
    } on Object catch (e) {
      if (mounted) {
        showHoboToast(context, e.toString(), level: BannerLevel.error);
      }
    }
  }

  Future<void> _publish() async {
    final text = _text.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      showHoboToast(context, '写点什么再发吧');
      return;
    }
    final repo = context.read<Repo>();
    if (!repo.hasSession()) {
      showHoboToast(context, '纯本地模式不能发微博，登录后可用', level: BannerLevel.warning);
      return;
    }
    setState(() => _publishing = true);
    try {
      final picIds = <String>[];
      for (var i = 0; i < _images.length; i++) {
        if (mounted) {
          showHoboToast(
            context,
            '正在上传图片 ${i + 1}/${_images.length}…',
          );
        }
        picIds.add(
          await repo.uploadImage(
            _previews[i],
            mime: _images[i].mimeType ?? 'image/jpeg',
          ),
        );
      }
      await repo.publish(
        text,
        picIds,
        visible: _visibility.code,
      );
      if (!mounted) return;
      context.read<Store>().removeDraft(0);
      Navigator.of(context).pop(true);
      showHoboToast(context, '已发布');
    } on Object catch (e) {
      if (!mounted) return;
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<bool> _onBack() async {
    final text = _text.text.trim();
    if (text.isEmpty && _images.isEmpty) return true;
    final keep = await showHoboConfirm(
      context,
      title: '保存草稿？',
      message: '没有发布的内容可以存进草稿箱',
      confirmText: '存草稿',
      cancelText: '不保存',
    );
    if (keep == true) {
      context.read<Store>().addDraft(text);
      if (mounted) showHoboToast(context, '已存为草稿');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBack();
        if (mounted) Navigator.of(context).pop();
      },
      child: HoboPage(
        title: '发微博',
        leading: HoboBackButton(
          onPressed: () async {
            await _onBack();
            if (mounted) Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            onPressed: _publishing ? null : _publish,
            tooltip: '发布',
            icon: _publishing
                ? const ActivityIndicator(size: 18)
                : const GlyphIcon(HoboGlyphs.send, size: 22),
          ),
        ],
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 24),
          children: [
            HoboCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _text,
                    autofocus: true,
                    minLines: 6,
                    maxLines: 20,
                    decoration: const InputDecoration(
                      hintText: '分享新鲜事…',
                      isCollapsed: true,
                    ),
                    style: AppTextStyle.body.of(context).copyWith(
                      fontSize: 16,
                      height: 1.5,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  if (_previews.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ImageGrid(
                      previews: _previews,
                      onRemove: (index) {
                        setState(() {
                          _images.removeAt(index);
                          _previews.removeAt(index);
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _pickImages,
                        tooltip: '添加图片',
                        icon: const GlyphIcon(HoboGlyphs.image, size: 22),
                      ),
                      Text(
                        '${_images.length}/9',
                        style: AppTextStyle.caption1.of(context).copyWith(
                          fontSize: 12,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_text.text.length}',
                        style: AppTextStyle.caption1.of(context).copyWith(
                          fontSize: 12,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            HoboSection(
              title: '谁能看',
              children: [
                for (final visibility in WeiboVisibility.values)
                  HoboRow(
                    title: visibility.label,
                    subtitle: visibility.summary,
                    trailing: visibility == _visibility
                        ? GlyphIcon(
                            HoboGlyphs.check,
                            size: 20,
                            color: context.colorScheme.primary,
                          )
                        : null,
                    onPressed: () => setState(() => _visibility = visibility),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '发表即表示同意微博社区公约。图片会先上传到微博图床再随正文提交。',
                style: AppTextStyle.caption1.of(context).copyWith(
                  fontSize: 11,
                  height: 1.5,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中的图片：三列预览，右上角可以删。
class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.previews, required this.onRemove});

  final List<Uint8List> previews;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: previews.length,
      itemBuilder: (context, index) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRSuperellipse(
              borderRadius: BorderRadius.circular(AppCorner.sm),
              child: Image.memory(previews[index], fit: BoxFit.cover),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const ShapeDecoration(
                    color: Color(0xB3000000),
                    shape: AppShape.full,
                  ),
                  child: const GlyphIcon(
                    Glyphs.close,
                    size: 12,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
