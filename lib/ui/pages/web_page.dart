import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/cookie_vault.dart';
import '../../data/repo.dart';
import '../../data/system_browser.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';

/// 应用内网页：站内链接不进系统浏览器，并把本机登录态补进 WebView。
///
/// 顶栏右侧的「用浏览器打开」把当前地址交给系统浏览器，用来应付那些
/// 只能在浏览器里跑完的流程（第三方登录、支付、要求装 App 的下载页）。
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.url, this.title = '网页'});

  final String url;
  final String title;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  WebViewController? _controller;
  int _progress = 0;
  String _title = '';

  /// 用户点到的那个地址。内置网页会自己跳转，复制链接和「用浏览器打开」都得用它，
  /// 不能用 widget.url —— 那是入口，不是当前页。
  late String _currentUrl = widget.url;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
  }

  Future<void> _setup() async {
    final repo = context.read<Repo>();
    final cookies = repo.session?.cookies ?? const <String, String>{};
    if (cookies.isNotEmpty) await CookieVault.plant(cookies);
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13; MI 9) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        );
      controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url == null || url.isEmpty || !mounted) return;
            setState(() => _currentUrl = url);
          },
          onPageFinished: (url) async {
            final title = await controller.getTitle() ?? '';
            if (mounted) {
              setState(() {
                _title = title;
                if (url.isNotEmpty) _currentUrl = url;
              });
            }
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _error = error.description);
          },
        ),
      );
      await controller.loadRequest(Uri.parse(widget.url));
      if (!mounted) return;
      setState(() => _controller = controller);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _openInBrowser() async {
    final opened = await SystemBrowser.open(_currentUrl);
    if (!mounted) return;
    if (!opened) {
      showHoboToast(context, '没有找到可用的浏览器', level: BannerLevel.error);
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _currentUrl));
    if (mounted) showHoboToast(context, '链接已复制');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return HoboPage(
      title: _title.isNotEmpty ? _title : widget.title,
      leading: const HoboBackButton(),
      actions: [
        IconButton(
          onPressed: _copyLink,
          tooltip: '复制链接',
          icon: const GlyphIcon(HoboGlyphs.link, size: 20),
        ),
        IconButton(
          onPressed: controller == null ? null : _openInBrowser,
          tooltip: '用浏览器打开',
          icon: const GlyphIcon(HoboGlyphs.openExternal, size: 20),
        ),
        IconButton(
          onPressed: () => controller?.reload(),
          tooltip: '刷新',
          icon: const GlyphIcon(HoboGlyphs.refresh, size: 20),
        ),
      ],
      body: Stack(
        children: [
          if (controller != null)
            Positioned.fill(child: WebViewWidget(controller: controller))
          else if (_error != null)
            Positioned.fill(
              child: HoboEmpty(
                title: '网页打不开',
                message: _error,
                action: TextButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _setup();
                  },
                  child: const Text('重试'),
                ),
              ),
            )
          else
            const Positioned.fill(
              child: HoboLoading(label: '正在加载网页…'),
            ),
          if (_progress > 0 && _progress < 100)
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.paddingOf(context).top + pageToolbarHeight - 2,
              child: LinearProgressIndicator(value: _progress / 100),
            ),
        ],
      ),
    );
  }
}
