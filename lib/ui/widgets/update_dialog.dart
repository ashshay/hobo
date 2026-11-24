import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/system_browser.dart';
import '../../data/update.dart';
import '../routes.dart';

/// 更新提示弹窗的返回结果。
class UpdateDialogResult {
  const UpdateDialogResult({
    required this.update,
    required this.dontRemind,
  });

  /// 用户点击了「立即更新」。
  final bool update;

  /// 用户勾选了「此版本不再提醒」。
  final bool dontRemind;
}

/// 跳转到 GitHub 最新 Release 页面：优先调系统浏览器，找不到浏览器时回退到内置网页。
Future<void> openReleasePage(BuildContext context, [UpdateInfo? info]) async {
  final target = info?.targetReleaseUrl ?? Updater.latestReleasePage;
  final opened = await SystemBrowser.open(target);
  if (!opened && context.mounted) {
    openWeb(context, target, title: 'Hobo 更新');
  }
}

/// 发现新版本时的首页提示弹窗：展示版本号、更新说明、可选「此版本不再提醒」勾选框，
/// 点「立即更新」后由调用方跳转到 GitHub 最新 Release 页面。
Future<UpdateDialogResult> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  String currentVersion = '',
  bool showDontRemind = true,
}) async {
  var dontRemind = false;
  final result = await showFloatingDialog<UpdateDialogResult>(
    context: context,
    child: _UpdateDialog(
      info: info,
      currentVersion: currentVersion,
      showDontRemind: showDontRemind,
      onDontRemindChanged: (value) => dontRemind = value,
    ),
  );
  // 点背景蒙层或按返回键关闭弹窗时（result == null），依然保留用户勾选的「不再提醒」。
  return result ?? UpdateDialogResult(update: false, dontRemind: dontRemind);
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.info,
    required this.currentVersion,
    required this.showDontRemind,
    required this.onDontRemindChanged,
  });

  final UpdateInfo info;
  final String currentVersion;
  final bool showDontRemind;
  final ValueChanged<bool> onDontRemindChanged;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _dontRemind = false;

  void _toggleDontRemind() {
    final next = !_dontRemind;
    setState(() => _dontRemind = next);
    widget.onDontRemindChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final notes = Updater.plainReleaseNotes(widget.info.notes);
    final meta = [
      if (widget.currentVersion.isNotEmpty) '当前版本 v${widget.currentVersion}',
      if (widget.info.sizeLabel.isNotEmpty) '安装包 ${widget.info.sizeLabel}',
    ].join(' · ');

    return AlertDialog(
      title: '发现新版本 v${widget.info.version}',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            UpdateDialogResult(update: false, dontRemind: _dontRemind),
          ),
          child: const Text('稍后'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            UpdateDialogResult(update: true, dontRemind: _dontRemind),
          ),
          child: const Text('立即更新'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (meta.isNotEmpty)
              Text(
                meta,
                style: AppTextStyle.caption1.of(context).copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(
                  notes.isNotEmpty
                      ? notes
                      : '已发布新版本，可前往 GitHub 查看更新说明并下载最新安装包。',
                  style: AppTextStyle.footnote.of(context).copyWith(
                    color: scheme.onSurface,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            if (widget.showDontRemind) ...[
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleDontRemind,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _dontRemind,
                        onChanged: (_) => _toggleDontRemind(),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '此版本不再提醒',
                        style: AppTextStyle.footnote.of(context).copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
