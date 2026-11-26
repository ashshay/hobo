import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/cookie_vault.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';

/// 网页登录。登录页与 App 共用系统 CookieManager：登录完成后把整表读出来落盘。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.addAccount = false, this.webSlotBuilder});

  final bool addAccount;

  /// 测试钩子：替换 WebView 槽位以验证布局边界，不触发平台 WebView 初始化。
  @visibleForTesting
  final WidgetBuilder? webSlotBuilder;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const _loginUrl = 'https://passport.weibo.cn/signin/login?entry=mweibo';

  WebViewController? _web;
  bool _checking = false;
  bool _ready = false;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.webSlotBuilder == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setup());
    }
  }

  Future<void> _setup() async {
    final repo = context.read<Repo>();
    // 站内 WebView 与 App 用同一份登录态：先把已有的 cookie 补进系统 CookieManager。
    final existing = repo.session?.cookies ?? const <String, String>{};
    if (existing.isNotEmpty) await CookieVault.plant(existing);
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; MI 9) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageFinished: (url) {
            if (mounted && _progress < 100) {
              setState(() => _progress = 100);
            }
            if (url.contains('m.weibo.cn') && !url.contains('passport')) {
              _tryLogin(silent: true);
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _error = error.description);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
    if (!mounted) return;
    setState(() {
      _web = controller;
      _ready = true;
    });
  }

  Future<void> _tryLogin({bool silent = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      final domains = await CookieVault.readDomains();
      final cookie = CookieVault.authHeader(domains, 'm.weibo.cn');
      if (!cookie.contains('SUB=')) {
        if (!silent && mounted) {
          showHoboToast(context, '还没有拿到登录 Cookie，请先在网页里完成登录');
        }
        return;
      }
      final repo = context.read<Repo>();
      final account = await repo.loginWithCookie(cookie, cookies: domains);
      if (!mounted) return;
      if (account == null) {
        if (!silent) {
          showHoboToast(context, '登录状态无效，请重试', level: BannerLevel.error);
        }
        return;
      }
      context.read<Settings>().applyLocalMode(false);
      showHoboToast(context, '登录成功：${account.name}');
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      if (!silent) {
        showHoboToast(context, e.toString(), level: BannerLevel.error);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _manualCookie() async {
    final text = await showHoboInputDialog(
      context,
      title: '粘贴 Cookie',
      hint: '从浏览器里复制整段 Cookie',
      multiline: true,
      confirmText: '登录',
    );
    if (text == null || text.isEmpty || !mounted) return;
    await runGuarded(context, () async {
      final repo = context.read<Repo>();
      final account = await repo.loginWithCookie(text.trim());
      if (!mounted) return;
      if (account == null) {
        showHoboToast(context, 'Cookie 无效或已过期', level: BannerLevel.error);
        return;
      }
      context.read<Settings>().applyLocalMode(false);
      showHoboToast(context, '登录成功：${account.name}');
      Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    final scheme = context.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return HoboPage(
      title: widget.addAccount ? '添加账号' : '登录',
      leading: HoboBackButton(
        onPressed: () {
          Navigator.of(context).pop(false);
          context.read<Settings>().applyLocalMode(true);
        },
      ),
      actions: [
        HoboBarAction(label: '完成', onPressed: _checking ? null : _tryLogin),
      ],
      // `HoboPage` 的顶栏浮在 body 上方：WebView 必须让出 `appBarInset`，
      // 否则微博登录页顶部的「切换登录方式 / 账号密码 / 短信」栏会被顶栏完全挡住。
      // 底部按钮同样改为独立底栏而非浮在网页上方，避免盖住网页底部的登录方式入口。
      body: AppBarClearance(
        child: Column(
          children: [
            if (_progress > 0 && _progress < 100)
              LinearProgressIndicator(value: _progress / 100),
            Expanded(
              child: Stack(
                children: [
                  if (widget.webSlotBuilder != null)
                    Positioned.fill(
                      child: Builder(builder: widget.webSlotBuilder!),
                    )
                  else if (web != null)
                    Positioned.fill(child: WebViewWidget(controller: web))
                  else if (_ready)
                    const Center(child: ActivityIndicator(size: 24))
                  else
                    const HoboLoading(label: '正在打开登录页…'),
                  if (_error != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.surface,
                        child: HoboEmpty(
                          title: '登录页打不开',
                          message: _error,
                          action: TextButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _web?.reload();
                            },
                            child: const Text('重试'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 10, 16, bottomInset + 12),
              decoration: BoxDecoration(
                color: SurfaceLevel.page.colorOf(scheme),
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FootButton(
                    label: '粘贴 Cookie',
                    onPressed: _manualCookie,
                  ),
                  const SizedBox(width: 12),
                  _FootButton(
                    label: '不登录，纯本地浏览',
                    onPressed: () async {
                      await context.read<Repo>().enterLocalMode();
                      if (!mounted) return;
                      Navigator.of(context).pop(false);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FootButton extends StatelessWidget {
  const _FootButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(
          color: context.colorScheme.surfaceContainerHigh.withValues(
            alpha: 0.94,
          ),
          shape: AppShape.full,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(
              HoboGlyphs.link,
              size: 15,
              color: context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyle.footnote.of(context).copyWith(
                fontSize: 12,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
