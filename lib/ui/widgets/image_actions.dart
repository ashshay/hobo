import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/media_saver.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../nav.dart';
import '../pages/image_viewer_page.dart';
import 'common.dart';

/// 卡片上长按缩略图：看原图 / 存到相册 / 复制链接。
///
/// 单放在这里而不是 `routes.dart`，是因为信息流、评论、卡片都要用，
/// 而 `routes.dart` 已经反向依赖了这些 widget。
Future<void> showImageActions(
  BuildContext context, {
  required List<Pic> pics,
  required int index,
}) async {
  if (pics.isEmpty) return;
  final safe = index.clamp(0, pics.length - 1);
  final pic = pics[safe];
  final url = pic.large.isNotEmpty ? pic.large : pic.thumb;
  if (url.isEmpty) return;
  await showHoboActionSheet(
    context,
    title: pics.length > 1 ? '图片 ${safe + 1}/${pics.length}' : '图片',
    actions: [
      ('查看原图', () => openImageViewer(context, pics, safe)),
      ('保存图片', () => saveImageToGallery(context, url)),
      ('复制图片链接', () => copyImageLink(context, url)),
    ],
  );
}

/// 打开看图页（和头条的 `openImages` 同一个页面，绕过 routes 的反向依赖）。
void openImageViewer(BuildContext context, List<Pic> pics, int index) {
  if (pics.isEmpty) return;
  pushPage(
    context,
    ImageViewerPage(
      pics: pics,
      initialIndex: index.clamp(0, pics.length - 1),
    ),
  );
}

/// 下载原图并写进系统相册。
Future<void> saveImageToGallery(BuildContext context, String url) async {
  if (url.isEmpty) return;
  final repo = context.read<Repo>();
  final messenger = context;
  showHoboToast(context, '正在保存…');
  try {
    await MediaSaver.saveImage(url, cookie: repo.cookie());
    if (messenger.mounted) showHoboToast(messenger, '已保存到相册');
  } on Object catch (e) {
    if (messenger.mounted) {
      showHoboToast(messenger, '保存失败：$e', level: BannerLevel.error);
    }
  }
}

void copyImageLink(BuildContext context, String url) {
  Clipboard.setData(ClipboardData(text: url));
  showHoboToast(context, '图片链接已复制');
}
