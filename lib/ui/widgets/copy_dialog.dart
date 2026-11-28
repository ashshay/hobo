import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'common.dart';

/// 「复制」面板：先把全文摆出来（可长按自由选取），再由用户点「复制全部」。
///
/// 一点就整段进剪贴板的话，想只取其中一句就没法回头了；先看一眼再决定复制什么，
/// 与 TiebaFrosted 对这个入口的处理保持一致。
Future<void> showHoboCopyDialog(BuildContext context, String text) async {
  final content = text.trim();
  if (content.isEmpty) {
    showHoboToast(context, '这里没有可复制的文字');
    return;
  }
  final copied = await showFloatingDialog<bool>(
    context: context,
    child: AlertDialog(
      title: '复制',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: content));
            if (context.mounted) Navigator.of(context).pop(true);
          },
          child: const Text('复制全部'),
        ),
      ],
      child: _CopyTextBody(content: content),
    ),
  );
  if (copied == true && context.mounted) {
    HapticFeedback.selectionClick();
    showHoboToast(context, '已复制到剪贴板');
  }
}

/// 面板正文：给够高度与宽度，长按选中一句后拖两端手柄可以扩大范围。
///
/// 弹窗默认按内容宽度收窄（`IntrinsicWidth`），正文一行只有几十个字时选框很难拖，
/// 所以这里显式撑开一块选区，滚动交给内层。
class _CopyTextBody extends StatelessWidget {
  const _CopyTextBody({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 96).clamp(240.0, 420.0);
    final height = (screen.height * 0.45).clamp(180.0, 420.0);
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '长按正文选中一段，拖两端手柄扩大范围',
            style: AppTextStyle.footnote
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                child: Text(
                  content,
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: scheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
