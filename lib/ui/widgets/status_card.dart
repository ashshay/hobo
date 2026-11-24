import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/links.dart';
import '../../data/models.dart';
import '../theme.dart';
import 'common.dart';
import 'glyphs.dart';
import 'press_scale.dart';
import 'remote_image.dart';
import 'weibo_text.dart';

/// 缩略图与看图页共用的 Hero tag：点开缩略图时做放大动画。
String hoboPicHeroTag(String url) => 'hobo-pic:$url';

/// 一张图在卡片与看图页里用同一个 tag（缩略图优先，保证两边取到同一个 key）。
String picHeroTag(Pic pic) =>
    hoboPicHeroTag(pic.thumb.isNotEmpty ? pic.thumb : pic.large);

/// 正文里「查看图片」这类链接：点了直接进看图页，而不是跳网页或原微博。
const _viewImageLabels = {'查看图片', '查看大图', '查看原图'};

bool _isViewImageLink(String text) => _viewImageLabels.contains(text.trim());

/// 「查看图片」链接指向的那张图。微博把它包在 `sinaurl?u=` 里，解开后是
/// `sinaimg.cn/large/xxx.jpg` 这样的直链；解不出图片地址就返回 null。
Pic? _linkedPic(String url) {
  final resolved = unwrapSinaUrl(url) ?? url;
  if (!isImageLink(resolved)) return null;
  return Pic(thumb: resolved, large: resolved);
}

/// 点「查看图片」时该看哪几张：链接自己指向的那张优先，其次本条配图，
/// 最后退回转发原博的配图。
List<Pic> _viewImageTargets(Status status, String url) {
  final linked = _linkedPic(url);
  if (linked != null) return [linked];
  if (status.pics.isNotEmpty) return status.pics;
  return status.retweeted?.pics ?? const [];
}

