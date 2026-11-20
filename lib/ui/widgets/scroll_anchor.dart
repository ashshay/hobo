import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 列表续看位置：第一条可见项的序号，以及它被顶栏遮掉了多少像素。
///
/// `ListView` 没有 `scrollToItem`，所以冷启动恢复位置时先按平均卡片高度估一个
/// 偏移，再按实际渲染出来的子项修正几轮，卡片高矮差得再多也能落到那一张上。
({int index, double offset})? firstVisibleAnchor(
  ScrollController controller, {
  double paddingTop = 0,
}) {
  if (!controller.hasClients || controller.positions.length != 1) return null;
  final sliver = _sliverOf(controller);
  if (sliver == null) return null;
  final pixels = controller.position.pixels;
  for (
    var child = sliver.firstChild;
    child != null;
    child = sliver.childAfter(child)
  ) {
    final data = child.parentData;
    if (data is! SliverMultiBoxAdaptorParentData) continue;
    final index = data.index;
    final layoutOffset = data.layoutOffset;
    if (index == null || layoutOffset == null) continue;
    if (paddingTop + layoutOffset + child.size.height > pixels + 0.5) {
      return (
        index: index,
        offset: (pixels - layoutOffset).clamp(0.0, double.infinity),
      );
    }
  }
  return null;
}

/// 把列表滚到第 [index] 项、项内偏移 [offset]。
Future<void> restoreScrollTo(
  ScrollController controller,
  int index,
  double offset, {
  double estimatedItemHeight = 320,
}) async {
  if (!controller.hasClients) {
    // 列表可能还没挂上（首帧还在加载态），等一帧再试一次。
    await WidgetsBinding.instance.endOfFrame;
    if (!controller.hasClients) return;
  }
  if (controller.positions.length != 1) return;
  final position = controller.position;
  double clamp(double value) => value.clamp(0.0, position.maxScrollExtent);

  controller.jumpTo(clamp(index * estimatedItemHeight + offset));
  for (var pass = 0; pass < 4; pass++) {
    await WidgetsBinding.instance.endOfFrame;
    if (!controller.hasClients) return;
    final sliver = _sliverOf(controller);
    if (sliver == null) return;
    final range = _visibleRange(sliver);
    if (range == null) return;
    final (first, last) = range;
    double target;
    if (index < first) {
      target = clamp(controller.offset - (first - index) * estimatedItemHeight);
    } else if (index > last) {
      target = clamp(controller.offset + (index - last) * estimatedItemHeight);
    } else {
      final layoutOffset = _layoutOffsetOf(sliver, index);
      if (layoutOffset == null) return;
      target = clamp(layoutOffset + offset);
    }
    if ((target - controller.offset).abs() < 1) return;
    controller.jumpTo(target);
  }
}

RenderSliverMultiBoxAdaptor? _sliverOf(ScrollController controller) {
  final root = controller.position.context.storageContext.findRenderObject();
  if (root == null) return null;
  RenderSliverMultiBoxAdaptor? found;
  void visit(RenderObject node) {
    if (found != null) return;
    if (node is RenderSliverMultiBoxAdaptor) {
      found = node;
      return;
    }
    node.visitChildren(visit);
  }

  visit(root);
  return found;
}

(int, int)? _visibleRange(RenderSliverMultiBoxAdaptor sliver) {
  int? first;
  int? last;
  for (
    var child = sliver.firstChild;
    child != null;
    child = sliver.childAfter(child)
  ) {
    final data = child.parentData;
    if (data is! SliverMultiBoxAdaptorParentData) continue;
    final index = data.index;
    if (index == null) continue;
    first ??= index;
    last = index;
  }
  if (first == null || last == null) return null;
  return (first, last);
}

double? _layoutOffsetOf(RenderSliverMultiBoxAdaptor sliver, int index) {
  for (
    var child = sliver.firstChild;
    child != null;
    child = sliver.childAfter(child)
  ) {
    final data = child.parentData;
    if (data is! SliverMultiBoxAdaptorParentData) continue;
    if (data.index == index) return data.layoutOffset;
  }
  return null;
}
