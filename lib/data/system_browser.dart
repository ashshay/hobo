/// 把链接交给系统浏览器。
///
/// 内置 WebView 适合读微博自己的页面，但有些流程只在系统浏览器里跑得通
/// （第三方登录、支付、需要装 App 的下载页），也有些人就是想用带广告拦截的那一个。
/// 所以这里不自己起 WebView，直接发 `Intent.ACTION_VIEW`，由系统挑默认浏览器。
///
/// 走原生 `hobo/browser` 通道而不是加一个 url_launcher 依赖：整个项目只有这一处要跳出去，
/// 通道里三行 `startActivity` 就够了，也省得再跟一个新包版本。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class SystemBrowser {
  static const _channel = MethodChannel('hobo/browser');

  /// 非 Android 平台（跑测试、跑桌面）直接当「打不开」处理，不抛异常。
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 用系统浏览器打开 [url]。成功交出去返回 true；
  /// 设备上没有能处理 http/https 的应用（少见，但模拟器的精简镜像里会有）返回 false。
  static Future<bool> open(String url) async {
    final target = url.trim();
    if (target.isEmpty) return false;
    if (!_supported) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openUrl', {
        'url': target,
      });
      return opened ?? false;
    } on Object {
      return false;
    }
  }
}