/// prism 版微博卡片：头部（头像 / 昵称 / 时间来源）+ 正文 + 九宫格 + 视频 + 转发块 + 操作栏。
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    this.onOpen,
    this.onUser,
    this.onImage,
    this.onLongPressImage,
    this.onVideo,
    this.onLongPress,
    this.onLink,
    this.onLike,
    this.onComment,
    this.onRepost,
    this.onFavorite,
    this.onMore,
    this.onOpenQuoted,
    this.showActions = true,
    this.detail = false,
  });

  final Status status;
  final VoidCallback? onOpen;
  final ValueChanged<User>? onUser;
  final void Function(List<Pic> pics, int index)? onImage;

  /// 长按缩略图：看原图 / 存到相册 / 复制链接。
  final void Function(List<Pic> pics, int index)? onLongPressImage;
  final ValueChanged<VideoInfo>? onVideo;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onLink;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onRepost;
  final VoidCallback? onFavorite;
  final VoidCallback? onMore;

  /// 点转发块时打开被引用的原微博。
  final ValueChanged<Status>? onOpenQuoted;
  final bool showActions;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final user = status.user;
    return HoboCard(
      onPressed: onOpen,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(status: status, onUser: onUser),
          const SizedBox(height: 8),
          WeiboText(
            html: status.textHtml,
            style: AppTextStyle.body.of(context).copyWith(
              fontSize: 16,
              height: 1.42,
              color: context.colorScheme.onSurface,
            ),
            maxLines: detail ? 400 : 10,
            onLink: onLink,
            onLinkSegment: onLink == null
                ? null
                : (url, text) {
                    if (_isViewImageLink(text)) {
                      final pics = _viewImageTargets(status, url);
                      if (pics.isNotEmpty) {
                        onImage?.call(pics, 0);
                        return;
                      }
                    }
                    onLink?.call(url);
                  },
          ),
          if (status.visibility != null && !status.visibility!.isPublic) ...[
            const SizedBox(height: 8),
            _VisibilityTag(label: status.visibility!.label),
          ],
          if (status.pics.isNotEmpty) ...[
            const SizedBox(height: 10),
            PicGrid(
              pics: status.pics,
              onOpen: onImage,
              onLongPress: onLongPressImage,
            ),
          ],
          if (status.video != null) ...[
            const SizedBox(height: 10),
            _VideoBlock(
              video: status.video!,
              onTap: () => onVideo?.call(status.video!),
            ),
          ],
          if (status.bigPic != null) ...[
            const SizedBox(height: 10),
            _BigPicBlock(
              bigPic: status.bigPic!,
              onTap: () => onImage?.call(
                [Pic(thumb: status.bigPic!.url, large: status.bigPic!.url)],
                0,
              ),
            ),
          ],
          if (status.isVote && !detail) ...[
            const SizedBox(height: 10),
            _VoteTag(voteId: status.voteId),
          ],
          if (status.retweeted != null) ...[
            const SizedBox(height: 10),
            RetweetBlock(
              status: status.retweeted!,
              onOpen: onOpenQuoted == null
                  ? null
                  : () => onOpenQuoted!(status.retweeted!),
              onUser: onUser,
              onImage: onImage,
              onLongPressImage: onLongPressImage,
              onLink: onLink,
            ),
          ],
          if (showActions) ...[
            const SizedBox(height: 12),
            ActionRow(
              status: status,
              onLike: onLike,
              onComment: onComment,
              onRepost: onRepost,
              onFavorite: onFavorite,
              onMore: onMore,
              compact: !detail,
            ),
          ],
          if (user == null) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, this.onUser});

  final Status status;
  final ValueChanged<User>? onUser;

  @override
  Widget build(BuildContext context) {
    final user = status.user;
    final meta = joinMeta([
      formatWeiboTime(status.createdAt),
      // 「1小时前」这类相对时间再补一条准确发布时间。
      if (isRelativeWeiboTime(status.createdAt))
        formatWeiboTimeExact(status.createdAt),
      status.source,
      if (status.region.isNotEmpty) status.region,
    ]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Avatar(
          url: user?.avatar ?? '',
          size: 40,
          onTap: user == null ? null : () => onUser?.call(user),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: user == null ? null : () => onUser?.call(user),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user?.name ?? '微博',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.subheadline
                            .of(context, emphasized: true)
                            .copyWith(
                              fontSize: 15,
                              color: context.colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (user?.verified == true) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(),
                    ],
                    if (user != null && user.membership != Membership.none) ...[
                      const SizedBox(width: 4),
                      MemberBadge(svip: user.membership == Membership.svip),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1.of(context).copyWith(
                    fontSize: 12,
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (status.editCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '已编辑',
              style: AppTextStyle.caption1.of(context).copyWith(
                fontSize: 11,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _VisibilityTag extends StatelessWidget {
  const _VisibilityTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: context.colorScheme.primaryContainer.withValues(alpha: 0.6),
        shape: AppShape.full,
      ),
      child: Text(
        label,
        style: AppTextStyle.caption2.of(context).copyWith(
          fontSize: 11,
          color: context.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// 九宫格。单图按原图比例完整显示（竖图不裁切），两张/四张走两列，其余三列。
class PicGrid extends StatelessWidget {
  const PicGrid({
    super.key,
    required this.pics,
    this.onOpen,
    this.onLongPress,
    this.hero = true,
    this.maxWidthFactor = 1,
  });

  final List<Pic> pics;
  final void Function(List<Pic> pics, int index)? onOpen;

  /// 长按缩略图（看原图 / 存到相册）。
  final void Function(List<Pic> pics, int index)? onLongPress;

  /// 转发块里关掉 Hero：同一张图可能在本条与转发块里各出现一次，
  /// 同 tag 重复会让 Hero 断言失败。
  final bool hero;

  /// 整格最宽占可用宽度的比例：评论区的图比正文小一号。
  final double maxWidthFactor;

  int get _columns => pics.length == 1
      ? 1
      : (pics.length == 2 || pics.length == 4)
      ? 2
      : 3;

  @override
  Widget build(BuildContext context) {
    if (pics.isEmpty) return const SizedBox.shrink();
    final columns = _columns;
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final available = full * maxWidthFactor;
        if (pics.length == 1) {
          final pic = pics.first;
          final ratio = pic.width > 0 && pic.height > 0
              ? pic.width / pic.height
              : 3 / 4;
          // 竖图不放大、不裁切：按原比例缩到卡片左侧，和参考图的单图观感一致。
          final portrait = ratio < 1;
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: available,
              child: Row(
                children: [
                  Flexible(
                    child: FractionallySizedBox(
                      widthFactor: portrait ? 0.52 : 1.0,
                      alignment: AlignmentDirectional.centerStart,
                      child: _SinglePic(
                        pic: pic,
                        hero: hero,
                        aspectRatio: ratio.clamp(0.55, 2.2),
                        width: available * (portrait ? 0.52 : 1.0),
                        onTap: onOpen == null ? null : () => onOpen!(pics, 0),
                        onLongPress: onLongPress == null
                            ? null
                            : () => onLongPress!(pics, 0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // 卡片宽是确定的，按格宽下采样解码，九宫格不再整张原图进显存。
        final cellWidth = (available - 4.0 * (columns - 1)) / columns;
        final rows = <Widget>[];
        for (var row = 0; row * columns < pics.length; row++) {
          final slice = pics.skip(row * columns).take(columns).toList();
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 4),
              child: SizedBox(
                width: available,
                child: Row(
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) const SizedBox(width: 4),
                      Expanded(
                        child: col < slice.length
                            ? _PicTile(
                                pic: slice[col],
                                hero: hero,
                                width: cellWidth > 0 ? cellWidth : null,
                                onTap: onOpen == null
                                    ? null
                                    : () => onOpen!(
                                        pics,
                                        row * columns + col,
                                      ),
                                onLongPress: onLongPress == null
                                    ? null
                                    : () => onLongPress!(
                                        pics,
                                        row * columns + col,
                                      ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

/// 单图预览：按原图比例完整显示，竖图不裁切；用原图地址、按宽度解码保画质。
class _SinglePic extends StatelessWidget {
  const _SinglePic({
    required this.pic,
    required this.aspectRatio,
    required this.width,
    this.hero = true,
    this.onTap,
    this.onLongPress,
  });

  final Pic pic;
  final double aspectRatio;
  final double width;
  final bool hero;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final url = pic.large.isNotEmpty ? pic.large : pic.thumb;
    Widget image = RemoteImage(
      url: url,
      width: width,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      placeholderColor: context.colorScheme.surfaceContainerHighest,
    );
    if (hero) image = Hero(tag: picHeroTag(pic), child: image);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: PressScale(
        scale: hoboMediaPressScale,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(AppCorner.md),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (pic.isLive)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _LiveBadge(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const ShapeDecoration(
        color: Color(0x99000000),
        shape: AppShape.full,
      ),
      child: Text(
        'LIVE',
        style: AppTextStyle.caption2.of(context).copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

class _PicTile extends StatelessWidget {
  const _PicTile({
    required this.pic,
    this.hero = true,
    this.width,
    this.onTap,
    this.onLongPress,
  });

  final Pic pic;
  final bool hero;
  final double? width;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final url = pic.thumb.isNotEmpty ? pic.thumb : pic.large;
    Widget image = RemoteImage(
      url: url,
      width: width,
      height: null,
      fit: BoxFit.cover,
      placeholderColor: context.colorScheme.surfaceContainerHighest,
    );
    if (hero) image = Hero(tag: picHeroTag(pic), child: image);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: PressScale(
        scale: hoboMediaPressScale,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(AppCorner.md),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (pic.isLive)
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: _LiveBadge(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoBlock extends StatelessWidget {
  const _VideoBlock({required this.video, required this.onTap});

  final VideoInfo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PressScale(
        scale: hoboMediaPressScale,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(AppCorner.md),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RemoteImage(
                  url: video.cover,
                  fit: BoxFit.cover,
                  placeholderColor: const Color(0xFF1A1A1A),
                ),
                const Center(child: _PlayBadge()),
                if (video.title.isNotEmpty)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Text(
                      video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1.of(context).copyWith(
                        fontSize: 12,
                        color: const Color(0xFFFFFFFF),
                        shadows: const [
                          Shadow(color: Color(0x99000000), blurRadius: 4),
                        ],
                      ),
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

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: const ShapeDecoration(
        color: Color(0x73000000),
        shape: AppShape.full,
      ),
      child: const Padding(
        padding: EdgeInsets.only(left: 3),
        child: GlyphIcon(HoboGlyphs.play, size: 22, color: Color(0xFFFFFFFF)),
      ),
    );
  }
}

class _BigPicBlock extends StatelessWidget {
  const _BigPicBlock({required this.bigPic, required this.onTap});

  final BigPicInfo bigPic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PressScale(
        scale: hoboMediaPressScale,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(AppCorner.md),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: RemoteImage(url: bigPic.url, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _VoteTag extends StatelessWidget {
  const _VoteTag({this.voteId});

  final String? voteId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GlyphIcon(
          HoboGlyphs.vote,
          size: 16,
          color: context.colorScheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          '投票',
          style: AppTextStyle.caption1.of(context).copyWith(
            fontSize: 12,
            color: context.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class RetweetBlock extends StatelessWidget {
  const RetweetBlock({
    super.key,
    required this.status,
    this.onOpen,
    this.onUser,
    this.onImage,
    this.onLongPressImage,
    this.onLink,
  });

  final Status status;

  /// 点整块转发内容都进原微博，不只昵称可点。
  final VoidCallback? onOpen;
  final ValueChanged<User>? onUser;
  final void Function(List<Pic> pics, int index)? onImage;
  final void Function(List<Pic> pics, int index)? onLongPressImage;
  final ValueChanged<String>? onLink;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: ShapeDecoration(
          color: context.colorScheme.surfaceContainerHigh.withValues(
            alpha: 0.6,
          ),
          shape: AppShape.all(AppCorner.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: status.user == null
                  ? null
                  : () => onUser?.call(status.user!),
              child: Text(
                '@${status.user?.name ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption1.of(context).copyWith(
                  fontSize: 12,
                  color: context.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            WeiboText(
              html: status.textHtml,
              style: AppTextStyle.body.of(context).copyWith(
                fontSize: 14,
                height: 1.4,
                color: context.colorScheme.onSurfaceVariant,
              ),
              maxLines: 6,
              onLink: onLink,
              onLinkSegment: onLink == null
                  ? null
                  : (url, text) {
                      if (_isViewImageLink(text)) {
                        final pics = _viewImageTargets(status, url);
                        if (pics.isNotEmpty) {
                          onImage?.call(pics, 0);
                          return;
                        }
                      }
                      onLink?.call(url);
                    },
            ),
            if (status.pics.isNotEmpty) ...[
              const SizedBox(height: 6),
              PicGrid(
                pics: status.pics,
                onOpen: onImage,
                onLongPress: onLongPressImage,
                hero: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 操作栏：转发 / 评论 / 赞（详情页再加收藏与更多）。
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.status,
    this.onLike,
    this.compact = true,
    this.onComment,
    this.onRepost,
    this.onFavorite,
    this.onMore,
  });

  final Status status;
  final VoidCallback? onLike;
  final bool compact;
  final VoidCallback? onComment;
  final VoidCallback? onRepost;
  final VoidCallback? onFavorite;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    // 参考三组图标在卡片里均分宽度居中，右侧留给收藏与「更多」。
    return Row(
      children: [
        Expanded(
          child: Center(
            child: _ActionButton(
              glyph: HoboGlyphs.repost,
              label: compact ? '${status.reposts}' : '转发 ${status.reposts}',
              semanticLabel: '转发 ${status.reposts}',
              onPressed: onRepost,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionButton(
              glyph: HoboGlyphs.comment,
              label: compact ? '${status.comments}' : '评论 ${status.comments}',
              semanticLabel: '评论 ${status.comments}',
              onPressed: onComment,
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionButton(
              glyph: HoboGlyphs.like,
              label: compact ? '${status.attitudes}' : '赞 ${status.attitudes}',
              semanticLabel: status.liked
                  ? '取消赞 ${status.attitudes}'
                  : '赞 ${status.attitudes}',
              filled: status.liked,
              color: status.liked ? context.colorScheme.error : null,
              onPressed: onLike,
            ),
          ),
        ),
        if (onFavorite != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _ActionButton(
              glyph: HoboGlyphs.bookmark,
              label: status.favorited ? '已收藏' : '收藏',
              semanticLabel: status.favorited ? '取消收藏' : '收藏',
              filled: status.favorited,
              color: status.favorited ? context.colorScheme.primary : null,
              onPressed: onFavorite,
            ),
          ),
        if (onMore != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: GlyphIcon(
                HoboGlyphs.more,
                size: 20,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.glyph,
    required this.label,
    required this.semanticLabel,
    this.onPressed,
    this.color,
    this.filled = false,
  });

  final Glyph glyph;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;

  /// 描边图标在点亮时由外向内填满，而不是换一枚图标硬切。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionGlyph(glyph: glyph, filled: filled, color: tint),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyle.caption1.of(context).copyWith(
                  fontSize: 12,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图标本体：点亮时用 prism 的 [AnimatedGlyph] 做填充过渡，熄灭时直接画描边。
class _ActionGlyph extends StatelessWidget {
  const _ActionGlyph({
    required this.glyph,
    required this.filled,
    required this.color,
  });

  final Glyph glyph;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.merge(
      data: IconThemeData(color: color, size: 17),
      child: context.disableAnimations
          ? GlyphIcon(glyph, fill: filled ? 1 : 0)
          : AnimatedGlyph(glyph: glyph, filled: filled),
    );
    return icon;
  }
}
