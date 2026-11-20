import 'package:flutter/foundation.dart';

/// 首页的「顶栏 / 底栏是否隐藏」与「刷新到最新」请求。
///
/// 信息流滚动时由 [FeedPage] 置位，外壳据此把顶栏和底栏一起滑走；
/// 双击底栏「微博」通过 [requestHomeRefresh] 刷新并回到最新一条。
class ChromeController extends ChangeNotifier {
  bool _hidden = false;
  int _homeRequests = 0;

  bool get hidden => _hidden;

  /// 双击底栏「微博」的累加计数，按钮在收不到命令时才复用。
  int get homeRequests => _homeRequests;

  void setHidden(bool value) {
    if (_hidden == value) return;
    _hidden = value;
    notifyListeners();
  }

  void requestHomeRefresh() {
    _homeRequests++;
    notifyListeners();
  }
}
