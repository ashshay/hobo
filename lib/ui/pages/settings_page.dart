import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/app_icon.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../../data/store.dart';
import '../../data/update.dart';
import '../routes.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';

/// 设置。分组照 Kotlin 版：外观 / 浏览 / 互动 / 更新 / 数据 / 账号 / 关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final repo = context.watch<Repo>();
    final session = repo.session;
    return HoboPage(
      title: '设置',
      leading: const HoboBackButton(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          pageTopInset(context),
          0,
          pageBottomInset(context),
        ),
        children: [
          _AccountCard(
            session: session,
            onLogin: () => openLogin(context),
            onAccounts: () => openAccounts(context),
            onProfile: session == null
                ? null
                : () => openUserById(context, session.uid),
          ),
          HoboSection(
            title: '外观',
            children: [
              HoboRow(
                title: '深色模式',
                subtitle: switch (settings.darkMode) {
                  1 => '浅色',
                  2 => '深色',
                  _ => '跟随系统',
                },
                leading: const GlyphIcon(HoboGlyphs.moon, size: 20),
                showChevron: true,
                onPressed: () => _pickDarkMode(settings),
              ),
              HoboRow(
                title: '字号',
                subtitle: '${(settings.fontScale * 100).round()}%',
                leading: const GlyphIcon(HoboGlyphs.textSize, size: 20),
                onPressed: settings.cycleFontScale,
              ),
              HoboRow(
                title: '强调色',
                subtitle: _accentLabel(settings.accentColor),
                leading: const GlyphIcon(HoboGlyphs.palette, size: 20),
                showChevron: true,
                onPressed: () => _pickAccent(settings),
              ),
              HoboRow(
                title: '卡片跟随壁纸取色',
                subtitle: '用壁纸色调给页面和卡片上色（Android 12+）',
                leading: const GlyphIcon(HoboGlyphs.palette, size: 20),
                trailing: Switch(
                  value: settings.monetCards,
                  onChanged: settings.applyMonetCards,
                ),
              ),
              HoboRow(
                title: '模糊效果',
                subtitle: '顶栏与玻璃面的实时模糊',
                leading: const GlyphIcon(Glyphs.eye, size: 20),
                trailing: Switch(
                  value: settings.blurEffects,
                  onChanged: settings.applyBlurEffects,
                ),
              ),
              HoboRow(
                title: '应用图标',
                subtitle: settings.iconShape.label,
                leading: HoboAppIcon(size: 22, shape: settings.iconShape),
                showChevron: true,
                onPressed: () => _pickIconShape(settings),
              ),
            ],
          ),
          HoboSection(
            title: '浏览',
            children: [
              HoboRow(
                title: '微博页栏目',
                subtitle: settings.visibleFeedTabs == null
                    ? '全部栏目'
                    : '已选 ${settings.visibleFeedTabs!.length} 个栏目',
                leading: const GlyphIcon(HoboGlyphs.list, size: 20),
                showChevron: true,
                onPressed: () => _pickFeedTabs(settings),
              ),
              HoboRow(
                title: '本地关注取数账号',
                subtitle: settings.localFollowUid.isEmpty
                    ? '跟随当前账号'
                    : _accountName(repo, settings.localFollowUid),
                leading: const GlyphIcon(HoboGlyphs.person, size: 20),
                showChevron: true,
                onPressed: () => _pickLocalFollowAccount(repo, settings),
              ),
              HoboRow(
                title: '附近城市',
                subtitle: settings.nearbyCustom
                    ? settings.nearbyPlaceName
                    : '跟随设备定位',
                leading: const GlyphIcon(HoboGlyphs.location, size: 20),
                showChevron: true,
                onPressed: () => openNearby(context),
              ),
              HoboRow(
                title: '热搜榜',
                subtitle: settings.hotBoards.isEmpty
                    ? '已隐藏'
                    : settings.hotBoards.map((b) => b.label).join('、'),
                leading: const GlyphIcon(HoboGlyphs.trending, size: 20),
                showChevron: true,
                onPressed: () => _pickHotBoards(settings),
              ),
              HoboRow(
                title: '看图默认画质',
                subtitle: settings.imageBrowseQuality.label,
                leading: const GlyphIcon(HoboGlyphs.image, size: 20),
                showChevron: true,
                onPressed: () => _pickImageQuality(settings),
              ),
            ],
          ),
          HoboSection(
            title: '互动',
            children: [
              HoboRow(
                title: '点赞前确认',
                subtitle: '点爱心后先问一句，避免手滑',
                leading: const GlyphIcon(HoboGlyphs.like, size: 20),
                trailing: Switch(
                  value: settings.confirmLike,
                  onChanged: settings.applyConfirmLike,
                ),
              ),
              HoboRow(
                title: '底栏「我」显示头像',
                leading: const GlyphIcon(HoboGlyphs.person, size: 20),
                trailing: Switch(
                  value: settings.profileTabAvatar,
                  onChanged: settings.applyProfileTabAvatar,
                ),
              ),
              HoboRow(
                title: '长按「我」快捷切号',
                leading: const GlyphIcon(HoboGlyphs.people, size: 20),
                trailing: Switch(
                  value: settings.quickSwitchAccount,
                  onChanged: settings.applyQuickSwitchAccount,
                ),
              ),
            ],
          ),
          HoboSection(
            title: '更新',
            children: [
              HoboRow(
                title: '检查更新',
                subtitle: '当前版本 $_version · 打开 GitHub 页面',
                leading: const GlyphIcon(HoboGlyphs.download, size: 20),
                showChevron: true,
                onPressed: _checkUpdate,
              ),
            ],
          ),
          HoboSection(
            title: '数据',
            children: [
              HoboRow(
                title: '收藏',
                leading: const GlyphIcon(HoboGlyphs.star, size: 20),
                showChevron: true,
                onPressed: () => openFavorites(context),
              ),
              HoboRow(
                title: '浏览历史',
                leading: const GlyphIcon(HoboGlyphs.clock, size: 20),
                showChevron: true,
                onPressed: () => openHistory(context),
              ),
              HoboRow(
                title: '草稿箱',
                leading: const GlyphIcon(HoboGlyphs.edit, size: 20),
                showChevron: true,
                onPressed: () => openDrafts(context),
              ),
              HoboRow(
                title: '清除接口缓存',
                subtitle: '只清网络缓存，不动登录态',
                leading: const GlyphIcon(HoboGlyphs.delete, size: 20),
                onPressed: () {
                  Api.cache?.clear();
                  showHoboToast(context, '缓存已清除');
                },
              ),
              HoboRow(
                title: '清除浏览历史',
                leading: const GlyphIcon(HoboGlyphs.delete, size: 20),
                danger: true,
                onPressed: () async {
                  final ok = await showHoboConfirm(
                    context,
                    title: '清除浏览历史？',
                    message: '收藏与草稿不受影响',
                    destructive: true,
                  );
                  if (ok == true && context.mounted) {
                    context.read<Store>().clearHistory();
                    showHoboToast(context, '已清除');
                  }
                },
              ),
            ],
          ),
          HoboSection(
            title: '关于',
            children: [
              const HoboRow(
                title: 'Hobo',
                subtitle: 'prism 设计语言的微博客户端',
                showChevron: false,
              ),
              HoboRow(
                title: '关于 Hobo',
                leading: const GlyphIcon(HoboGlyphs.info, size: 20),
                showChevron: true,
                onPressed: () => openAbout(context),
              ),
              HoboRow(
                title: '捐赠',
                subtitle: '感谢支持，请作者喝杯水',
                leading: const GlyphIcon(HoboGlyphs.like, size: 20),
                showChevron: true,
                onPressed: _showDonation,
              ),
            ],
          ),
          if (session != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: HoboCard(
                onPressed: () => _logout(repo),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlyphIcon(
                      HoboGlyphs.logout,
                      size: 18,
                      color: context.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '退出登录',
                      style: AppTextStyle.body.of(context).copyWith(
                        color: context.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _version => Updater.versionLabel;

  String _accentLabel(int argb) {
    if (argb == 0) return '跟随壁纸（Monet）';
    if (argb == accentHueCycle) return 'Jeb_ · 色相缓慢循环';
    for (final preset in accentPresets) {
      if (preset.argb != 0 &&
          preset.argb != accentHueCycle &&
          (preset.argb | 0xFF000000) == argb) {
        return preset.label;
      }
    }
    final hex = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '自定义 #${hex.toUpperCase()}';
  }

  String _accountName(Repo repo, String uid) {
    for (final account in repo.store.accounts()) {
      if (account.uid == uid) {
        return account.name.isEmpty ? account.uid : account.name;
      }
    }
    return uid;
  }

  Future<void> _pickDarkMode(Settings settings) async {
    final pick = await showHoboActionSheet(
      context,
      title: '深色模式',
      actions: [
        ('跟随系统', () => settings.applyDarkMode(0)),
        ('浅色', () => settings.applyDarkMode(1)),
        ('深色', () => settings.applyDarkMode(2)),
      ],
    );
    pick;
  }

  Future<void> _pickAccent(Settings settings) async {
    final picked = await showFloatingDialog<int>(
      context: context,
      child: _AccentDialog(current: settings.accentColor),
    );
    if (picked != null) settings.applyAccentColor(picked);
  }

  Future<void> _pickFeedTabs(Settings settings) async {
    final repo = context.read<Repo>();
    var groups = const <FollowGroup>[];
    try {
      groups = await repo.followGroups();
    } on Object {
      groups = const [];
    }
    if (!mounted) return;
    // 顺序和首页栏目条一致；「原创」还没有独立数据源，先不放进来。
    const order = [
      FeedTabItem.follow,
      FeedTabItem.recommend,
      FeedTabItem.circle,
      FeedTabItem.special,
      FeedTabItem.secret,
      FeedTabItem.local,
      FeedTabItem.favorites,
      FeedTabItem.nearby,
    ];
    final options = <FeedTabSelection>[
      for (final item in order) FeedTabSelection(item),
      for (final group in groups) FeedTabSelection(FeedTabItem.group, group),
    ];
    final saved = settings.visibleFeedTabs;
    final initial = saved ?? {for (final option in options) option.key};
    final picked = await showFloatingDialog<Set<String>>(
      context: context,
      child: _FeedTabsDialog(options: options, selected: initial),
    );
    if (picked == null || !mounted) return;
    // 本次没拉到的关注分组（接口失败）不要因为保存而从已选里消失。
    final known = {for (final option in options) option.key};
    final kept = saved?.where((key) => !known.contains(key)) ?? const <String>{};
    final keys = {...picked, ...kept};
    settings.applyVisibleFeedTabs(keys);
    if (!keys.contains(settings.feedTab.key)) {
      final fallback = options.firstWhere(
        (option) => keys.contains(option.key),
        orElse: () => options.first,
      );
      settings.applyFeedTab(fallback);
      settings.applyFeedTabKey(fallback.key);
    }
  }

  Future<void> _pickLocalFollowAccount(Repo repo, Settings settings) async {
    final accounts = repo.store.accounts();
    await showHoboActionSheet(
      context,
      title: '本地关注取数账号',
      actions: [
        ('跟随当前账号', () => settings.applyLocalFollowUid('')),
        for (final account in accounts)
          (
            account.name.isEmpty ? account.uid : account.name,
            () => settings.applyLocalFollowUid(account.uid),
          ),
      ],
    );
  }

  Future<void> _pickHotBoards(Settings settings) async {
    final selected = {...settings.hotBoards};
    await showFloatingDialog<void>(
      context: context,
      child: _HotBoardDialog(selected: selected, settings: settings),
    );
  }

  Future<void> _pickIconShape(Settings settings) async {
    final picked = await showHoboChoices<AppIconShape>(
      context,
      title: '应用图标',
      choices: [
        for (final shape in AppIconShape.values)
          HoboChoice(
            value: shape,
            label: shape.label,
            subtitle: shape.hint,
            leading: HoboAppIcon(size: 30, shape: shape),
            selected: shape == settings.iconShape,
          ),
      ],
    );
    if (picked == null) return;
    settings.applyIconShape(picked);
    final applied = await AppIcon.apply(picked);
    if (!mounted) return;
    if (applied == null) {
      showHoboToast(
        context,
        '已记住选择，但这台设备不支持改桌面图标',
        level: BannerLevel.warning,
      );
    } else {
      showHoboToast(context, '已切换为${applied.label}，回桌面看看');
    }
  }

  Future<void> _pickImageQuality(Settings settings) async {
    await showHoboActionSheet(
      context,
      title: '看图默认画质',
      actions: [
        for (final quality in ImageBrowseQuality.values)
          (quality.label, () => settings.applyImageBrowseQuality(quality)),
      ],
    );
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      // 记一笔「什么时候查过」，数据页/诊断用得到。
      context.read<Settings>().applyUpdateCheckedAt(
        DateTime.now().millisecondsSinceEpoch,
      );
      // 版本说明、更新日志和安装包都在 GitHub 页面上，直接把人送过去，
      // 不在设置里复述一遍版本号。内置网页顶栏还能一键转到系统浏览器。
      openWeb(context, Updater.homepage, title: 'Hobo 更新');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _showDonation() async {
    await showFloatingDialog<void>(
      context: context,
      child: const _DonationDialog(),
    );
  }

  Future<void> _logout(Repo repo) async {
    final ok = await showHoboConfirm(
      context,
      title: '退出登录？',
      message: '收藏、草稿与浏览历史会保留',
      destructive: true,
      confirmText: '退出',
    );
    if (ok != true) return;
    await repo.logout();
    if (!mounted) return;
    context.read<Settings>().applyLocalMode(true);
    await repo.enterLocalMode();
    if (mounted) showHoboToast(context, '已退出登录');
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.session,
    required this.onLogin,
    required this.onAccounts,
    this.onProfile,
  });

  final Session? session;
  final VoidCallback onLogin;
  final VoidCallback onAccounts;
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final account = _findAccount(context, session?.uid);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: HoboCard(
        onPressed: session == null ? onLogin : onAccounts,
        child: Row(
          children: [
            Avatar(
              url: account?.avatar ?? '',
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session == null
                        ? '未登录'
                        : (account?.name.isNotEmpty == true
                              ? account!.name
                              : session!.uid),
                    style: AppTextStyle.headline.of(context).copyWith(
                      fontSize: 17,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    session == null
                        ? '登录后可以关注、评论、发布'
                        : (session!.loggedIn ? '网页登录态' : '登录已过期'),
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontSize: 12,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (session == null)
              const GlyphIcon(Glyphs.chevronForward, size: 18)
            else
              GestureDetector(
                onTap: onProfile,
                child: Text(
                  '主页',
                  style: AppTextStyle.footnote.of(context).copyWith(
                    fontSize: 13,
                    color: context.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Account? _findAccount(BuildContext context, String? uid) {
    if (uid == null || uid.isEmpty) return null;
    for (final account in context.read<Repo>().store.accounts()) {
      if (account.uid == uid) return account;
    }
    return null;
  }
}

/// 赞赏码：点「捐赠」后展示。
class _DonationDialog extends StatelessWidget {
  const _DonationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '赞赏码',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            image: true,
            label: '赞赏码',
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/donate/donate_qr.png',
                width: 260,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '微信 / 支付宝扫一扫，感谢支持',
            style: AppTextStyle.caption1.of(context).copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 热搜榜多选。
class _HotBoardDialog extends StatefulWidget {
  const _HotBoardDialog({required this.selected, required this.settings});

  final Set<HotBoard> selected;
  final Settings settings;

  @override
  State<_HotBoardDialog> createState() => _HotBoardDialogState();
}

class _HotBoardDialogState extends State<_HotBoardDialog> {
  late final Set<HotBoard> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '热搜榜',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final board in HotBoard.values)
            HoboRow(
              title: board.label,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              trailing: Switch(
                value: _selected.contains(board),
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      _selected.add(board);
                    } else {
                      _selected.remove(board);
                    }
                  });
                  widget.settings.applyHotBoards(_selected);
                },
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '一个都不选时，发现页不显示热搜区块',
            style: AppTextStyle.caption1.of(context).copyWith(
              fontSize: 11,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 微博页栏目多选：勾选并保存后，首页才显示这些栏目。
class _FeedTabsDialog extends StatefulWidget {
  const _FeedTabsDialog({required this.options, required this.selected});

  final List<FeedTabSelection> options;
  final Set<String> selected;

  @override
  State<_FeedTabsDialog> createState() => _FeedTabsDialogState();
}

class _FeedTabsDialogState extends State<_FeedTabsDialog> {
  late final Set<String> _selected = {...widget.selected};
  bool _emptyHint = false;

  void _toggle(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
      _emptyHint = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '微博页栏目',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            if (_selected.isEmpty) {
              setState(() => _emptyHint = true);
              return;
            }
            Navigator.of(context).pop(_selected);
          },
          child: const Text('保存'),
        ),
      ],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          minWidth: 260,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in widget.options)
                HoboRow(
                  title: option.label,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  onPressed: () => _toggle(option.key),
                  trailing: Checkbox(
                    value: _selected.contains(option.key),
                    onChanged: (_) => _toggle(option.key),
                  ),
                ),
              if (_emptyHint)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '至少保留一个栏目',
                    style: AppTextStyle.caption1.of(context).copyWith(
                      color: context.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 强调色选择：预设 + 自定义十六进制。
class _AccentDialog extends StatefulWidget {
  const _AccentDialog({required this.current});

  final int current;

  @override
  State<_AccentDialog> createState() => _AccentDialogState();
}

class _AccentDialogState extends State<_AccentDialog> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.current == 0 || widget.current == accentHueCycle
        ? ''
        : (widget.current & 0xFFFFFF).toRadixString(16).padLeft(6, '0'),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyCustom() {
    final clean = _hex.text.trim().replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(clean)) {
      Navigator.of(context).pop(int.parse(clean, radix: 16) | 0xFF000000);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '强调色',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _applyCustom, child: const Text('应用')),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final preset in accentPresets)
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(preset.argb),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: ShapeDecoration(
                          color: preset.argb == accentHueCycle
                              ? const Color(0xFFFF8200)
                              : preset.argb == 0
                              ? const Color(0xFF0A84FF)
                              : Color(preset.argb),
                          shape: AppShape.full,
                        ),
                        child: widget.current == preset.argb
                            ? const Center(
                                child: GlyphIcon(
                                  HoboGlyphs.check,
                                  size: 18,
                                  color: Color(0xFFFFFFFF),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preset.label,
                        style: AppTextStyle.caption1.of(context).copyWith(
                          fontSize: 10,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _hex,
            decoration: const InputDecoration(
              hintText: '自定义 #RRGGBB',
              isCollapsed: true,
            ),
            onSubmitted: (_) => _applyCustom(),
          ),
        ],
      ),
    );
  }
}
