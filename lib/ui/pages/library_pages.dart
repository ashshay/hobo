import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../../data/store.dart';
import '../../data/update.dart';
import '../routes.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/image_actions.dart';
import '../widgets/remote_image.dart';
import '../widgets/status_card.dart';

/// 收藏夹：全局一份，跨账号保留。

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Status> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _items = context.read<Store>().favorites());
  }

  @override
  Widget build(BuildContext context) {
    return HoboPage(
      title: '收藏',
      leading: const HoboBackButton(),
      body: _items.isEmpty
          ? const HoboEmpty(
              title: '还没有收藏',
              message: '在微博卡片的操作栏里点收藏',
              icon: HoboGlyphs.star,
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                pageTopInset(context),
                16,
                pageBottomInset(context),
              ),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final status = _items[index];
                return StatusCard(
                  status: status,
                  onOpen: () => openStatus(context, status),
                  onOpenQuoted: (quoted) => openStatus(context, quoted),
                  onUser: (user) => openUser(context, user),
                  onImage: (pics, i) =>
                      openImages(context, pics: pics, index: i),
                  onLongPressImage: (pics, i) =>
                      showImageActions(context, pics: pics, index: i),
                  onVideo: (video) => openVideo(context, video),
                  onLongPress: () => _remove(status),
                  onFavorite: () => _remove(status),
                );
              },
            ),
    );
  }

  Future<void> _remove(Status status) async {
    final ok = await showHoboConfirm(
      context,
      title: '取消收藏？',
      destructive: true,
    );
    if (ok != true) return;
    context.read<Store>().removeFavorite(status.id);
    _load();
    if (mounted) showHoboToast(context, '已移出收藏');
  }
}

