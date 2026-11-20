/// 点赞的本地退避闸门。
///
/// 微博对写操作有频率上限，撞上会回 `errno 20016`「update weibo too fast」。
/// 关键是**继续重试会把限制窗口往后推**：撞一次就再等一会儿，比让用户每点一次
/// 都去问一次服务端要划算。所以撞上之后按指数退避停手，成功一次才清零。
class LikeGate {
  LikeGate({
    this.base = const Duration(seconds: 30),
    this.max = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// 第一次撞上的退避时长。
  final Duration base;

  /// 退避的上限。
  final Duration max;

  final DateTime Function() _now;

  Duration _backoff = Duration.zero;
  DateTime? _blockedUntil;

  /// 还在冷却期：本地直接拒绝，不发请求。
  bool get blocked {
    final until = _blockedUntil;
    return until != null && _now().isBefore(until);
  }

  /// 冷却还剩多久；没在冷却就是零。
  Duration get remaining {
    final until = _blockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// 服务端回了 20016：停手，下次撞上的等待时间翻倍。
  void onRejected() {
    _backoff = _backoff == Duration.zero
        ? base
        : Duration(
            milliseconds: (_backoff.inMilliseconds * 2).clamp(
              base.inMilliseconds,
              max.inMilliseconds,
            ),
          );
    _blockedUntil = _now().add(_backoff);
  }

  /// 成功一次：退避清零，恢复正常。
  void onAccepted() {
    _backoff = Duration.zero;
    _blockedUntil = null;
  }
}
