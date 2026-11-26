import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../data/models.dart';
import 'glyphs.dart';
import 'remote_image.dart';

/// 主页「相册」的分页控制器。和 [FeedController] 一样只有刷新 / 续页两件事，
/// 只是条目换成照片。
class AlbumController extends ChangeNotifier {
  AlbumController(this._loader);

  final Future<AlbumPage> Function(String? cursor, {required bool force})
  _loader;

  final List<AlbumPhoto> photos = [];
  String? _cursor;
  bool _started = false;
  bool _disposed = false;

  bool loading = false;
  bool loadingMore = false;
  bool refreshing = false;
  bool atEnd = false;
  String? error;

  bool get started => _started;
  bool get isEmpty => photos.isEmpty;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_started) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (loading || refreshing) return;
    _started = true;
    refreshing = loading = true;
    error = null;
    _notify();
    try {
      final page = await _loader(null, force: true);
      photos
        ..clear()
        ..addAll(_dedupe(page.photos));
      _cursor = page.sinceId;
      atEnd = page.sinceId == null || page.photos.isEmpty;
    } on Object catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      refreshing = false;
      _notify();
    }
  }

  Future<void> loadMore() async {
    if (loading || loadingMore || atEnd) return;
    loadingMore = true;
    _notify();
    try {
      final page = await _loader(_cursor, force: false);
      final fresh = _dedupe(page.photos);
      photos.addAll(fresh);
      if (page.sinceId == null ||
          page.photos.isEmpty ||
          (page.sinceId == _cursor && fresh.isEmpty)) {
        atEnd = true;
      }
      _cursor = page.sinceId ?? _cursor;
    } on Object catch (e) {
      error = e.toString();
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  List<AlbumPhoto> _dedupe(List<AlbumPhoto> page) {
    final seen = photos.map((photo) => photo.pid).toSet();
    return [
      for (final photo in page)
        if (seen.add(photo.pid)) photo,
    ];
  }
}

/// 相册九宫格：按月分组，一行三张，点开进看图页。
class ProfileAlbumGrid extends StatelessWidget {
  const ProfileAlbumGrid({
    super.key,
    required this.photos,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<AlbumPhoto> photos;

  /// 下标是 [photos] 里的位置，看图页的左右翻页从这一张开始。
  final ValueChanged<int> onOpen;
  final ValueChanged<int> onLongPress;

  @override
  Widget build(BuildContext context) {
    final entries = _albumEntries(photos);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      sliver: SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) => switch (entries[index]) {
          _AlbumMonth(:final title) => _MonthHeader(title: title),
          _AlbumRow(:final items) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: i < items.length
                        ? AspectRatio(
                            aspectRatio: 1,
                            child: _PhotoTile(
                              photo: items[i].$2,
                              index: items[i].$1,
                              onTap: () => onOpen(items[i].$1),
                              onLongPress: () => onLongPress(items[i].$1),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        },
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        title,
        style: AppTextStyle.footnote
            .of(context, emphasized: true)
            .copyWith(fontSize: 13, color: context.colorScheme.onSurface),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.index,
    required this.onTap,
    required this.onLongPress,
  });

  final AlbumPhoto photo;

  /// 在整页照片里的下标，只用来给读屏一个能分辨的标签。
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: photo.isVideo ? '视频 ${index + 1}' : '照片 ${index + 1}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'album:${photo.pid}',
                createRectTween: (begin, end) =>
                    RectTween(begin: begin, end: end),
                child: RemoteImage(
                  url: photo.thumb,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  placeholderColor: context.surfaceLevel.next.colorOf(
                    context.colorScheme,
                  ),
                ),
              ),
              if (photo.isVideo)
                Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: const ShapeDecoration(
                      color: Color(0x66000000),
                      shape: AppShape.full,
                    ),
                    child: const Center(
                      child: GlyphIcon(
                        HoboGlyphs.play,
                        size: 18,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _AlbumEntry {
  const _AlbumEntry();
}

class _AlbumMonth extends _AlbumEntry {
  const _AlbumMonth(this.title);

  final String title;
}

class _AlbumRow extends _AlbumEntry {
  const _AlbumRow(this.items);

  /// 照片在整页列表里的下标 + 照片本身。
  final List<(int, AlbumPhoto)> items;
}

/// 把分组后的相册摊平成「月份标题 + 三张一行的照片」。
List<_AlbumEntry> _albumEntries(List<AlbumPhoto> photos) {
  final entries = <_AlbumEntry>[];
  var index = 0;
  for (final section in groupAlbumPhotos(photos)) {
    entries.add(_AlbumMonth(section.title));
    for (var i = 0; i < section.photos.length; i += 3) {
      entries.add(
        _AlbumRow([
          for (var j = i; j < i + 3 && j < section.photos.length; j++)
            (index + j, section.photos[j]),
        ]),
      );
    }
    index += section.photos.length;
  }
  return entries;
}
