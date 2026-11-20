import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/html_text.dart';

/// 微博正文的富文本：链接可点，`<img>` 表情按行高内联成图片。
///
/// 识别器要手动释放，否则每次重建都会漏一批 GestureRecognizer。
class WeiboText extends StatefulWidget {
  const WeiboText({
    super.key,
    required this.html,
    this.style,
    this.maxLines = 200,
    this.onLink,
    this.onLinkSegment,
    this.linkColor,
    this.textAlign = TextAlign.start,
  });

  final String html;
  final TextStyle? style;
  final int maxLines;
  final ValueChanged<String>? onLink;

  /// 需要链接文字时用这个（「查看图片」要直接进看图页）；给了它就不再走 [onLink]。
  final void Function(String url, String text)? onLinkSegment;
  final Color? linkColor;
  final TextAlign textAlign;

  @override
  State<WeiboText> createState() => _WeiboTextState();
}

class _WeiboTextState extends State<WeiboText> {
  final List<TapGestureRecognizer> _recognizers = [];
  String? _builtHtml;
  TextStyle? _builtStyle;
  int? _builtMaxLines;
  Color? _builtLinkColor;
  TextSpan? _span;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// 识别器是缓存的，回调里现读 [widget]，避免拿到上一次 build 的闭包。
  void _handleLinkTap(String url, String text) {
    final segment = widget.onLinkSegment;
    if (segment != null) {
      segment(url, text);
      return;
    }
    widget.onLink?.call(url);
  }

  TextSpan _buildSpan(TextStyle style, Color linkColor) {
    final base = MediaQuery.textScalerOf(context);
    final fontSize = style.fontSize ?? 15;
    final emojiSize = base.scale(fontSize) * 1.02;
    final spans = <InlineSpan>[];
    final segments = parseWeiboHtml(widget.html);
    if (segments.isEmpty) return TextSpan(text: '', style: style);
    for (final segment in segments) {
      switch (segment) {
        case WeiboTextSegment(:final text):
          spans.add(TextSpan(text: text));
        case WeiboLinkSegment(:final text, :final url):
          final tappable =
              widget.onLink != null || widget.onLinkSegment != null;
          TapGestureRecognizer? recognizer;
          if (tappable) {
            recognizer = TapGestureRecognizer()
              ..onTap = () => _handleLinkTap(url, text);
            _recognizers.add(recognizer);
          }
          spans.add(
            TextSpan(
              text: text,
              recognizer: recognizer,
              style: TextStyle(color: linkColor),
            ),
          );
        case WeiboEmojiSegment(:final alt, :final url):
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Image.network(
                  url,
                  width: emojiSize,
                  height: emojiSize,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Text(
                    alt,
                    style: TextStyle(fontSize: fontSize),
                  ),
                ),
              ),
            ),
          );
      }
    }
    return TextSpan(children: spans, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        widget.style ??
        AppTextStyle.body.of(context).copyWith(
          fontSize: 16,
          height: 1.45,
          color: context.colorScheme.onSurface,
        );
    final linkColor = widget.linkColor ?? context.colorScheme.primary;
    if (_span == null ||
        _builtHtml != widget.html ||
        _builtStyle != baseStyle ||
        _builtMaxLines != widget.maxLines ||
        _builtLinkColor != linkColor) {
      _disposeRecognizers();
      _span = _buildSpan(baseStyle, linkColor);
      _builtHtml = widget.html;
      _builtStyle = baseStyle;
      _builtMaxLines = widget.maxLines;
      _builtLinkColor = linkColor;
    }
    return Text.rich(
      _span!,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: baseStyle,
    );
  }
}
