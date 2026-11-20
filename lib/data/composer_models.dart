/// 发布页的可见范围、话题联想，以及 `@` / `#` 触发词的识别与替换。
library;

import 'json.dart';

enum WeiboVisibility {
  public(0, '公开', '所有人可见'),
  circle(6, '好友圈', '仅互关好友可见'),
  self(1, '私密', '仅自己可见');

  const WeiboVisibility(this.code, this.label, this.summary);

  final int code;
  final String label;
  final String summary;

  static WeiboVisibility fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return public;
  }
}

class TopicSuggestion {
  const TopicSuggestion(this.title, {this.desc = '', this.icon = ''});

  final String title;
  final String desc;
  final String icon;
}

sealed class ComposerTrigger {
  const ComposerTrigger({
    required this.replaceStart,
    required this.replaceEnd,
    required this.query,
  });

  final int replaceStart;
  final int replaceEnd;
  final String query;
}

class MentionTrigger extends ComposerTrigger {
  const MentionTrigger({
    required super.replaceStart,
    required super.replaceEnd,
    required super.query,
  });
}

class TopicTrigger extends ComposerTrigger {
  const TopicTrigger({
    required super.replaceStart,
    required super.replaceEnd,
    required super.query,
    required this.hasClosingHash,
  });

  final bool hasClosingHash;
}

/// 光标前是不是正在输入 `@昵称` 或 `#话题`。
ComposerTrigger? detectComposerTrigger(String text, int cursor) {
  final safeCursor = cursor.clamp(0, text.length);
  if (safeCursor == 0) return null;

  var i = safeCursor - 1;
  while (i >= 0) {
    final ch = text[i];
    if (ch == '@') {
      final query = text.substring(i + 1, safeCursor);
      if (query.length <= 30 && !query.contains(RegExp(r'\s'))) {
        return MentionTrigger(
          replaceStart: i,
          replaceEnd: safeCursor,
          query: query,
        );
      }
      break;
    }
    if (ch.trim().isEmpty || ch == '#' || ch == '[' || ch == ']') break;
    if (safeCursor - i > 30) break;
    i--;
  }

  final newlineAt = text.lastIndexOf('\n', safeCursor - 1);
  final lineStart = newlineAt < 0 ? 0 : newlineAt + 1;
  var hashCount = 0;
  var lastHash = -1;
  for (var pos = lineStart; pos < safeCursor; pos++) {
    if (text[pos] == '#') {
      hashCount++;
      lastHash = pos;
    }
  }
  if (hashCount.isOdd && lastHash >= 0) {
    final query = text.substring(lastHash + 1, safeCursor);
    if (query.length <= 40 && !query.contains('@')) {
      final hasClosingHash = safeCursor < text.length && text[safeCursor] == '#';
      return TopicTrigger(
        replaceStart: lastHash,
        replaceEnd: hasClosingHash ? safeCursor + 1 : safeCursor,
        query: query,
        hasClosingHash: hasClosingHash,
      );
    }
  }
  return null;
}

/// 把选中的联想词替换进正文，返回新正文与新的光标位置。
({String text, int cursor}) applyComposerReplacement(
  String text,
  ComposerTrigger trigger,
  String chosenValue,
) {
  final start = trigger.replaceStart.clamp(0, text.length);
  final end = trigger.replaceEnd.clamp(start, text.length);
  final token = switch (trigger) {
    MentionTrigger() => '@${chosenValue.trim().replaceFirst(RegExp(r'^@'), '')} ',
    TopicTrigger() =>
      '#${chosenValue.trim().replaceAll(RegExp(r'^#+|#+$'), '')}# ',
  };
  final next = text.substring(0, start) + token + text.substring(end);
  return (text: next, cursor: start + token.length);
}

List<TopicSuggestion> parseHotspotTopics(Map<String, dynamic>? root) {
  if (root == null || root.intOf('ok') != 1) return const [];
  final arr = root.arr('data');
  if (arr == null) return const [];
  final seen = <String>{};
  final out = <TopicSuggestion>[];
  for (final item in arr) {
    final o = jObj(item);
    if (o == null) continue;
    var title = o.str('title').trim().replaceAll(RegExp(r'^#+|#+$'), '');
    if (title.isEmpty) {
      title = o.str('content').trim().replaceAll(RegExp(r'^#+|#+$'), '');
    }
    if (title.isEmpty || !seen.add(title)) continue;
    var desc = o.str('description').trim();
    if (desc.isEmpty) desc = o.str('category_name').trim();
    var icon = o.str('image').trim();
    if (icon.isEmpty) icon = o.str('icon').trim();
    out.add(TopicSuggestion(title, desc: desc, icon: icon));
  }
  return out;
}
