import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// 统一的页面推入方式：prism 的卡片转场（跟手返回、背景模糊都在里面）。
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    CardPageRoute<T>(builder: (_) => page),
  );
}

/// 打开一个底部弹层。
Future<T?> openSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showSheet<T>(context: context, builder: builder);

/// 弹一个浮层对话框。
Future<T?> openDialog<T>(BuildContext context, Widget child) =>
    showFloatingDialog<T>(context: context, child: child);
