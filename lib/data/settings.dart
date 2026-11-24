/// 用户设置：主题、字号、强调色、信息流栏目、附近城市、更新策略、搜索历史、续看位置。
///
/// 对应 Kotlin 版 `data/Settings.kt`（SharedPreferences），用 [ChangeNotifier] 让界面跟着变。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 信息流栏目。分组是账号里的数据，不写进枚举，由 [FeedTabSelection.group] 带上。
enum FeedTabItem {
  none('none', '隐藏'),
  follow('follow', '关注'),
  circle('circle', '好友圈'),
  recommend('recommend', '推荐'),
  local('local', '本地关注'),
  original('original', '原创'),
  special('special', '特别关注'),
  secret('secret', '悄悄关注'),
  favorites('favorites', '收藏'),
  nearby('nearby', '附近'),
  group('group', '关注分组');

  const FeedTabItem(this.key, this.label);

  final String key;
  final String label;

  static FeedTabItem fromKey(String? key, FeedTabItem fallback) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return fallback;
  }
}

class FeedTabSelection {
  const FeedTabSelection(this.item, [this.group]);

  final FeedTabItem item;
  final FollowGroup? group;

  String get key => switch (item) {
    FeedTabItem.group => group == null ? item.key : 'group_${group!.gid}',
    _ => item.key,
  };

  String get label => switch (item) {
    FeedTabItem.group => (group?.title.isNotEmpty ?? false)
        ? group!.title
        : item.label,
    _ => item.label,
  };

  bool get isGroup => item == FeedTabItem.group && group != null;
}

enum ImageBrowseQuality {
  standard('default', '默认'),
  original('original', '原图');

  const ImageBrowseQuality(this.key, this.label);

  final String key;
  final String label;

  static ImageBrowseQuality fromKey(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return standard;
  }
}

class AccentPreset {
  const AccentPreset(this.label, this.argb);

  final String label;
  final int argb;
}

/// 视频倍速。播放器里换档、设置里的默认值都走这一套。
enum VideoSpeed {
  half(0.5, '0.5x'),
  threeQuarters(0.75, '0.75x'),
  normal(1, '1.0x'),
  fiveQuarters(1.25, '1.25x'),
  oneHalf(1.5, '1.5x'),
  twice(2, '2.0x');

  const VideoSpeed(this.rate, this.label);

  final double rate;
  final String label;

  static VideoSpeed fromRate(double? rate) {
    final value = rate ?? normal.rate;
    for (final speed in values) {
      if ((speed.rate - value).abs() < 0.01) return speed;
    }
    return normal;
  }
}

/// 桌面图标形状。两套位图都打进 APK，靠 `AndroidManifest.xml` 里的 activity-alias 切换，
/// 实际开关在 `lib/data/app_icon.dart`。
enum AppIconShape {
  rounded('rounded', '圆角矩形', '圆角方形，和桌面上的其他图标排在一起更整齐'),
  circle('circle', '圆形', '正圆，适合圆形桌面主题');

  const AppIconShape(this.key, this.label, this.hint);

  final String key;
  final String label;
  final String hint;

  static AppIconShape fromKey(
    String? key, [
    AppIconShape fallback = AppIconShape.rounded,
  ]) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return fallback;
  }
}

/// `0` 表示跟随 prism 默认蓝；[accentHueCycle] 表示色相缓慢循环。
const accentHueCycle = 1;

/// 全局字号缩放范围与步进：85%–130%，每档 5%（共 9 段 / 10 档）。
const double fontScaleMin = 0.85;
const double fontScaleMax = 1.30;
const int fontScaleDivisions = 9;

/// 全局字体粗细偏移档位：-1（较细）~ +3（粗体），0 为默认标准粗细。
const int fontWeightDeltaMin = -1;
const int fontWeightDeltaMax = 3;

/// 将字号缩放夹在合法区间内并去掉浮点尾差（如 1.1500000000000001）。
double normalizeFontScale(double value) {
  final clamped = value.clamp(fontScaleMin, fontScaleMax).toDouble();
  return (clamped * 100).round() / 100;
}

/// 将字体粗细偏移夹在合法档位内。
int normalizeFontWeightDelta(int value) =>
    value.clamp(fontWeightDeltaMin, fontWeightDeltaMax);

