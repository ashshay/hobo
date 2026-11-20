import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/settings.dart';
import 'glyphs.dart';

/// 轻提示：走 prism 的通知横幅，和系统通知同一套观感。
void showHoboToast(
  BuildContext context,
  String message, {
  BannerLevel level = BannerLevel.info,
}) {
  if (message.trim().isEmpty) return;
  BannerHost.maybeOf(context)?.show(message, level: level);
}

Future<bool?> showHoboConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool destructive = false,
}) {
  return showFloatingDialog<bool>(
    context: context,
    child: AlertDialog(
      title: title,
      destructive: destructive,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
      child: message == null
          ? null
          : Text(
              message,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
    ),
  );
}

Future<void> showHoboAlert(
  BuildContext context, {
  required String title,
  String? message,
}) async {
  await showFloatingDialog<void>(
    context: context,
    child: AlertDialog(
      title: title,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
      child: message == null ? null : Text(message),
    ),
  );
}

/// 一个输入框的弹窗，返回用户输入；取消返回 null。
Future<String?> showHoboInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  bool multiline = false,
  String confirmText = '确定',
}) {
  return showFloatingDialog<String>(
    context: context,
    child: _InputDialog(
      title: title,
      initial: initial,
      hint: hint,
      multiline: multiline,
      confirmText: confirmText,
    ),
  );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.multiline,
    required this.confirmText,
  });

  final String title;
  final String initial;
  final String hint;
  final bool multiline;
  final String confirmText;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.title,
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
      child: TextField(
        controller: _controller,
        autofocus: true,
        minLines: widget.multiline ? 3 : 1,
        maxLines: widget.multiline ? 6 : 1,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

/// 顶栏的毛玻璃底：内容从下面滚过时透出模糊的影子，而不是被整块底色盖住。
class HoboBlurBar extends StatelessWidget {
  const HoboBlurBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final tint = SurfaceLevel.page.colorOf(scheme);
    // 设置里的「模糊效果」就是给顶栏和玻璃面用的，关掉时退回实色。
    if (!context.select<Settings, bool>((settings) => settings.blurEffects)) {
      return ColoredBox(color: tint, child: child);
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: ColoredBox(
          color: tint.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.65 : 0.68,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// prism 的页内顶栏。`PrismScaffold.bar` 要的是 [PreferredSizeWidget]，
/// 而 prism 的 [AppBar] 只是普通组件，这里补上首选高度。
class HoboAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HoboAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.titleTextStyle,
    this.toolbarHeight,
    this.hidden = false,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget> actions;
  final TextStyle? titleTextStyle;
  final double? toolbarHeight;

  /// 滚动信息流时整条顶栏向上滑走。
  final bool hidden;

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? pageToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: hidden ? const Offset(0, -1) : Offset.zero,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      // 毛玻璃：列表滚到顶栏下面时只透出模糊的一层，和底栏是同一套观感。
      child: HoboBlurBar(
        child: AppBar(
          leading: leading,
          title: title,
          actions: actions,
          titleTextStyle: titleTextStyle,
          toolbarHeight: toolbarHeight,
          // 不裁掉自己，向上滑出的部分才不会被 ClipRect 截断。
          clipBehavior: Clip.none,
        ),
      ),
    );
  }
}

/// 页面骨架：浮动标题栏 + 内容。内容自己处理顶部留白（见 [pageTopInset]）。
class HoboPage extends StatelessWidget {
  const HoboPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.leading,
    this.titleTextStyle,
    this.foot,
    this.footActions,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.hidden = false,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? leading;
  final TextStyle? titleTextStyle;
  final Widget? foot;
  final Widget? footActions;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  /// 滚动内容时整条顶栏向上滑走，和首页信息流一致。
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return PrismScaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      bar: HoboAppBar(
        leading: leading,
        title: Text(title),
        titleTextStyle:
            titleTextStyle ??
            AppTextStyle.title3
                .of(context)
                .copyWith(
                  color: context.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
        actions: actions,
        hidden: hidden,
      ),
      body: body,
      foot: foot,
      footActions: footActions,
    );
  }
}

/// 返回按钮：和 prism 的页内导航一致的细箭头。
class HoboBackButton extends StatelessWidget {
  const HoboBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      tooltip: '返回',
      icon: const GlyphIcon(Glyphs.chevronBack, size: 26),
    );
  }
}

