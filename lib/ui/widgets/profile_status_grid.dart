import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import '../theme.dart' show formatCount, sizedImageUrl;
import 'common.dart';
import 'glyphs.dart';
import 'remote_image.dart';

/// 「微博」栏目的网格视图：两列，有图先铺图，没图就是一块纯文字。
class ProfileStatusGrid extends StatelessWidget {
  const ProfileStatusGrid({
    super.key,
    required this.statuses,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<Status> statuses;
  final ValueChanged<Status> onOpen;
  final ValueChanged<Status> onLongPress;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 198,
        ),
        itemCount: statuses.length,
        itemBuilder: (context, index) {
          final status = statuses[index];
          return _StatusTile(
            key: ValueKey(status.id),
            status: status,
            onTap: () => onOpen(status),
            onLongPress: () => onLongPress(status),
          );
        },
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    super.key,
    required this.status,
    required this.onTap,
    required this.onLongPress,
  });

  final Status status;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static const double _mediaHeight = 118;

  String get _cover {
    String pick(Status value) {
      if (value.pics.isNotEmpty) return value.pics.first.large;
      final video = value.video;
      if (video != null) return video.cover;
      final retweeted = value.retweeted;
      if (retweeted != null) return pick(retweeted);
      return '';
    }

    return pick(status);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final cover = _cover;
    final hasVideo = status.video != null || status.retweeted?.video != null;
    return HoboCard(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cover.isEmpty)
            Expanded(
              child: ColoredBox(
                color: context.surfaceLevel.next.next.colorOf(scheme),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  child: Text(
                    status.plainText,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(
                          fontSize: 12.5,
                          height: 1.4,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: _mediaHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RemoteImage(
                    url: sizedImageUrl(cover, 480),
                    fit: BoxFit.cover,
                    placeholderColor: context.surfaceLevel.next.next.colorOf(
                      scheme,
                    ),
                  ),
                  if (hasVideo)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const ShapeDecoration(
                          color: Color(0x66000000),
                          shape: AppShape.full,
                        ),
                        child: const Center(
                          child: GlyphIcon(
                            HoboGlyphs.play,
                            size: 14,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(
                status.plainText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(
                      fontSize: 12.5,
                      height: 1.35,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            const Spacer(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                _Stat(glyph: HoboGlyphs.likeOutline, value: status.attitudes),
                const SizedBox(width: 10),
                _Stat(glyph: HoboGlyphs.comment, value: status.comments),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.glyph, required this.value});

  final Glyph glyph;
  final int value;

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(glyph, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          formatCount(value),
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(fontSize: 10.5, color: color),
        ),
      ],
    );
  }
}