/// 字号挡位的易读描述。
String fontScaleLabel(double scale) {
  final pct = (normalizeFontScale(scale) * 100).round();
  if (pct <= 88) return '$pct% · 紧凑';
  if (pct <= 96) return '$pct% · 偏小';
  if (pct <= 104) return '$pct% · 标准';
  if (pct <= 116) return '$pct% · 偏大';
  return '$pct% · 特大';
}

/// 字体粗细档位标签（对应基准正文 W300–W700）。
String fontWeightLabel(int delta) => switch (normalizeFontWeightDelta(delta)) {
  -1 => '较细',
  0 => '标准',
  1 => '适中',
  2 => '偏粗',
  _ => '粗体',
};

const accentPresets = <AccentPreset>[
  AccentPreset('跟随壁纸', 0),
  AccentPreset('微博橙', 0xFFFF8200),
  AccentPreset('珊瑚红', 0xFFE53935),
  AccentPreset('樱花粉', 0xFFE91E63),
  AccentPreset('紫罗兰', 0xFF8E24AA),
  AccentPreset('靛青蓝', 0xFF3F51B5),
  AccentPreset('天空青', 0xFF00ACC1),
  AccentPreset('翡翠绿', 0xFF009688),
  AccentPreset('生机绿', 0xFF34C759),
  AccentPreset('Jeb_', accentHueCycle),
];