/// 副标题小按钮（顶栏右侧的「搜索」「更多」这类）。
class HoboBarAction extends StatelessWidget {
  const HoboBarAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: AppTextStyle.footnote
            .of(context)
            .copyWith(
              color: context.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 页面内容顶部留白：浮动标题栏的高度。
double pageTopInset(BuildContext context) => context.appBarInset + 8;

/// 滚动内容底部留白：避开悬浮底栏与系统手势条。
double pageBottomInset(BuildContext context) =>
    NavigationDock.insetOf(context) + 24;

/// 卡片的圆角，和 prism 的列表卡一致。
const hoboCardRadius = AppCorner.lg;

/// 卡片按下时缩到 98.5%：整卡够大，缩太多会显得在抖。
const hoboCardPressScale = 0.985;

/// 图片、视频这类整块内容按下时缩到 97%，比卡片明显一档。
const hoboMediaPressScale = 0.97;

/// 一张圆角卡片，可点。卡片内边距默认 16。
class HoboCard extends StatelessWidget {
  const HoboCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onPressed,
    this.onLongPress,
    this.fill,
    this.radius = hoboCardRadius,
    this.border,
    this.pressScale = hoboCardPressScale,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Color? fill;
  final double radius;
  final BorderSide? border;

  /// 按下时整张卡缩到多小。1 表示不动。
  final double pressScale;

  @override
  Widget build(BuildContext context) {
    final card = PressSurface(
      fill: fill ?? context.surfaceLevel.next.colorOf(context.colorScheme),
      shape: border == null
          ? AppShape.all(radius)
          : AppShape.all(radius).copyWith(side: border!),
      padding: padding,
      pressScale: pressScale,
      onPressed: onPressed,
      child: child,
    );
    if (onLongPress == null) return card;
    return GestureDetector(
      onLongPress: () {
        Feedback.forLongPress(context);
        onLongPress!();
      },
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}

/// 一行「标题 + 副标题 + 右侧箭头/开关」的设置项。
class HoboRow extends StatelessWidget {
  const HoboRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onPressed,
    this.showChevron = false,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool showChevron;
  final bool danger;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? context.colorScheme.error
        : context.colorScheme.onSurface;
    return PressSurface(
      fill: const Color(0x00000000),
      shape: AppShape.none,
      padding: padding,
      onPressed: onPressed,
      child: Row(
        children: [
          if (leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(
                color: danger
                    ? context.colorScheme.error
                    : context.colorScheme.primary,
                size: 22,
              ),
              child: leading!,
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTextStyle.body.of(context).copyWith(color: color),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (showChevron)
            GlyphIcon(
              Glyphs.chevronForward,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

/// 一组设置项：卡片 + 分隔线。
class HoboSection extends StatelessWidget {
  const HoboSection({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const _Hairline());
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 16, 8),
            child: Text(
              title!,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: ShapeDecoration(
            color: context.surfaceLevel.next.colorOf(context.colorScheme),
            shape: AppShape.all(hoboCardRadius),
          ),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(hoboCardRadius),
            child: Column(children: rows),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            child: Text(
              footer!,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// 空态 / 错误态。
class HoboEmpty extends StatelessWidget {
  const HoboEmpty({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.icon = HoboGlyphs.list,
  });

  final String title;
  final String? message;
  final Widget? action;
  final Glyph icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(
              icon,
              size: 44,
              color: context.colorScheme.onSurfaceVariant.withValues(
                alpha: 0.5,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyle.headline
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurface),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// 首屏加载。
class HoboLoading extends StatelessWidget {
  const HoboLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ActivityIndicator(size: 24),
          if (label != null) ...[
            const SizedBox(height: 10),
            Text(
              label!,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 列表底部「正在加载更多 / 到底了」。
class HoboListFooter extends StatelessWidget {
  const HoboListFooter({super.key, required this.loading, required this.atEnd});

  final bool loading;
  final bool atEnd;

  @override
  Widget build(BuildContext context) {
    if (!loading && !atEnd) return const SizedBox(height: 24);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: loading
            ? const ActivityIndicator(size: 18)
            : Text(
                '没有更多了',
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
      ),
    );
  }
}

/// 底部弹层的内容：`SingleChildScrollView` + 高度收缩的 Column。
class HoboSheetBody extends StatelessWidget {
  const HoboSheetBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        pageTopInset(context),
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 一个选项。
class HoboChoice<T> {
  const HoboChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
    this.selected = false,
  });

  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
}

/// 选择一项：浮动对话框里的选项卡。返回选中的值，取消返回 null。
///
/// 这里刻意用 `showFloatingDialog` 而不是 `showSheet`：prism 的 SnapSheet 在内容比
/// 初始 detent 高时会停在「hold」状态，整块内容不接收点击（表现为点了没反应）。
Future<T?> showHoboChoices<T>(
  BuildContext context, {
  required String title,
  required List<HoboChoice<T>> choices,
  String cancelText = '取消',
}) {
  return showFloatingDialog<T>(
    context: context,
    child: _ChoiceCard<T>(
      title: title,
      choices: choices,
      cancelText: cancelText,
    ),
  );
}

class _ChoiceCard<T> extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.choices,
    required this.cancelText,
  });

  final String title;
  final List<HoboChoice<T>> choices;
  final String cancelText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: title,
      showRim: false,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(cancelText),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          minWidth: 240,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final choice in choices)
                HoboRow(
                  title: choice.label,
                  subtitle: choice.subtitle,
                  leading: choice.leading,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  trailing: choice.selected
                      ? GlyphIcon(
                          HoboGlyphs.check,
                          size: 18,
                          color: context.colorScheme.primary,
                        )
                      : null,
                  onPressed: () => Navigator.of(context).pop(choice.value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 动作菜单：一组「文字 → 动作」，点完自动收起。
Future<void> showHoboActionSheet(
  BuildContext context, {
  required String title,
  required List<(String, VoidCallback)> actions,
}) async {
  final index = await showHoboChoices<int>(
    context,
    title: title,
    choices: [
      for (final (i, action) in actions.indexed)
        HoboChoice(value: i, label: action.$1),
    ],
  );
  if (index == null || index < 0 || index >= actions.length) return;
  actions[index].$2();
}

/// 把一次异步操作的异常统一转成 banner，避免每条调用都写一遍 try/catch。
Future<void> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  void Function(Object error)? onError,
}) async {
  try {
    await action();
  } on Object catch (error) {
    final message = error.toString();
    if (!context.mounted) return;
    onError?.call(error);
    showHoboToast(
      context,
      message.isEmpty ? '操作失败' : message,
      level: BannerLevel.error,
    );
  }
}

/// 延时弹出的轻提示，避免在 build 里直接开 banner。
void scheduleToast(
  BuildContext context,
  String message, {
  BannerLevel level = BannerLevel.info,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    showHoboToast(context, message, level: level);
  });
}

/// 0.5dp 的分隔线：prism 的 Divider 没有 color 参数，这里自己画一条。
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 16),
      color: context.colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}
