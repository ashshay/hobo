import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import 'common.dart';
import 'remote_image.dart';
import 'weibo_text.dart';

/// 消息中心里的一条通知卡片：谁 + 做了什么 + 相关微博的摘要。
/// 「@我的微博」不用这个，那里每条本身就是一条微博，走 [StatusCard]。
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.user,
    required this.action,
    required this.createdAt,
    this.html = '',
    this.status,
    this.onOpen,
    this.onUser,
    this.onLink,
  });

  final User? user;

  /// 「评论了你的微博」「赞了你的微博」这类。
  final String action;
  final String createdAt;

  /// 评论 / @ 的正文 HTML；赞没有正文。
  final String html;

  /// 相关微博，只取摘要显示。
  final Status? status;

  final VoidCallback? onOpen;
  final ValueChanged<User>? onUser;
  final ValueChanged<String>? onLink;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final author = user;
    return HoboCard(
      padding: const EdgeInsets.all(12),
      onPressed: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            url: author?.avatar ?? '',
            size: 38,
            onTap: author == null ? null : () => onUser?.call(author),
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
                        onTap: author == null ? null : () => onUser?.call(author),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                author?.name.isNotEmpty == true
                                    ? author!.name
                                    : '微博用户',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.subheadline.of(context)
                                    .copyWith(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                              ),
                            ),
                            if (author?.verified == true) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(size: 13),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatWeiboTime(createdAt),
                      style: AppTextStyle.caption1.of(context).copyWith(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  action,
                  style: AppTextStyle.caption1.of(context).copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (html.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  WeiboText(
                    html: html,
                    maxLines: 4,
                    style: AppTextStyle.body.of(context).copyWith(
                      fontSize: 14,
                      height: 1.4,
                      color: scheme.onSurface,
                    ),
                    onLink: onLink,
                  ),
                ],
                if (status != null) ...[
                  const SizedBox(height: 8),
                  _QuotedText(status: status!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 被评论 / 被赞的那条微博的摘要块，观感和转发块一致。
class _QuotedText extends StatelessWidget {
  const _QuotedText({required this.status});

  final Status status;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final name = status.user?.name ?? '';
    final text = status.plainText.trim();
    final summary = text.isEmpty
        ? (status.pics.isNotEmpty ? '[图片]' : '')
        : text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        shape: AppShape.all(AppCorner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Text(
              '@$name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption1.of(context).copyWith(
                fontSize: 12,
                color: scheme.primary,
              ),
            ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.body.of(context).copyWith(
                fontSize: 13,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
