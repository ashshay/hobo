import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_dirs.dart';
import 'data/api.dart';
import 'data/app_icon.dart';
import 'data/cache_store.dart';
import 'data/follow_tags.dart';
import 'data/repo.dart';
import 'data/settings.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = Settings(prefs);
  final dir = await appDataDir();
  final store = await Store.open(dir);
  final followTags = FollowTags(store);
  final repo = Repo(store: store, settings: settings, followTags: followTags);
  Api.cache = await CacheStore.instance();
  runApp(
    HoboApp(
      settings: settings,
      repo: repo,
      store: store,
      followTags: followTags,
    ),
  );
  // 冷启动后顺手把网页登录态续一次；纯本地模式则提前领一个访客身份。
  unawaited(repo.refreshSessionIfStale());
  // 桌面图标形状跟设置对齐（换过包、清过数据时两边会不一致；一致时这行什么都不做）。
  unawaited(AppIcon.sync(settings.iconShape));
  if (repo.guest) {
    unawaited(repo.visitorForStartup());
  }
}
