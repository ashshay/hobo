import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/settings.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/feed_list.dart';
import '../widgets/glyphs.dart';

/// 附近（同城）：按坐标取一条同城流，可切换到别的城市。
class NearbyPage extends StatefulWidget {
  const NearbyPage({super.key});

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  FeedController? _feed;
  List<NearbyPlace> _cities = const [];
  bool _loadingCities = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final settings = context.read<Settings>();
    final lat = settings.nearbyCustom ? settings.nearbyPlaceLat : 31.2304;
    final lon = settings.nearbyCustom ? settings.nearbyPlaceLon : 121.4737;
    _feed = FeedController(
      (cursor, {required force}) =>
          context.read<Repo>().nearby('$lat', '$lon', maxId: cursor, force: force),
    );
    _feed!.ensureLoaded();
  }

  @override
  void dispose() {
    _feed?.dispose();
    super.dispose();
  }

  Future<void> _pickCity() async {
    if (_loadingCities) return;
    setState(() => _loadingCities = true);
    try {
      final cities = await context.read<Repo>().nearbyCities();
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _loadingCities = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadingCities = false);
      showHoboToast(context, e.toString(), level: BannerLevel.error);
      return;
    }
    if (!mounted) return;
    final settings = context.read<Settings>();
    final picked = await showHoboChoices<NearbyPlace>(
      context,
      title: '选择城市',
      choices: [
        const HoboChoice(
          value: NearbyPlace('跟随设备定位', 31.2304, 121.4737),
          label: '跟随设备定位',
          subtitle: '按默认坐标浏览',
          selected: true,
        ),
        for (final place in _cities)
          HoboChoice(value: place, label: place.name),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked.name == '跟随设备定位') {
      settings.applyNearbyDevice();
    } else {
      settings.applyNearbyPlace(picked.name, picked.lat, picked.lon);
    }
    setState(_start);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final feed = _feed;
    final title = settings.nearbyCustom && settings.nearbyPlaceName.isNotEmpty
        ? settings.nearbyPlaceName
        : '附近';
    return HoboPage(
      title: title,
      leading: const HoboBackButton(),
      actions: [
        IconButton(
          onPressed: _loadingCities ? null : _pickCity,
          tooltip: '选择城市',
          icon: const GlyphIcon(HoboGlyphs.location, size: 22),
        ),
        IconButton(
          onPressed: () => feed?.refresh(),
          tooltip: '刷新',
          icon: const GlyphIcon(HoboGlyphs.refresh, size: 22),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 8),
            child: HoboCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  GlyphIcon(
                    HoboGlyphs.location,
                    size: 16,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      settings.nearbyCustom
                          ? '当前城市：${settings.nearbyPlaceName}'
                          : '未选择城市，按默认坐标浏览',
                      style: AppTextStyle.footnote.of(context).copyWith(
                        fontSize: 12,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: feed == null
                ? const HoboLoading()
                : StatusList(
                    controller: feed,
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                    dockInset: false,
                    emptyTitle: '这里还没有内容',
                    emptyMessage: '换个城市看看',
                    onOpenStatus: (status) => openStatus(context, status),
                    onOpenUser: (user) => openUser(context, user),
                    onOpenImage: (pics, index) =>
                        openImages(context, pics: pics, index: index),
                    onOpenVideo: (video) => openVideo(context, video),
                    onLink: (url) => handleLink(context, url),
                    onLongPressStatus: (status) =>
                        showStatusActions(context, status),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 城市选择页单独入口（设置里用）。
class NearbyCitiesPage extends StatefulWidget {
  const NearbyCitiesPage({super.key});

  @override
  State<NearbyCitiesPage> createState() => _NearbyCitiesPageState();
}

class _NearbyCitiesPageState extends State<NearbyCitiesPage> {
  List<NearbyPlace> _cities = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cities = await context.read<Repo>().nearbyCities(force: true);
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    return HoboPage(
      title: '附近城市',
      leading: const HoboBackButton(),
      body: _loading
          ? const HoboLoading(label: '正在加载城市…')
          : _cities.isEmpty
          ? HoboEmpty(
              title: _error ?? '没有可选城市',
              action: TextButton(onPressed: _load, child: const Text('重试')),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                pageTopInset(context),
                16,
                pageBottomInset(context),
              ),
              children: [
                HoboCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      HoboRow(
                        title: '跟随设备定位',
                        trailing: !settings.nearbyCustom
                            ? GlyphIcon(
                                HoboGlyphs.check,
                                size: 18,
                                color: context.colorScheme.primary,
                              )
                            : null,
                        onPressed: () {
                          settings.applyNearbyDevice();
                          Navigator.of(context).maybePop();
                        },
                      ),
                      for (final place in _cities)
                        HoboRow(
                          title: place.name,
                          trailing:
                              settings.nearbyCustom &&
                                  settings.nearbyPlaceName == place.name
                              ? GlyphIcon(
                                  HoboGlyphs.check,
                                  size: 18,
                                  color: context.colorScheme.primary,
                                )
                              : null,
                          onPressed: () {
                            settings.applyNearbyPlace(
                              place.name,
                              place.lat,
                              place.lon,
                            );
                            Navigator.of(context).maybePop();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
