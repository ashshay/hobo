import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/store.dart';
import '../routes.dart';
import '../widgets/comment_tile.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/image_actions.dart';
import '../widgets/refresh.dart';
import '../widgets/status_card.dart';

/// 微博详情：正文 + 评论（热门 / 按时间两套排序）。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.statusId, this.mid = ''});

  final String statusId;
  final String mid;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final List<Comment> _comments = [];
  Status? _status;
  bool _loading = true;
  bool _loadingComments = true;
  bool _loadingMore = false;
  bool _end = false;
  String? _error;
  String _maxId = '';
  int _maxIdType = 0;
  int _page = 1;
  CommentSort _sort = CommentSort.hot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStatus(), _loadComments()]);
  }

  Future<void> _loadStatus() async {
    final repo = context.read<Repo>();
    try {
      final status = await repo.detail(widget.statusId, force: true);
      if (!mounted) return;
      if (status != null) context.read<Store>().addStatusHistory(status);
      setState(() {
        _status = status;
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadComments({bool more = false}) async {
    final repo = context.read<Repo>();
    final status = _status;
    if (more && (_end || _loadingMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loadingComments = true;
      }
    });
    try {
      final page = await repo.comments(
        widget.statusId,
        mid: status?.mid ?? widget.mid,
        sort: _sort,
        maxId: more && _sort == CommentSort.hot ? _maxId : null,
        maxIdType: _maxIdType,
        page: more && _sort == CommentSort.time ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _comments.addAll(page.items);
        } else {
          _comments
            ..clear()
            ..addAll(page.items);
        }
        if (_sort == CommentSort.hot) {
          _maxId = page.maxId;
          _maxIdType = page.maxIdType;
          _end = page.items.isEmpty || page.maxId.isEmpty;
        } else {
          _page = more ? _page + 1 : 1;
          _end = page.nextPage == 0 || page.items.isEmpty;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      if (!more) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loadingComments = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _switchSort(CommentSort sort) {
    if (sort == _sort) return;
    setState(() {
      _sort = sort;
      _comments.clear();
      _maxId = '';
      _maxIdType = 0;
      _page = 1;
      _end = false;
    });
    _loadComments();
  }

  Future<void> _toggleLike() async {
    final status = _status;
    if (status == null) return;
    final repo = context.read<Repo>();
    if (repo.likeBlocked) {
      showHoboToast(context, '点赞太频繁，稍后再试', level: BannerLevel.warning);
      return;
    }
    final next = !status.liked;
    setState(() {
      _status = status.copyWith(
        liked: next,
        attitudes: status.attitudes + (next ? 1 : -1),
      );
    });
    try {
      await repo.like(status.id, liked: status.liked);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _status = status);
      showHoboToast(
        context,
        e.toString(),
        level: repo.likeBlocked ? BannerLevel.warning : BannerLevel.error,
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final status = _status;
    if (status == null) return;
    final repo = context.read<Repo>();
    final next = !status.favorited;
    try {
      await repo.favorite(status.id, favorited: !next);
      if (!mounted) return;
      setState(() => _status = status.copyWith(favorited: next));
      showHoboToast(context, next ? '已收藏' : '已取消收藏');
    } on Object catch (e) {
      if (!mounted) return;
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    }
  }

  Future<void> _comment() async {
    final status = _status;
    if (status == null) return;
    final text = await showHoboInputDialog(
      context,
      title: '评论',
      hint: '说点什么…',
      multiline: true,
      confirmText: '发送',
    );
    if (text == null || text.isEmpty || !mounted) return;
    final repo = context.read<Repo>();
    await runGuarded(context, () async {
      await repo.comment(status.id, status.mid, text);
      if (!mounted) return;
      showHoboToast(context, '评论已发送');
      _loadComments();
    });
  }

  Future<void> _reply(Comment comment) async {
    final status = _status;
    if (status == null) return;
    final text = await showHoboInputDialog(
      context,
      title: '回复 @${comment.user?.name ?? ''}',
      hint: '回复…',
      multiline: true,
      confirmText: '发送',
    );
    if (text == null || text.isEmpty || !mounted) return;
    final repo = context.read<Repo>();
    await runGuarded(context, () async {
      await repo.replyComment(status.id, status.mid, comment.id, text);
      if (!mounted) return;
      showHoboToast(context, '回复已发送');
      _loadComments();
    });
  }

  Future<void> _repost() async {
    final status = _status;
    if (status == null) return;
    final text = await showHoboInputDialog(
      context,
      title: '转发',
      initial: '',
      hint: '说点什么（可留空）',
      multiline: true,
      confirmText: '转发',
    );
    if (text == null || !mounted) return;
    final repo = context.read<Repo>();
    await runGuarded(context, () async {
      await repo.repost(status.id, status.mid, text);
      if (!mounted) return;
      showHoboToast(context, '已转发');
      _loadStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return HoboPage(
      title: '微博',
      leading: const HoboBackButton(),
      actions: [
        if (status != null)
          IconButton(
            onPressed: () => showStatusActions(context, status),
            tooltip: '更多',
            icon: const GlyphIcon(HoboGlyphs.more, size: 22),
          ),
      ],
      body: _buildBody(status),
    );
  }

  Widget _buildBody(Status? status) {
    if (_loading && status == null) {
      return const HoboLoading(label: '正在加载…');
    }
    if (status == null) {
      return HoboEmpty(
        title: _error ?? '微博不见了',
        message: '可能已经被删除或仅自己可见',
        action: TextButton(
          onPressed: _loadStatus,
          child: const Text('重试'),
        ),
      );
    }
    final padding = EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 24);
    return HoboRefresh(
      onRefresh: _loadAll,
      topInset: padding.top,
      child: ListView(
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        children: [
        StatusCard(
          status: status,
          detail: true,
          onOpen: null,
          onOpenQuoted: (quoted) => openStatus(context, quoted),
          onUser: (user) => openUser(context, user),
          onImage: (pics, index) => openImages(context, pics: pics, index: index),
          onLongPressImage: (pics, index) =>
              showImageActions(context, pics: pics, index: index),
          onVideo: (video) => openVideo(context, video),
          onLink: (url) => handleLink(context, url),
          onLike: _toggleLike,
          onComment: _comment,
          onRepost: _repost,
          onFavorite: _toggleFavorite,
          onMore: () => showStatusActions(context, status),
        ),
        if (status.isVote && status.voteId != null) ...[
          const SizedBox(height: 10),
          HoboCard(
            onPressed: () => openVote(context, status.voteId!, status: status),
            child: Row(
              children: [
                GlyphIcon(
                  HoboGlyphs.vote,
                  size: 20,
                  color: context.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('参与投票')),
                GlyphIcon(
                  Glyphs.chevronForward,
                  size: 18,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              '评论 ${status.comments}',
              style: AppTextStyle.headline.of(context).copyWith(
                fontSize: 17,
                color: context.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            // 官方评论区那样：右侧一个「按热度 / 按时间」的切换。
            GestureDetector(
              onTap: () => _switchSort(
                _sort == CommentSort.hot ? CommentSort.time : CommentSort.hot,
              ),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sort == CommentSort.hot ? '按热度' : '按时间',
                      style: AppTextStyle.footnote.of(context).copyWith(
                        fontSize: 13,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GlyphIcon(
                      Glyphs.sort,
                      size: 16,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_loadingComments && _comments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: ActivityIndicator(size: 22)),
          )
        else if (_comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                '还没有评论',
                style: AppTextStyle.footnote.of(context).copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final comment in _comments)
            CommentTile(
              comment: comment,
              authorId: status.user?.id ?? '',
              onReply: () => _reply(comment),
              onLike: () => _likeComment(comment),
              onUser: (user) => openUser(context, user),
              onLink: (url) => handleLink(context, url),
              onOpenImage: (pics, index) =>
                  openImages(context, pics: pics, index: index),
              onLongPressImage: (pics, index) =>
                  showImageActions(context, pics: pics, index: index),
              // 「共 N 条回复」展开这一层的全部回复。
              onOpenReplies: () => openReplies(
                context,
                statusId: status.id,
                mid: status.mid,
                comment: comment,
                authorId: status.user?.id ?? '',
              ),
            ),
        if (_comments.isNotEmpty)
          Center(
            child: _end
                ? Text(
                    '没有更多评论了',
                    style: AppTextStyle.caption1.of(context).copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  )
                : TextButton(
                    onPressed: _loadingMore
                        ? null
                        : () => _loadComments(more: true),
                    child: _loadingMore
                        ? const ActivityIndicator(size: 16)
                        : const Text('加载更多评论'),
                  ),
          ),
        SizedBox(height: 8 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  Future<void> _likeComment(Comment comment) async {
    final repo = context.read<Repo>();
    final index = _comments.indexWhere((c) => c.id == comment.id);
    if (index < 0) return;
    final next = !comment.liked;
    setState(() {
      _comments[index] = comment.copyWith(
        liked: next,
        likes: comment.likes + (next ? 1 : -1),
      );
    });
    try {
      await repo.likeComment(comment.id, liked: comment.liked);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _comments[index] = comment);
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    }
  }
}
