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
    this.showDivider = false,
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

  /// 非卡片式下是否在底部拉一条浅色分隔线（列表里除最后一条都给 true）。
  final bool showDivider;

  bool get _isAuthor =>
      authorId.isNotEmpty && comment.user?.id == authorId;

  @override
  Widget build(BuildContext context) {
    // 楼中楼里的单条回复保持原来的小卡片，只有一级评论跟随样式设置。
    if (style == CommentStyle.flat && !nested) return _buildFlat(context);
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
                Expanded(child: _nameRow(context, showMeta: true)),
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

  /// 非卡片式：照 Bifu 的图一样式——左头像、右侧昵称/正文/时间，末尾一行「时间 · 赞 · 回复」。
  /// [showDivider] 是列表给的：除了最后一条，底下拉一条浅色分隔线代替卡片边界。
  Widget _buildFlat(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(0, 2, 0, showDivider ? 14 : 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatar(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nameRow(context, showMeta: false),
                      const SizedBox(height: 4),
                      _content(context),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _metaText(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.caption1.of(context).copyWith(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _CommentAction(
                            glyph: HoboGlyphs.like,
                            label: comment.likes > 0 ? '${comment.likes}' : '赞',
                            active: comment.liked,
                            activeColor: scheme.error,
                            onTap: onLike,
                          ),
                          const SizedBox(width: 2),
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
              ],
            ),
          ),
        ),
        if (showDivider)
          Container(
            key: const ValueKey('comment-divider'),
            height: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
      ],
    );
  }

  Widget _avatar(BuildContext context) {
    final user = comment.user;
    final size = nested ? 30.0 : 36.0;
    final url = user?.avatar ?? '';
    // 没头像的账号（以及设置里的预览样例）给一颗首字圆片，别留一个空洞。
    final Widget avatar = url.isEmpty
        ? Container(
            width: size,
            height: size,
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
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : Avatar(url: url, size: size);
    if (user == null) return avatar;
    return GestureDetector(onTap: () => onUser?.call(user), child: avatar);
  }

  Widget _nameRow(BuildContext context, {required bool showMeta}) {
    final scheme = context.colorScheme;
    final user = comment.user;
    final meta = _metaText();
    final nameStyle = AppTextStyle.subheadline
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
                  style: nameStyle,
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
              style: AppTextStyle.caption1.of(context).copyWith(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (!nested && comment.replies.isNotEmpty) ...[
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
