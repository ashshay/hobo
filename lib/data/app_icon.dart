/// 桌面图标的形状：跟 Kotlin 侧的 `hobo/icon` 通道通信。
///
/// Android 8+ 的自适应图标由启动器套遮罩，应用改不了形状，所以这里不是改 adaptive-icon，
/// 而是：两套已经画好形状的位图分别挂在 `.IconRounded` / `.IconCircle` 两个 activity-alias
/// 上，同一时刻只启用一个。换形状 = 换桌面入口，图标像素完全由 App 决定。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// 非 Android 平台或通道不可用（跑测试、跑桌面）时全部安静地返回 null，不抛异常。
abstract final class AppIcon {
  static const _channel = MethodChannel('hobo/icon');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 桌面现在实际生效的形状。
  static Future<AppIconShape?> current() async {
    if (!_supported) return null;
    try {
      final raw = await _channel.invokeMethod<String>('currentShape');
      return raw == null ? null : AppIconShape.fromKey(raw);
    } on Object {
      return null;
    }
  }

  /// 切到 [shape]，返回切换后实际生效的形状；失败返回 null。
  static Future<AppIconShape?> apply(AppIconShape shape) async {
    if (!_supported) return null;
    try {
      final raw = await _channel.invokeMethod<String>('applyShape', {
        'shape': shape.key,
      });
      return AppIconShape.fromKey(raw, shape);
    } on Object {
      return null;
    }
  }

  /// 冷启动对齐：设置存的和桌面实际生效的可能是两个（清过应用数据、或用 `flutter run`
  /// 重装过一个别的形状）。一致时什么都不做，不惊动桌面。
  static Future<void> sync(AppIconShape shape) async {
    final actual = await current();
    if (actual == null || actual == shape) return;
    await apply(shape);
  }
}
