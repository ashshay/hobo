/// 主页「更多」菜单里的三种关注标记，互斥，只存本机。
///
/// 微博网页端只给得出「特别关注」这一个状态（`status.user.special_follow`），
/// 悄悄关注与本地关注在 m.weibo.cn 上没有可写的接口，所以三档统一按本地标记处理。
library;

import 'package:flutter/foundation.dart';

import 'store.dart';

enum FollowTag {
  special('special', '特别'),
  secret('secret', '悄悄'),
  local('local', '本地');

  const FollowTag(this.key, this.label);

  final String key;
  final String label;

  /// 菜单里显示的文字：特别关注 / 悄悄关注 / 本地关注。
  String get menuLabel => '$label关注';

  static FollowTag? of(String? key) {
    for (final value in values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// 进程内的标记表：改完主页，信息流里同一张卡片立刻跟着变，不用重新拉数据。
class FollowTags extends ChangeNotifier {
  FollowTags(this._store) {
    _tags.addAll(_store.followTags());
  }

  final Store _store;
  final Map<String, FollowTag> _tags = {};

  FollowTag? operator [](String? uid) =>
      uid == null || uid.isEmpty ? null : _tags[uid];

  /// 有没有「记过」这件事：清掉标记也留一个空记录，免得服务端值把它补回来。
  bool has(String uid) => _tags.containsKey(uid) || _store.hasFollowTag(uid);

  /// 当前打了某个标记的全部 uid。
  List<String> uids(FollowTag tag) =>
      _tags.entries.where((e) => e.value == tag).map((e) => e.key).toList();

  void set(String uid, FollowTag? tag) {
    if (uid.isEmpty) return;
    if (tag == null) {
      _tags.remove(uid);
    } else {
      _tags[uid] = tag;
    }
    _store.setFollowTag(uid, tag);
    notifyListeners();
  }

  FollowTag? tagOf(String uid) => _tags[uid];
}
