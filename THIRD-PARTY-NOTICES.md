# 第三方组件与许可

Hobo 本身以 **GNU General Public License v3.0** 发布（见 [`LICENSE`](LICENSE)）。
之所以是 GPL-3.0 而不是随便挑一个宽松协议：项目的界面层直接链接了 FlClash 仓库里的
`prism_ui`，而 `prism_ui` 是 GPL-3.0。把 GPL 代码静态编译进安装包再分发，
整个组合作品就得按 GPL-3.0 走。

## 直接依赖

| 组件 | 版本 | 许可 | 说明 |
| --- | --- | --- | --- |
| [`prism_ui`](https://github.com/chen08209/prism_ui) | path: `FlClash/plugins/prism_ui` 0.1.2 | **GPL-3.0** | 底栏 / 卡片 / 弹层 / 转场 / 按钮，来自 FlClash |
| [`dynamic_color`](https://pub.dev/packages/dynamic_color) | path: `FlClash/plugins/dynamic_color` | **Apache-2.0** | Android 12+ 壁纸取色（Monet），来自 FlClash |
| [dio](https://pub.dev/packages/dio) | ^5.11.1 | MIT | HTTP 客户端 |
| [provider](https://pub.dev/packages/provider) | ^6.1.5 | MIT | 状态注入 |
| [webview_flutter](https://pub.dev/packages/webview_flutter) | ^4.14.1 | BSD-3-Clause | 登录与内置网页 |
| [video_player](https://pub.dev/packages/video_player) | ^2.11.1 | BSD-3-Clause | 微博视频播放 |
| [image_picker](https://pub.dev/packages/image_picker) | ^1.2.4 | Apache-2.0 | 发布时选图 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | ^2.5.6 | BSD-3-Clause | 设置 / 会话落盘 |
| [path_provider](https://pub.dev/packages/path_provider) | ^2.1.6 | BSD-3-Clause | 应用私有目录 |
| [package_info_plus](https://pub.dev/packages/package_info_plus) | ^10.2.2 | BSD-3-Clause | 读 versionCode |
| [crypto](https://pub.dev/packages/crypto) | ^3.0.7 | BSD-3-Clause | XSRF / 摘要 |
| [path](https://pub.dev/packages/path) | ^1.9.1 | BSD-3-Clause | 路径拼接 |

传递依赖同样是宽松许可（BSD / MIT / Apache-2.0），完整清单见 `pubspec.lock`。

## 资源

- **应用图标**：IconKitchen 导出的方图（`assets/icon/`），`tool/make_icons.py` 生成各密度位图。
- **图标路径**：`lib/ui/widgets/glyphs.dart` 里的矢量路径取自
  [Material Icons](https://fonts.google.com/icons)，**Apache-2.0**。
- **赞赏码**：`assets/donate/donate_qr.png`，仓库作者自备。

## 与 FlClash 的关系

Hobo 只**读取**（path 依赖）FlClash 仓库里的两个 Flutter 插件，不修改 FlClash 本体，
也不包含 Clash / mihomo 的任何内核代码。给 FlClash 提改动请走
<https://github.com/chen08209/FlClash>。
