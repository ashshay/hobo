/// 微博表情。接口 `weibo.com/ajax/statuses/config` 给全量分组；拿不到时用内置的常用表情兜底。
library;

import 'json.dart';

class WeiboEmoji {
  const WeiboEmoji(this.phrase, [this.url = '']);

  final String phrase;
  final String url;
}

class EmojiSection {
  const EmojiSection(this.label, this.items);

  final String label;
  final List<WeiboEmoji> items;
}

const _fallbackPhrases = <String>[
  '[微笑]', '[嘻嘻]', '[哈哈]', '[可爱]', '[可怜]', '[挖鼻]', '[吃惊]', //
  '[害羞]', '[挤眼]', '[闭嘴]', '[鄙视]', '[爱你]', '[泪]', '[偷笑]',
  '[亲亲]', '[生病]', '[太开心]', '[白眼]', '[右哼哼]', '[左哼哼]', '[嘘]',
  '[衰]', '[委屈]', '[吐]', '[哈欠]', '[抱抱]', '[怒]', '[疑问]',
  '[馋嘴]', '[拜拜]', '[思考]', '[汗]', '[困]', '[睡]', '[钱]',
  '[失望]', '[酷]', '[色]', '[哼]', '[鼓掌]', '[晕]', '[悲伤]',
  '[抓狂]', '[黑线]', '[阴险]', '[怒骂]', '[互粉]', '[心]', '[伤心]',
  '[猪头]', '[熊猫]', '[兔子]', '[ok]', '[耶]', '[good]', '[NO]',
  '[赞]', '[来]', '[弱]', '[囧]', '[浮云]', '[给力]', '[围观]',
  '[威武]', '[礼物]', '[蜡烛]', '[蛋糕]', '[doge]', '[二哈]', '[允悲]',
  '[笑cry]', '[摊手]', '[抱拳]', '[吃瓜]', '[打call]', '[酸]', '[苦涩]',
  '[破防]', '[裂开]', '[求饶]', '[老师好]', '[打脸]', '[跪了]', '[并不简单]',
];

const _fallbackUnicode = <String>[
  '😀', '😁', '😂', '🤣', '😃', '😄', '😅', '😆', '😉', '😊', //
  '😋', '😎', '😍', '😘', '😗', '😙', '😚', '🙂', '🤗', '🤩',
  '🤔', '🤨', '😐', '😑', '😶', '🙄', '😏', '😣', '😥', '😮',
  '🤐', '😯', '😪', '😫', '🥱', '😴', '😌', '😛', '😜', '😝',
  '🤤', '😒', '😓', '😔', '😕', '🙃', '🤑', '😲', '🙁', '😖',
  '😞', '😟', '😤', '😢', '😭', '😦', '😧', '😨', '😩', '🤯',
  '😬', '😰', '😱', '🥵', '🥶', '😳', '🤪', '😵', '🥴', '😠',
  '😡', '🤬', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '😇', '🥳',
  '🥺', '🤠', '🤡', '🤥', '🤫', '🤭', '🧐', '🤓', '😈', '👿',
  '💀', '👻', '👽', '🤖', '💩', '😺', '😸', '😹', '😻', '😼',
];

final List<EmojiSection> fallbackEmojiSections = [
  EmojiSection('常用微博', [for (final p in _fallbackPhrases) WeiboEmoji(p)]),
  EmojiSection('Emoji', [for (final e in _fallbackUnicode) WeiboEmoji(e)]),
];

List<EmojiSection> parseWeiboEmotions(Map<String, dynamic>? root) {
  final zhCn = root
      ?.obj('data')
      ?.obj('emoticon')
      ?.obj('ZH_CN');
  if (zhCn == null) return const [];
  final sections = <EmojiSection>[];
  for (final entry in zhCn.entries) {
    final arr = jArr(entry.value);
    if (arr == null) continue;
    final seen = <String>{};
    final items = <WeiboEmoji>[];
    for (final item in arr) {
      final o = jObj(item);
      if (o == null) continue;
      final phrase = o.str('phrase').trim();
      if (phrase.isEmpty || !seen.add(phrase)) continue;
      final rawUrl = o.str('url').trim();
      final url = rawUrl.startsWith('//')
          ? 'https:$rawUrl'
          : rawUrl.startsWith('http://')
          ? 'https://${rawUrl.substring(7)}'
          : rawUrl;
      items.add(WeiboEmoji(phrase, url));
    }
    if (items.isEmpty) continue;
    final label = entry.key.trim();
    sections.add(
      EmojiSection(label == 'PC热门表情' ? '热门' : label, items),
    );
  }
  if (sections.isNotEmpty) {
    sections.add(
      EmojiSection('Emoji', [for (final e in _fallbackUnicode) WeiboEmoji(e)]),
    );
  }
  return sections;
}

/// 已加载表情的 `[短语] → 图片地址` 映射，发布页插入表情时用。
Map<String, String> emojiUrlIndex(List<EmojiSection> sections) {
  final out = <String, String>{};
  for (final section in sections) {
    for (final item in section.items) {
      if (item.url.isNotEmpty) out.putIfAbsent(item.phrase, () => item.url);
    }
  }
  return out;
}
