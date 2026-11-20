/// 微博正文是 HTML：`<a href>` 是链接，`<img alt="[可爱]">` 是表情，其余标签只影响排版。
/// 这里把它拆成「文本 / 链接 / 表情」三种片段，供纯文本摘要与富文本渲染共用。
library;

sealed class WeiboSegment {
  const WeiboSegment();
}

class WeiboTextSegment extends WeiboSegment {
  const WeiboTextSegment(this.text);

  final String text;
}

class WeiboLinkSegment extends WeiboSegment {
  const WeiboLinkSegment({required this.text, required this.url});

  final String text;
  final String url;
}

class WeiboEmojiSegment extends WeiboSegment {
  const WeiboEmojiSegment({required this.alt, required this.url});

  final String alt;
  final String url;
}

final _token = RegExp(
  r'''<a\b([^>]*)>([\s\S]*?)</a>|<img\b([^>]*)>|</?([a-zA-Z][\w-]*)\b[^>]*>''',
  caseSensitive: false,
);
final _tag = RegExp(r'<[^>]*>');
final _attr = RegExp(r'''([\w-]+)\s*=\s*"([^"]*)"''');
final _numericEntity = RegExp(r'&#(\d+);');
final _hexEntity = RegExp(r'&#[xX]([0-9a-fA-F]+);');

const _namedEntities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00A0',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'middot': '·',
};

/// 微博偶尔把数字实体重复转义（`&amp;#10;`），先一层层剥掉，换行和文字才不会被当成字面量。
String normalizeWeiboHtml(String html) {
  var normalized = html;
  for (var i = 0; i < 4; i++) {
    final next = normalized.replaceAllMapped(
      RegExp(r'&amp;#(\d+);'),
      (m) => '&#${m[1]};',
    );
    if (next == normalized) break;
    normalized = next;
  }
  return normalized;
}

String decodeHtmlEntities(String input) {
  if (!input.contains('&')) return input;
  var out = input.replaceAllMapped(_numericEntity, (m) {
    final code = int.tryParse(m[1]!);
    if (code == null || code <= 0 || code > 0x10FFFF) return m[0]!;
    return String.fromCharCode(code);
  });
  out = out.replaceAllMapped(_hexEntity, (m) {
    final code = int.tryParse(m[1]!, radix: 16);
    if (code == null || code <= 0 || code > 0x10FFFF) return m[0]!;
    return String.fromCharCode(code);
  });
  return out.replaceAllMapped(
    RegExp(r'&(\w+);'),
    (m) => _namedEntities[m[1]!.toLowerCase()] ?? m[0]!,
  );
}

String _cleanText(String text) {
  return decodeHtmlEntities(text)
      .replaceAll('\uFFFC', '')
      .replaceAll('\u200B', '')
      .replaceAll('\uFEFF', '')
      .replaceAll('\u00A0', ' ');
}

Map<String, String> _attributesOf(String source) {
  final out = <String, String>{};
  for (final match in _attr.allMatches(source)) {
    out[match[1]!.toLowerCase()] = match[2]!;
  }
  return out;
}

String _absoluteImageUrl(String url) {
  final trimmed = decodeHtmlEntities(url).trim();
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  if (trimmed.startsWith('http')) return trimmed;
  if (trimmed.isEmpty) return '';
  return 'https://wx1.sinaimg.cn/thumb150/$trimmed';
}

/// HTML → 片段列表。链接里嵌套的标签会被压平成文字，链接本身保留可点。
List<WeiboSegment> parseWeiboHtml(String html) {
  final source = normalizeWeiboHtml(html);
  final segments = <WeiboSegment>[];
  final buffer = StringBuffer();
  var cursor = 0;

  void flush() {
    if (buffer.isEmpty) return;
    final text = _cleanText(buffer.toString());
    buffer.clear();
    if (text.isEmpty) return;
    segments.add(WeiboTextSegment(text));
  }

  for (final match in _token.allMatches(source)) {
    if (match.start > cursor) {
      buffer.write(source.substring(cursor, match.start));
    }
    cursor = match.end;
    final anchorAttrs = match[1];
    final anchorBody = match[2];
    final imageAttrs = match[3];
    if (anchorAttrs != null && anchorBody != null) {
      flush();
      final url = decodeHtmlEntities(_attributesOf(anchorAttrs)['href'] ?? '').trim();
      final text = _cleanText(anchorBody.replaceAll(_tag, '')).trim();
      if (text.isEmpty) continue;
      if (url.isEmpty) {
        segments.add(WeiboTextSegment(text));
      } else {
        segments.add(WeiboLinkSegment(text: text, url: url));
      }
      continue;
    }
    if (imageAttrs != null) {
      flush();
      final attrs = _attributesOf(imageAttrs);
      final alt = _cleanText(attrs['alt'] ?? '').trim();
      final url = _absoluteImageUrl(attrs['src'] ?? '');
      if (alt.isNotEmpty && url.isNotEmpty) {
        segments.add(WeiboEmojiSegment(alt: alt, url: url));
      } else if (alt.isNotEmpty) {
        segments.add(WeiboTextSegment(alt));
      }
      continue;
    }
    final name = (match[4] ?? '').toLowerCase();
    // 段落只在闭合处换行：`<p>` 与 `</p>` 都换会多出一行空行。
    if (name == 'br' || (name == 'p' && match[0]!.startsWith('</'))) {
      buffer.write('\n');
    }
  }
  if (cursor < source.length) {
    buffer.write(source.substring(cursor));
  }
  flush();
  return segments;
}

/// 纯文本：链接只留文字，表情留 alt。
String stripHtml(String? html) {
  if (html == null || html.trim().isEmpty) return '';
  return parseWeiboHtml(html)
      .map(
        (segment) => switch (segment) {
          WeiboTextSegment(:final text) => text,
          WeiboLinkSegment(:final text) => text,
          WeiboEmojiSegment(:final alt) => alt,
        },
      )
      .join()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 私信正文里的 emoji 是 `<img alt="[可爱]">`，纯文本要换成 alt 文本而不是占位符。
String chatPlainText(String? html) => stripHtml(html);

/// 正文里 `#话题#` 与 `@昵称` 的提取，用于发布前的联想与高亮。
final weiboTopicPattern = RegExp(r'#([^#\s]{1,40})#');
final weiboMentionPattern = RegExp(r'@([\u4e00-\u9fa5\w\-]{1,30})');
