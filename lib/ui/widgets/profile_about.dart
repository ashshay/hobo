import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import '../theme.dart' show formatCount;
import 'common.dart';
import 'glyphs.dart';
import 'remote_image.dart';

/// 「关于」栏目：认证、简介、数据与主页操作。
class ProfileAbout extends StatelessWidget {
  const ProfileAbout({
    super.key,
    required this.user,
    required this.isSelf,
    required this.onOpenRelations,
    required this.onCopyLink,
    required this.onOpenWeb,
    required this.onRefresh,
  });

  final User user;
  final bool isSelf;
  final ValueChanged<RelationKind> onOpenRelations;
  final VoidCallback onCopyLink;
  final VoidCallback onOpenWeb;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: ShapeDecoration(
              color: context.surfaceLevel.next.colorOf(scheme),
              shape: AppShape.all(hoboCardRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(url: user.avatar, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.headline
                                .of(context)
                                .copyWith(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                          ),
                          if (user.verified) const VerifiedBadge(size: 16),
                          if (user.membership != Membership.none)
                            MemberBadge(svip: user.svip),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'UID ${user.id}',
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (user.verifiedReason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          user.verifiedReason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: scheme.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (user.description.isNotEmpty)
          HoboSection(
            title: '简介',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Text(
                  user.description,
                  style: AppTextStyle.footnote
                      .of(context)
                      .copyWith(
                        fontSize: 14,
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                ),
              ),
            ],
          ),
        HoboSection(
          title: '数据',
          children: [
            HoboRow(
              title: '微博',
              trailing: _Count(value: user.statuses),
            ),
            HoboRow(
              title: '关注',
              showChevron: true,
              onPressed: () => onOpenRelations(RelationKind.following),
              trailing: _Count(value: user.friends),
            ),
            HoboRow(
              title: '粉丝',
              showChevron: true,
              onPressed: () => onOpenRelations(RelationKind.followers),
              trailing: _Count(value: user.followers),
            ),
            if (user.membership != Membership.none)
              HoboRow(
                title: '会员',
                trailing: MemberBadge(svip: user.svip),
              ),
          ],
        ),
        HoboSection(
          title: isSelf ? '我的主页' : '更多',
          children: [
            HoboRow(
              title: '复制主页链接',
              leading: const GlyphIcon(HoboGlyphs.link, size: 20),
              onPressed: onCopyLink,
            ),
            HoboRow(
              title: '在浏览器中打开',
              leading: const GlyphIcon(HoboGlyphs.openExternal, size: 20),
              onPressed: onOpenWeb,
            ),
            HoboRow(
              title: '刷新资料',
              leading: const GlyphIcon(HoboGlyphs.refresh, size: 20),
              onPressed: onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatCount(value),
      style: AppTextStyle.footnote
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    );
  }
}