/// 浏览历史：本地记录，最多 100 条。

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _items = context.read<Store>().history());
  }

  @override
  Widget build(BuildContext context) {
    return HoboPage(
      title: '浏览历史',
      leading: const HoboBackButton(),
      actions: [
        if (_items.isNotEmpty)
          HoboBarAction(
            label: '清空',
            onPressed: () async {
              final ok = await showHoboConfirm(
                context,
                title: '清空浏览历史？',
                destructive: true,
              );
              if (ok == true) {
                context.read<Store>().clearHistory();
                _load();
              }
            },
          ),
      ],
      body: _items.isEmpty
          ? const HoboEmpty(
              title: '还没有浏览记录',
              message: '看过的微博会出现在这里',
              icon: HoboGlyphs.clock,
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                pageTopInset(context),
                16,
                pageBottomInset(context),
              ),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return HoboCard(
                  onPressed: () => openStatusById(context, item.id, item.mid),
                  onLongPress: () {
                    context.read<Store>().removeHistory(item.id);
                    _load();
                  },
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.user.isEmpty ? '微博' : item.user,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.subheadline.of(context)
                                  .copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: context.colorScheme.onSurface,
                                  ),
                            ),
                          ),
                          if (item.time > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              formatWeiboTime('${item.time}'),
                              style: AppTextStyle.caption1.of(context).copyWith(
                                fontSize: 11,
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.footnote.of(context).copyWith(
                          fontSize: 12.5,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// 草稿箱。点一条继续编辑，长按删除。

class DraftsPage extends StatefulWidget {
  const DraftsPage({super.key});

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  List<Draft> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _items = context.read<Store>().drafts());
  }

  @override
  Widget build(BuildContext context) {
    return HoboPage(
      title: '草稿箱',
      leading: const HoboBackButton(),
      body: _items.isEmpty
          ? HoboEmpty(
              title: '还没有草稿',
              message: '发布页退出时可以选择存草稿',
              icon: HoboGlyphs.edit,
              action: TextButton(
                onPressed: () => openCompose(context),
                child: const Text('去发微博'),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                pageTopInset(context),
                16,
                pageBottomInset(context),
              ),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final draft = _items[index];
                return HoboCard(
                  padding: const EdgeInsets.all(14),
                  onPressed: () => openCompose(context, initialText: draft.text),
                  onLongPress: () async {
                    final ok = await showHoboConfirm(
                      context,
                      title: '删除这条草稿？',
                      destructive: true,
                    );
                    if (ok == true) {
                      context.read<Store>().removeDraft(draft.time);
                      _load();
                    }
                  },
                  child: Text(
                    draft.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.body.of(context).copyWith(
                      fontSize: 14,
                      height: 1.4,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 账号管理：切换、添加、移除。

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    final accounts = repo.store.accounts();
    final current = repo.session?.uid ?? '';
    return HoboPage(
      title: '账号',
      leading: const HoboBackButton(),
      actions: [
        HoboBarAction(
          label: '添加',
          onPressed: () => openLogin(context, addAccount: true),
        ),
      ],
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          pageBottomInset(context),
        ),
        children: [
          if (accounts.isEmpty)
            const HoboEmpty(
              title: '还没有保存的账号',
              message: '登录一次就会记在这里',
              icon: HoboGlyphs.person,
            )
          else
            HoboCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final account in accounts)
                    HoboRow(
                      title: account.name.isEmpty ? account.uid : account.name,
                      subtitle: account.uid == current ? '当前账号' : null,
                      leading: Avatar(url: account.avatar, size: 32),
                      trailing: account.uid == current
                          ? GlyphIcon(
                              HoboGlyphs.check,
                              size: 18,
                              color: context.colorScheme.primary,
                            )
                          : null,
                      onPressed: () async {
                        await repo.switchAccount(account);
                        if (context.mounted) {
                          showHoboToast(context, '已切换账号');
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          HoboSection(
            title: '本地模式',
            footer: '纯本地模式不写入任何账号 cookie，只领取访客身份用于浏览。',
            children: [
              HoboRow(
                title: '纯本地浏览',
                subtitle: context.watch<Settings>().localMode
                    ? '已开启（无登录态只读）'
                    : '未开启',
                leading: const GlyphIcon(HoboGlyphs.link, size: 20),
                onPressed: () async {
                  await repo.enterLocalMode();
                  if (context.mounted) showHoboToast(context, '已进入本地模式');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 关于页。

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return HoboPage(
      title: '关于',
      leading: const HoboBackButton(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          pageBottomInset(context),
        ),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                HoboAppIcon(size: 76, shape: settings.iconShape),
                const SizedBox(height: 14),
                Text(
                  'Hobo',
                  style: AppTextStyle.title1.of(context).copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: context.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 ${Updater.versionLabel}',
                  style: AppTextStyle.footnote.of(context).copyWith(
                    fontSize: 12,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Hobo 是一个第三方微博客户端。界面基于 FlClash 的 prism_ui，'
                    '底栏、卡片、弹层与转场与 prism 设计语言保持一致。',
                    textAlign: TextAlign.center,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          HoboSection(
            title: '信息',
            children: [
              HoboRow(
                title: '开源组件',
                subtitle: 'prism_ui · dio · provider · video_player',
                leading: const GlyphIcon(HoboGlyphs.info, size: 20),
                onPressed: () {
                  Clipboard.setData(
                    const ClipboardData(
                      text: 'prism_ui, dio, provider, video_player, webview_flutter',
                    ),
                  );
                  showHoboToast(context, '已复制组件列表');
                },
              ),
              HoboRow(
                title: '检查更新',
                subtitle: '见设置页',
                leading: const GlyphIcon(HoboGlyphs.download, size: 20),
                onPressed: () async {
                  final current = await Updater.currentVersion();
                  if (!context.mounted) return;
                  showHoboToast(context, '当前版本 $current');
                },
              ),
              HoboRow(
                title: '隐私说明',
                subtitle: '登录 Cookie 只存放在本机应用私有目录',
                leading: const GlyphIcon(HoboGlyphs.info, size: 20),
                onPressed: () => showHoboAlert(
                  context,
                  title: '隐私说明',
                  message:
                      'Hobo 不收集任何账号数据。Cookie、草稿、收藏与浏览历史都保存在本机，'
                      '卸载应用即删除。所有请求直接发往微博接口。',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Made with prism_ui',
              style: AppTextStyle.caption1.of(context).copyWith(
                fontSize: 11,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
