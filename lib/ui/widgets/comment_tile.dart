import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import '../../data/settings.dart';
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
    this.style = CommentStyle.card,
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

  /// 一级评论的排版；楼中楼里的单条回复固定用小卡片。
  final CommentStyle style;

  bool get _isAuthor =>
      authorId.isNotEmpty && comment.user?.id == authorId;

  @override
  @override
  Widget build(BuildContext context) {
    // 楼中楼里的单条回复保持小卡片，只有一级评论跟随「评论区样式」。
    if (style == CommentStyle.merged && !nested) return _buildMerged(context);
    return _buildCard(context);
  }

  Widget _buildCard(BuildContext context) {
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
                _avatar(context),
                const SizedBox(width: 10),
                Expanded(
                  child: _nameRow(
                    context,
                    showMeta: true,
                    nameStyle: AppTextStyle.headline.of(context).copyWith(
                      color: context.colorScheme.onSurface,
                      fontWeight: FontWeightScope.resolve(
                        context,
                        FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: nested ? 6 : 8),
            _content(context),
            const SizedBox(height: 4),
            _actions(context),
          ],
        ),
      ),
    );
  }

  /// 融合样式：照 TiebaFrosted 的融合排版——没有卡片底，头像放大到 40，
  /// 昵称加粗、正文用正文级字号，时间与点赞落在同一行，楼中楼收成一条圆角横条。
  Widget _buildMerged(BuildContext context) {
    final scheme = context.colorScheme;
    final meta = _metaText();
    final replyTotal = comment.replyCount > 0
        ? comment.replyCount
        : comment.replies.length;
    final nameStyle = AppTextStyle.body.of(context).copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeightScope.resolve(context, FontWeight.w700),
    );
    final bodyStyle = AppTextStyle.body.of(
      context,
    ).copyWith(color: scheme.onSurface, height: 1.45);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(context, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _nameRow(context, showMeta: false, nameStyle: nameStyle),
                  const SizedBox(height: 6),
                  _content(context, bodyStyle: bodyStyle, showReplies: false),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (meta.isNotEmpty)
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.footnote.of(context).copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      const SizedBox(width: 8),
                      _MergedLikeButton(
                        likes: comment.likes,
                        liked: comment.liked,
                        onTap: onLike,
                      ),
                    ],
                  ),
                  if (replyTotal > 0 && onOpenReplies != null) ...[
                    const SizedBox(height: 10),
                    _MergedRepliesBar(
                      total: replyTotal,
                      onPressed: onOpenReplies,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, {double? size}) {
    final user = comment.user;
    final side = size ?? (nested ? 30.0 : 36.0);
    final url = user?.avatar ?? '';
    // 没头像的账号（以及设置里的预览样例）给一颗首字圆片，别留一个空洞。
    final Widget avatar = url.isEmpty
        ? Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: context.colorScheme.surfaceContainerHighest,
              shape: AppShape.full,
            ),
            child: Text(
              user != null && user.name.isNotEmpty
                  ? user.name.substring(0, 1)
                  : '评',
              style: TextStyle(
                fontSize: side * 0.4,
                fontWeight: FontWeight.w600,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : Avatar(url: url, size: side);
    if (user == null) return avatar;
    return GestureDetector(onTap: () => onUser?.call(user), child: avatar);
  }

  Widget _nameRow(
    BuildContext context, {
    required bool showMeta,
    TextStyle? nameStyle,
  }) {
    final scheme = context.colorScheme;
    final user = comment.user;
    final meta = _metaText();
    final style =
        nameStyle ??
        AppTextStyle.subheadline
            .of(context, emphasized: true)
            .copyWith(fontSize: nested ? 14 : 15, color: scheme.onSurface);
    return GestureDetector(
      onTap: user == null ? null : () => onUser?.call(user),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  user?.name.isNotEmpty == true ? user!.name : '评论',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              if (user?.verified == true) ...[
                const SizedBox(width: 4),
                const VerifiedBadge(size: 13),
              ],
              if (user != null && user.membership != Membership.none) ...[
                const SizedBox(width: 4),
                MemberBadge(svip: user.membership == Membership.svip),
              ],
              if (_isAuthor) ...[
                const SizedBox(width: 6),
                const _AuthorBadge(),
              ],
            ],
          ),
          if (showMeta && meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote.of(context).copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    TextStyle? bodyStyle,
    bool showReplies = true,
  }) {
    final scheme = context.colorScheme;
    final style =
        bodyStyle ??
        AppTextStyle.subheadline.of(context).copyWith(
          fontSize: nested ? 14 : 15,
          height: 1.45,
          color: scheme.onSurface,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WeiboText(
          html: comment.textHtml,
          style: style,
          onLink: onLink,
          maxLines: 40,
        ),
        if (comment.pics.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 评论配图比正文小一号，长按也能存原图。
          PicGrid(
            pics: comment.pics,
            heroScope: comment.id.isNotEmpty ? 'c:${comment.id}' : null,
            onOpen: onOpenImage,
            onLongPress: onLongPressImage,
            hero: comment.id.isNotEmpty,
            maxWidthFactor: nested ? 0.6 : 0.78,
          ),
        ],
        if (!nested && comment.reply != null) ...[
          const SizedBox(height: 8),
          WeiboText(
            html: _replyHtml(comment.reply!),
            maxLines: 3,
            onLink: onLink,
            style: AppTextStyle.footnote.of(context).copyWith(
              fontSize: 12.5,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (showReplies && !nested && comment.replies.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ReplyBlock(
            replies: comment.replies,
            total: comment.replyCount,
            authorId: authorId,
            onOpenReplies: onOpenReplies,
          ),
        ],
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
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
    );
  }

  String _replyHtml(Comment reply) {
    final user = reply.user;
    final name = user?.name ?? '';
    final target = user != null && user.id.isNotEmpty
        ? '<a href="/u/${user.id}">@$name</a>'
        : (name.isNotEmpty ? '<a href="/n/$name">@$name</a>' : '');
    final body = reply.textHtml.isNotEmpty ? reply.textHtml : reply.plainText;
    return target.isEmpty ? body : '回复 $target：$body';
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
          final bodyStyle = AppTextStyle.subheadline.of(context).copyWith(
            fontSize: 14,
            height: 1.42,
            color: scheme.onSurface,
          );
          final nameStyle = AppTextStyle.subheadline
              .of(context, emphasized: true)
              .copyWith(fontSize: 14, height: 1.42, color: scheme.primary);
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
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < replies.take(3).length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: replies[i].user?.name ?? '',
                                style: nameStyle,
                              ),
                              if (authorId.isNotEmpty &&
                                  replies[i].user?.id == authorId)
                                TextSpan(
                                  text: ' 楼主',
                                  style: nameStyle.copyWith(fontSize: 11.5),
                                ),
                              if (replies[i].reply?.user?.name.isNotEmpty == true)
                                TextSpan(
                                  text: ' 回复 ${replies[i].reply!.user!.name}',
                                  style: bodyStyle.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              TextSpan(text: '：', style: bodyStyle),
                              TextSpan(
                                text: replies[i].plainText,
                                style: bodyStyle,
                              ),
                            ],
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ],
                    if (total > replies.take(3).length || replies.isEmpty) ...[
                      if (replies.isNotEmpty) const SizedBox(height: 6),
                      Text(
                        replies.isEmpty
                            ? '查看 $total 条回复'
                            : '查看全部 $total 条回复',
                        style: AppTextStyle.footnote
                            .of(context, emphasized: true)
                            .copyWith(color: scheme.primary),
                      ),
                    ],
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

/// 融合样式的点赞：文字在前、拇指在后，贴在同一行右端（与 TiebaFrosted 一致）。
class _MergedLikeButton extends StatelessWidget {
  const _MergedLikeButton({
    required this.likes,
    required this.liked,
    this.onTap,
  });

  final int likes;
  final bool liked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = liked ? scheme.error : scheme.onSurfaceVariant;
    return PressScale(
      scale: 0.94,
      enabled: onTap != null,
      child: PressSurface(
        fill: const Color(0x00000000),
        shape: AppShape.full,
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '赞',
                style: AppTextStyle.footnote.of(context).copyWith(color: color),
              ),
              if (likes > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '$likes',
                  style: AppTextStyle.footnote
                      .of(context, emphasized: liked)
                      .copyWith(color: color),
                ),
              ],
              const SizedBox(width: 5),
              if (context.disableAnimations)
                GlyphIcon(
                  HoboGlyphs.like,
                  size: 17,
                  color: color,
                  fill: liked ? 1 : 0,
                )
              else
                IconTheme(
                  data: IconThemeData(size: 17, color: color),
                  child: AnimatedGlyph(glyph: HoboGlyphs.like, filled: liked),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 融合样式的楼中楼入口：一条铺满的圆角横条，取代卡片里的预览块。
class _MergedRepliesBar extends StatelessWidget {
  const _MergedRepliesBar({required this.total, this.onPressed});

  final int total;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return PressSurface(
      fill: context.surfaceLevel.next.colorOf(context.colorScheme),
      shape: AppShape.all(AppCorner.md),
      onPressed: onPressed,
      childFills: true,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(
            '查看全部 $total 条回复',
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(color: context.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}