class Settings extends ChangeNotifier {
  Settings(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const searchHistoryLimit = 10;

  List<String> _searchHistory = const [];
  int _darkMode = 0;
  double _fontScale = 1;
  int _fontWeightDelta = 0;
  int _accentColor = 0;
  int _mainTab = 0;
  FeedTabSelection _feedTab = const FeedTabSelection(FeedTabItem.follow);
  String _feedTabKey = 'follow';

  /// 首页要显示的栏目 key（`feed_tab_visible`）。null 表示没设置过，全部显示。
  Set<String>? _visibleFeedTabs;
  String _localFollowUid = '';
  bool _localMode = false;
  bool _nearbyCustom = false;
  String _nearbyPlaceName = '';
  double _nearbyPlaceLat = 0;
  double _nearbyPlaceLon = 0;
  bool _blurEffects = true;
  bool _monetCards = false;
  bool _confirmLike = false;
  bool _quickSwitchAccount = true;
  bool _profileTabAvatar = true;
  bool _reverseBrowse = false;
  ImageBrowseQuality _imageBrowseQuality = ImageBrowseQuality.standard;
  VideoSpeed _videoSpeed = VideoSpeed.normal;
  AppIconShape _iconShape = AppIconShape.rounded;
  Set<HotBoard> _hotBoards = HotBoard.values.toSet();
  int _updateCheckedAt = 0;
  String _skippedUpdate = '';
  bool _autoCheckUpdate = true;
  String _updateEtag = '';
  String _updateCache = '';

  void _load() {
    final rawHistory = _prefs.getString('search_history');
    if (rawHistory != null) {
      _searchHistory = parseSearchHistoryJson(rawHistory);
    }
    if (_prefs.containsKey('dark_mode')) {
      _darkMode = _prefs.getInt('dark_mode') ?? 0;
    } else if (_prefs.containsKey('dark')) {
      _darkMode = (_prefs.getBool('dark') ?? false) ? 2 : 1;
    }
    _fontScale = normalizeFontScale(_prefs.getDouble('font_scale') ?? 1);
    _fontWeightDelta = normalizeFontWeightDelta(
      _prefs.getInt('font_weight_delta') ?? 0,
    );
    _accentColor = _prefs.getInt('accent_color') ?? 0;
    _mainTab = _prefs.getInt('main_tab') ?? 0;
    final item = FeedTabItem.fromKey(
      _prefs.getString('feed_tab'),
      FeedTabItem.follow,
    );
    if (item == FeedTabItem.group) {
      final gid = _prefs.getString('feed_group_gid') ?? '';
      final title = _prefs.getString('feed_group_title') ?? '';
      _feedTab = gid.isEmpty
          ? const FeedTabSelection(FeedTabItem.follow)
          : FeedTabSelection(FeedTabItem.group, FollowGroup(gid, title));
    } else {
      _feedTab = FeedTabSelection(item);
    }
    _feedTabKey = _prefs.getString('feed_tab_key') ?? 'follow';
    final storedTabs = _prefs.getStringList('feed_tabs_visible');
    if (storedTabs != null) _visibleFeedTabs = storedTabs.toSet();
    _localFollowUid = _prefs.getString('local_follow_uid') ?? '';
    _localMode = _prefs.getBool('local_mode') ?? false;
    _nearbyCustom = _prefs.getBool('nearby_custom') ?? false;
    _nearbyPlaceName = _prefs.getString('nearby_place_name') ?? '';
    _nearbyPlaceLat = _prefs.getDouble('nearby_place_lat') ?? 0;
    _nearbyPlaceLon = _prefs.getDouble('nearby_place_lon') ?? 0;
    _blurEffects = _prefs.getBool('blur_effects') ?? true;
    _monetCards = _prefs.getBool('monet_cards') ?? false;
    _confirmLike = _prefs.getBool('confirm_like') ?? false;
    _quickSwitchAccount = _prefs.getBool('quick_switch_account') ?? true;
    _profileTabAvatar = _prefs.getBool('profile_tab_avatar') ?? true;
    _reverseBrowse = _prefs.getBool('reverse_browse') ?? false;
    _imageBrowseQuality = ImageBrowseQuality.fromKey(
      _prefs.getString('image_browse_quality'),
    );
    _videoSpeed = VideoSpeed.fromRate(_prefs.getDouble('video_speed'));
    _iconShape = AppIconShape.fromKey(_prefs.getString('icon_shape'));
    _hotBoards = parseHotBoards(_prefs.getString('hot_boards'));
    _updateCheckedAt = _prefs.getInt('update_checked_at') ?? 0;
    _skippedUpdate = _prefs.getString('skipped_update') ?? '';
    _autoCheckUpdate = _prefs.getBool('auto_check_update') ?? true;
    _updateEtag = _prefs.getString('update_etag') ?? '';
    _updateCache = _prefs.getString('update_cache') ?? '';
  }

  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  int get darkMode => _darkMode;
  bool get isDarkMode => _darkMode == 2;
  double get fontScale => _fontScale;
  int get fontWeightDelta => _fontWeightDelta;
  int get accentColor => _accentColor;
  int get mainTab => _mainTab;
  FeedTabSelection get feedTab => _feedTab;
  String get feedTabKey => _feedTabKey;

  /// 首页可见栏目；null 表示没设置过，全部显示。
  Set<String>? get visibleFeedTabs =>
      _visibleFeedTabs == null ? null : Set.unmodifiable(_visibleFeedTabs!);
  String get localFollowUid => _localFollowUid;
  bool get localMode => _localMode;
  bool get nearbyCustom => _nearbyCustom;
  String get nearbyPlaceName => _nearbyPlaceName;
  double get nearbyPlaceLat => _nearbyPlaceLat;
  double get nearbyPlaceLon => _nearbyPlaceLon;
  bool get blurEffects => _blurEffects;

  /// 卡片背景是否也跟随壁纸取色（Monet 色调）。
  bool get monetCards => _monetCards;
  bool get confirmLike => _confirmLike;
  bool get quickSwitchAccount => _quickSwitchAccount;
  bool get profileTabAvatar => _profileTabAvatar;
  bool get reverseBrowse => _reverseBrowse;
  ImageBrowseQuality get imageBrowseQuality => _imageBrowseQuality;
  VideoSpeed get videoSpeed => _videoSpeed;
  AppIconShape get iconShape => _iconShape;
  Set<HotBoard> get hotBoards => _hotBoards;
  int get updateCheckedAt => _updateCheckedAt;
  String get skippedUpdate => _skippedUpdate;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String get updateEtag => _updateEtag;
  String get updateCache => _updateCache;

  void applyMainTab(int value) {
    _mainTab = value;
    _prefs.setInt('main_tab', value);
    notifyListeners();
  }

  void pushSearchHistory(String keyword) {
    final query = keyword.trim();
    if (query.isEmpty) return;
    final next = [query, ..._searchHistory.where((item) => item != query)];
    _searchHistory = next.take(searchHistoryLimit).toList();
    _prefs.setString('search_history', encodeSearchHistoryJson(_searchHistory));
    notifyListeners();
  }

  void removeSearchHistory(String keyword) {
    _searchHistory = [
      for (final item in _searchHistory)
        if (item != keyword) item,
    ];
    _prefs.setString('search_history', encodeSearchHistoryJson(_searchHistory));
    notifyListeners();
  }

  void clearSearchHistory() {
    _searchHistory = const [];
    _prefs.setString('search_history', encodeSearchHistoryJson(_searchHistory));
    notifyListeners();
  }

  void applyFeedTab(FeedTabSelection selection) {
    _feedTab = selection;
    _prefs.setString('feed_tab', selection.item.key);
    _prefs.setString('feed_group_gid', selection.group?.gid ?? '');
    _prefs.setString('feed_group_title', selection.group?.title ?? '');
    notifyListeners();
  }

  void applyFeedTabKey(String key) {
    _feedTabKey = key;
    _prefs.setString('feed_tab_key', key);
    notifyListeners();
  }

  void applyVisibleFeedTabs(Iterable<String> keys) {
    _visibleFeedTabs = {...keys};
    _prefs.setStringList('feed_tabs_visible', _visibleFeedTabs!.toList());
    notifyListeners();
  }

  /// 换账号时把落在分组上的栏恢复成内置流：分组是账号里的数据，换了号就不存在。
  void clearGroupFeedTab() {
    if (_feedTab.isGroup) {
      applyFeedTab(const FeedTabSelection(FeedTabItem.follow));
    }
    if (_feedTabKey.contains('group_')) {
      applyFeedTabKey(FeedTabItem.follow.key);
    }
  }

  /// 某个账号的首页栏目上次停在哪条微博：`<微博 id>,<卡片下标>,<项内偏移>`。
  ///
  /// 冷启动时先按 id 找回那一条，找不到（比如已经删了）再退回下标。
  ({String id, int index, int offset})? feedAnchor(String owner, String key) {
    final raw = _prefs.getString(_scopedScrollKey(owner, key));
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 3) return null;
    final index = int.tryParse(parts[1]);
    final offset = int.tryParse(parts[2]);
    if (index == null || offset == null) return null;
    return (
      id: parts[0],
      index: math.max(0, index),
      offset: math.max(0, offset),
    );
  }

