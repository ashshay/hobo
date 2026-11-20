import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import 'glyphs.dart' show HoboGlyphs;
import 'remote_image.dart';
import 'status_card.dart' show PicGrid;
import 'weibo_text.dart';

/// 一条评论。按微博官方的排版：头像在左，昵称 + 时间来源，正文，
/// 楼中楼用浅底块列几条，「共 N 条回复」可点；点赞爱心在右上角。
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.authorId = '',
    this.onReply,
    this.onLike,
    this.onUser,
    this.onLink,
    this.onOpenImage,
    this.onLongPressImage,
    this.onOpenReplies,
    this.nested = false,
    this.showDivider = true,
  });

  final Comment comment;

  /// 微博作者 uid：用来在评论和回复上打「博主」标。
  final String authorId;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final ValueChanged<User>? onUser;
  final ValueChanged<String>? onLink;

  /// 点评论配图；长按出「看原图 / 存到相册」。
  final void Function(List<Pic> pics, int index)? onOpenImage;
  final void Function(List<Pic> pics, int index)? onLongPressImage;
  final VoidCallback? onOpenReplies;
  final bool nested;
  final bool showDivider;

  bool get _isAuthor =>
      authorId.isNotEmpty && comment.user?.id == authorId;

  @override
  Widget build(BuildContext context) {
    final user = comment.user;
    final meta = _metaText();
    final body = Padding(
      padding: EdgeInsets.fromLTRB(0, nested ? 8 : 12, 0, nested ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            url: user?.avatar ?? '',
            size: nested ? 28 : 38,
            onTap: user == null ? null : () => onUser?.call(user),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: user == null ? null : () => onUser?.call(user),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                user?.name ?? '评论',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.subheadline
                                    .of(context)
                                    .copyWith(
                                      fontSize: nested ? 13 : 14,
                                      fontWeight: FontWeight.w500,
                                      color: context.colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                            if (user?.verified == true) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(size: 13),
                            ],
                            if (_isAuthor) ...[
                              const SizedBox(width: 4),
                              const _AuthorBadge(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 点赞爱心放在右上角，和官方评论区一致。
                    GestureDetector(
                      onTap: onLike,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconTheme.merge(
                              data: IconThemeData(
                                size: 15,
                                color: comment.liked
                                    ? context.colorScheme.error
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                              child: context.disableAnimations
                                  ? GlyphIcon(
                                      HoboGlyphs.like,
                                      fill: comment.liked ? 1 : 0,
                                    )
                                  : AnimatedGlyph(
                                      glyph: HoboGlyphs.like,
                                      filled: comment.liked,
                                    ),
                            ),
                            if (comment.likes > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '${comment.likes}',
                                style: AppTextStyle.caption1.of(context)
                                    .copyWith(
                                      fontSize: 11,
                                      color: comment.liked
                                          ? context.colorScheme.error
                                          : context.colorScheme
                                                .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption1.of(context).copyWith(
                      fontSize: 11.5,
                      color: context.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                WeiboText(
                  html: comment.textHtml,
                  style: AppTextStyle.body.of(context).copyWith(
                    fontSize: nested ? 13.5 : 14.5,
                    height: 1.42,
                    color: context.colorScheme.onSurface,
                  ),
                  onLink: onLink,
                  maxLines: 40,
                ),
                if (comment.pics.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  // 评论配图比正文小一号，长按也能存原图。
                  PicGrid(
                    pics: comment.pics,
                    onOpen: onOpenImage,
                    onLongPress: onLongPressImage,
                    hero: false,
                    maxWidthFactor: nested ? 0.55 : 0.78,
                  ),
                ],
                if (!nested && comment.reply != null) ...[
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '回复 @${comment.reply?.user?.name ?? ''}：',
                          style: TextStyle(
                            color: context.colorScheme.primary,
                          ),
                        ),
                        TextSpan(text: comment.reply!.plainText),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!nested && comment.replies.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ReplyBlock(
                    replies: comment.replies,
                    total: comment.replyCount,
                    authorId: authorId,
                    onOpenReplies: onOpenReplies,
                  ),
                ],
                if (!nested) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onReply,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlyphIcon(
                          Glyphs.chevronBack,
                          size: 12,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '回复',
                          style: AppTextStyle.caption1.of(context).copyWith(
                            fontSize: 11.5,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (!showDivider || nested) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        body,
        Container(
          height: 0.5,
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ],
    );
  }

  String _metaText() {
    final parts = <String>[
      if (comment.createdAt.isNotEmpty) formatWeiboTime(comment.createdAt),
      if (comment.source.isNotEmpty) comment.source,
      if (comment.region.isNotEmpty) '来自 ${comment.region}',
    ];
    return parts.where((part) => part.isNotEmpty).join(' ');
  }
}

/// 楼中楼预览：浅底圆角块，蓝名前缀，底部「共 N 条回复」。
class _ReplyBlock extends StatelessWidget {
  const _ReplyBlock({
    required this.replies,
    required this.total,
    required this.authorId,
    this.onOpenReplies,
  });

  final List<Comment> replies;
  final int total;
  final String authorId;
  final VoidCallback? onOpenReplies;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: ShapeDecoration(
        color: context.colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        shape: AppShape.all(AppCorner.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reply in replies.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${reply.user?.name ?? ''}',
                      style: TextStyle(color: context.colorScheme.primary),
                    ),
                    if (authorId.isNotEmpty && reply.user?.id == authorId)
                      TextSpan(
                        text: ' 博主',
                        style: TextStyle(
                          color: context.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    TextSpan(
                      text: '：${reply.plainText}',
                      style: TextStyle(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote.of(context).copyWith(
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          if (total > replies.length && onOpenReplies != null)
            GestureDetector(
              onTap: onOpenReplies,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '共 $total 条回复',
                  style: AppTextStyle.caption1.of(context).copyWith(
                    fontSize: 12,
                    color: context.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AuthorBadge extends StatelessWidget {
  const _AuthorBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: ShapeDecoration(
        color: context.colorScheme.primary.withValues(alpha: 0.14),
        shape: AppShape.xs,
      ),
      child: Text(
        '博主',
        style: AppTextStyle.caption2.of(context).copyWith(
          fontSize: 9.5,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: context.colorScheme.primary,
        ),
      ),
    );
  }
}
