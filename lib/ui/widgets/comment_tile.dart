import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import 'common.dart';
import 'glyphs.dart';
import 'press_scale.dart';
import 'remote_image.dart';
import 'status_card.dart' show PicGrid;
import 'weibo_text.dart';

/// 一条评论，按 TiebaFrosted 的楼层卡片排版：
///
/// 头像 + 昵称 + 身份标签 +「楼层 · 时间 · 来源」在顶上，正文、配图、
/// 被回复内容、楼中楼预览依次往下，底部一排胶囊按钮（赞 / 回复）。
/// [nested] 是楼中楼里的单条回复，同一个排版收小一号。
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.authorId = '',
    this.floor,
    this.onReply,
    this.onLike,
    this.onUser,
    this.onLink,
    this.onOpenImage,
    this.onLongPressImage,
    this.onOpenReplies,
    this.onLongPress,
    this.nested = false,
  });

  final Comment comment;

  /// 微博作者 uid：用来在评论和回复上打「博主」标。
  final String authorId;

  /// 楼层号（详情页从 1 开始）。楼中楼的单条回复不显示。
  final int? floor;

  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final ValueChanged<User>? onUser;
  final ValueChanged<String>? onLink;

  /// 点评论配图；长按出「看原图 / 存到相册」。
  final void Function(List<Pic> pics, int index)? onOpenImage;
  final void Function(List<Pic> pics, int index)? onLongPressImage;
  final VoidCallback? onOpenReplies;
  final VoidCallback? onLongPress;
  final bool nested;

  bool get _isAuthor =>
      authorId.isNotEmpty && comment.user?.id == authorId;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final user = comment.user;
    final meta = _metaText();
    final nameStyle = AppTextStyle.subheadline
        .of(context, emphasized: true)
        .copyWith(
          fontSize: nested ? 14 : 15,
          color: scheme.onSurface,
        );

    return Padding(
      padding: EdgeInsets.only(bottom: nested ? 8 : 10),
      child: HoboCard(
        padding: EdgeInsets.fromLTRB(
          nested ? 12 : 14,
          nested ? 10 : 12,
          nested ? 12 : 14,
          nested ? 6 : 6,
        ),
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(
                  url: user?.avatar ?? '',
                  size: nested ? 30 : 36,
                  onTap: user == null ? null : () => onUser?.call(user),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: user == null ? null : () => onUser?.call(user),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user?.name.isNotEmpty == true
                                    ? user!.name
                                    : '评论',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: nameStyle,
                              ),
                            ),
                            if (user?.verified == true) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(size: 13),
                            ],
                            if (user != null &&
                                user.membership != Membership.none) ...[
                              const SizedBox(width: 4),
                              MemberBadge(
                                svip: user.membership == Membership.svip,
                              ),
                            ],
                            if (_isAuthor) ...[
                              const SizedBox(width: 6),
                              const _AuthorBadge(),
                            ],
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
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: nested ? 6 : 8),
            WeiboText(
              html: comment.textHtml,
              style: AppTextStyle.body.of(context).copyWith(
                fontSize: nested ? 14 : 14.5,
                height: 1.42,
                color: scheme.onSurface,
              ),
              onLink: onLink,
              maxLines: 40,
            ),
            if (comment.pics.isNotEmpty) ...[
              const SizedBox(height: 8),
              // 评论配图比正文小一号，长按也能存原图。
              PicGrid(
                pics: comment.pics,
                onOpen: onOpenImage,
                onLongPress: onLongPressImage,
                hero: false,
                maxWidthFactor: nested ? 0.6 : 0.78,
              ),
            ],
            if (!nested && comment.reply != null) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '回复 @${comment.reply?.user?.name ?? ''}：',
                      style: TextStyle(color: scheme.primary),
                    ),
                    TextSpan(text: comment.reply!.plainText),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote.of(context).copyWith(
                  fontSize: 12.5,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
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
            const SizedBox(height: 4),
            Row(
              children: [
                _CommentAction(
                  glyph: HoboGlyphs.like,
                  label: comment.likes > 0 ? '${comment.likes}' : '赞',
                  active: comment.liked,
                  activeColor: scheme.error,
                  onTap: onLike,
                ),
                const SizedBox(width: 10),
                _CommentAction(
                  glyph: HoboGlyphs.comment,
                  label: '回复',
                  onTap: onReply,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _metaText() {
    final parts = <String>[
      if (floor != null && !nested) '$floor楼',
      if (comment.createdAt.isNotEmpty) formatWeiboTime(comment.createdAt),
      if (comment.source.isNotEmpty) comment.source,
      if (comment.region.isNotEmpty) '来自 ${comment.region}',
    ];
    return parts.where((part) => part.isNotEmpty).join(' · ');
  }
}

/// 楼层卡片底部那排胶囊按钮：图标 + 计数，激活时整颗变色。
class _CommentAction extends StatelessWidget {
  const _CommentAction({
    required this.glyph,
    required this.label,
    this.active = false,
    this.activeColor,
    this.onTap,
  });

  final Glyph glyph;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = active ? (activeColor ?? scheme.primary) : scheme.onSurfaceVariant;
    return PressScale(
      scale: 0.94,
      enabled: onTap != null,
      child: PressSurface(
        fill: const Color(0x00000000),
        shape: AppShape.full,
        onPressed: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(size: 16, color: color),
                  child: context.disableAnimations
                      ? GlyphIcon(glyph, fill: active ? 1 : 0)
                      : AnimatedGlyph(glyph: glyph, filled: active),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: AppTextStyle.footnote.of(context).copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 楼中楼预览：比卡片再深一档的圆角块，蓝名前缀，底部「查看全部 N 条回复」。
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
    return SurfaceScope(
      level: SurfaceLevel.card,
      child: Builder(
        builder: (context) {
          final scheme = context.colorScheme;
          final fill = context.raisedSurfaceLevel.colorOf(scheme);
          // 撑满正文宽度：块里是几行长短不一的回复，按内容收缩的话每层卡片
          // 宽窄都不一样，一列看下来像没对齐。
          return SizedBox(
            width: double.infinity,
            child: PressSurface(
              fill: fill,
              shape: AppShape.all(AppCorner.md),
              // 按压面默认是「围着内容收紧」的，这里要整块铺满、字从左边起排。
              childFills: true,
              onPressed: onOpenReplies,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final reply in replies.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: reply.user?.name ?? '',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (authorId.isNotEmpty &&
                                  reply.user?.id == authorId)
                                TextSpan(
                                  text: ' 博主',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              TextSpan(
                                text: '：${reply.plainText}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: AppTextStyle.footnote.of(context).copyWith(
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    if (total > replies.length || replies.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              replies.isEmpty
                                  ? '查看 $total 条回复'
                                  : '查看全部 $total 条回复',
                              style: AppTextStyle.caption1
                                  .of(context)
                                  .copyWith(
                                    fontSize: 12.5,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(width: 2),
                            GlyphIcon(
                              Glyphs.chevronForward,
                              size: 13,
                              color: scheme.primary,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
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