  void applyFeedAnchor(
    String owner,
    String key,
    String id,
    int index,
    int offset,
  ) {
    _prefs.setString(
      _scopedScrollKey(owner, key),
      '${id.replaceAll(',', '')},${math.max(0, index)},${math.max(0, offset)}',
    );
  }

  void clearFeedScrolls() {
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith('scroll_')) _prefs.remove(key);
    }
  }

  void applyNearbyDevice() {
    _nearbyCustom = false;
    _prefs.setBool('nearby_custom', false);
    notifyListeners();
  }

  void applyNearbyPlace(String name, double lat, double lon) {
    _nearbyCustom = true;
    _nearbyPlaceName = name;
    _nearbyPlaceLat = lat;
    _nearbyPlaceLon = lon;
    _prefs
      ..setBool('nearby_custom', true)
      ..setString('nearby_place_name', name)
      ..setDouble('nearby_place_lat', lat)
      ..setDouble('nearby_place_lon', lon);
    notifyListeners();
  }

  void applyMonetCards(bool value) {
    _monetCards = value;
    _prefs.setBool('monet_cards', value);
    notifyListeners();
  }

  void applyBlurEffects(bool value) {
    _blurEffects = value;
    _prefs.setBool('blur_effects', value);
    notifyListeners();
  }

  void applyConfirmLike(bool value) {
    _confirmLike = value;
    _prefs.setBool('confirm_like', value);
    notifyListeners();
  }

  void applyQuickSwitchAccount(bool value) {
    _quickSwitchAccount = value;
    _prefs.setBool('quick_switch_account', value);
    notifyListeners();
  }

  void applyProfileTabAvatar(bool value) {
    _profileTabAvatar = value;
    _prefs.setBool('profile_tab_avatar', value);
    notifyListeners();
  }

  void applyReverseBrowse(bool value) {
    _reverseBrowse = value;
    _prefs.setBool('reverse_browse', value);
    notifyListeners();
  }

  void applyImageBrowseQuality(ImageBrowseQuality value) {
    _imageBrowseQuality = value;
    _prefs.setString('image_browse_quality', value.key);
    notifyListeners();
  }

  void applyVideoSpeed(VideoSpeed value) {
    _videoSpeed = value;
    _prefs.setDouble('video_speed', value.rate);
    notifyListeners();
  }

  void applyIconShape(AppIconShape value) {
    _iconShape = value;
    _prefs.setString('icon_shape', value.key);
    notifyListeners();
  }

  void applyHotBoards(Set<HotBoard> value) {
    _hotBoards = {
      for (final board in HotBoard.values)
        if (value.contains(board)) board,
    };
    _prefs.setString(
      'hot_boards',
      _hotBoards.map((b) => b.filterType).join(','),
    );
    notifyListeners();
  }

  void applyLocalFollowUid(String uid) {
    _localFollowUid = uid;
    _prefs.setString('local_follow_uid', uid);
    notifyListeners();
  }

  void applyLocalMode(bool value) {
    _localMode = value;
    _prefs.setBool('local_mode', value);
    notifyListeners();
  }

  void applyUpdateCheckedAt(int value) {
    _updateCheckedAt = value;
    _prefs.setInt('update_checked_at', value);
  }

  void applySkippedUpdate(String value) {
    _skippedUpdate = value;
    _prefs.setString('skipped_update', value);
    notifyListeners();
  }

  void applyAutoCheckUpdate(bool value) {
    _autoCheckUpdate = value;
    _prefs.setBool('auto_check_update', value);
    notifyListeners();
  }

  void applyUpdateCache(String etag, String body) {
    _updateEtag = etag;
    _updateCache = body;
    _prefs
      ..setString('update_etag', etag)
      ..setString('update_cache', body);
  }

  void applyDarkMode(int value) {
    _darkMode = value % 3;
    _prefs.setInt('dark_mode', _darkMode);
    notifyListeners();
  }

  void applyFontScale(double value) {
    final normalized = normalizeFontScale(value);
    if ((normalized - _fontScale).abs() < 0.001) return;
    _fontScale = normalized;
    _prefs.setDouble('font_scale', normalized);
    notifyListeners();
  }

  void applyFontWeightDelta(int value) {
    final normalized = normalizeFontWeightDelta(value);
    if (normalized == _fontWeightDelta) return;
    _fontWeightDelta = normalized;
    _prefs.setInt('font_weight_delta', normalized);
    notifyListeners();
  }

  void resetTypography() {
    if ((_fontScale - 1.0).abs() < 0.001 && _fontWeightDelta == 0) return;
    _fontScale = 1.0;
    _fontWeightDelta = 0;
    _prefs
      ..setDouble('font_scale', 1.0)
      ..setInt('font_weight_delta', 0);
    notifyListeners();
  }

  void applyAccentColor(int argb) {
    final normalized = (argb == 0 || argb == accentHueCycle)
        ? argb
        : (argb | 0xFF000000);
    _accentColor = normalized;
    _prefs.setInt('accent_color', normalized);
    notifyListeners();
  }

  double cycleFontScale() {
    const scales = [0.85, 1.0, 1.15, 1.3];
    final index = scales.indexWhere((s) => (s - _fontScale).abs() < 0.01);
    final next = scales[(index < 0 ? 1 : index + 1) % scales.length];
    applyFontScale(next);
    return next;
  }

  int cycleDarkMode() {
    final next = (_darkMode + 1) % 3;
    applyDarkMode(next);
    return next;
  }

  static String _scopedScrollKey(String owner, String key) =>
      'scroll_v2_${owner.isEmpty ? 'guest' : owner}_$key';
}

/// `null` 表示从没设置过（默认全部显示）；空串表示用户明确全不勾，热搜区块隐藏。
Set<HotBoard> parseHotBoards(String? raw) {
  if (raw == null) return HotBoard.values.toSet();
  if (raw.trim().isEmpty) return {};
  final keys = raw.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toSet();
  return {
    for (final board in HotBoard.values)
      if (keys.contains(board.filterType)) board,
  };
}

List<String> parseSearchHistoryJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <String>[];
    for (final item in decoded) {
      final text = item.toString().trim();
      if (text.isNotEmpty && !out.contains(text)) out.add(text);
    }
    return out;
  } on Object {
    return const [];
  }
}

String encodeSearchHistoryJson(List<String> history) => jsonEncode(history);
