import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../routes.dart';
import '../widgets/comment_tile.dart';
import '../widgets/common.dart';
import '../widgets/image_actions.dart';

/// 楼中楼：一层评论下的全部回复。
class RepliesPage extends StatefulWidget {
  const RepliesPage({
    super.key,
    required this.statusId,
    required this.mid,
    required this.comment,
    this.authorId = '',
  });

  final String statusId;
  final String mid;
  final Comment comment;
  final String authorId;

  @override
  State<RepliesPage> createState() => _RepliesPageState();
}

class _RepliesPageState extends State<RepliesPage> {
  final List<Comment> _replies = [];
  String _maxId = '0';
  int _maxIdType = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _atEnd = false;

  /// 连续几页没有新回复：游标翻页的页与页之间会重叠，一页全重复不算到底。
  int _dryMore = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loadingMore || _atEnd)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await context.read<Repo>().commentReplies(
        widget.comment.id,
        maxId: more ? _maxId : null,
        maxIdType: _maxIdType,
      );
      if (!mounted) return;
      var added = page.items.length;
      setState(() {
        if (more) {
          added = appendUnique(_replies, page.items, (comment) => comment.id);
          _dryMore = added == 0 ? _dryMore + 1 : 0;
        } else {
          _dryMore = 0;
          _replies
            ..clear()
            ..addAll(page.items);
        }
        _maxId = page.maxId;
        _maxIdType = page.maxIdType;
        _total = page.nextPage;
        _atEnd =
            page.items.isEmpty ||
            _dryMore >= 2 ||
            (page.maxId.isEmpty && page.items.length < 10);
        _loading = false;
        _loadingMore = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _replyTo(Comment target) async {
    final text = await showHoboInputDialog(
      context,
      title: '回复 @${target.user?.name ?? ''}',
      hint: '回复…',
      multiline: true,
      confirmText: '发送',
    );
    if (text == null || text.isEmpty || !mounted) return;
    final repo = context.read<Repo>();
    await runGuarded(context, () async {
      final created = await repo.replyComment(
        widget.statusId,
        widget.mid,
        widget.comment.id,
        text,
      );
      if (!mounted) return;
      setState(() {
        _replies.insert(0, created);
        _total = _replies.length;
      });
      showHoboToast(context, '回复已发送');
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _total > 0 ? _total : widget.comment.replyCount;
    return HoboPage(
      title: '共 $total 条回复',
      leading: const HoboBackButton(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, pageTopInset(context), 16, 24),
        children: [
          // 被回复的那一层评论放在最上面。
          CommentTile(
            comment: widget.comment,
            authorId: widget.authorId,
            showDivider: false,
            onUser: (user) => openUser(context, user),
            onLink: (url) => handleLink(context, url),
            onOpenImage: (pics, index) =>
                openImages(context, pics: pics, index: index),
            onLongPressImage: (pics, index) =>
                showImageActions(context, pics: pics, index: index),
            onReply: () => _replyTo(widget.comment),
            onLike: null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Text(
                  '全部回复',
                  style: AppTextStyle.headline.of(context).copyWith(
                    fontSize: 15,
                    color: context.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (_loadingMore) const ActivityIndicator(size: 14),
              ],
            ),
          ),
          if (_loading && _replies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: ActivityIndicator(size: 22)),
            )
          else if (_replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _error ?? '还没有回复',
                  style: AppTextStyle.footnote.of(context).copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            for (final reply in _replies)
              CommentTile(
                comment: reply,
                authorId: widget.authorId,
                onUser: (user) => openUser(context, user),
                onLink: (url) => handleLink(context, url),
                onOpenImage: (pics, index) =>
                    openImages(context, pics: pics, index: index),
                onLongPressImage: (pics, index) =>
                    showImageActions(context, pics: pics, index: index),
                onReply: () => _replyTo(reply),
              ),
          if (_replies.isNotEmpty && !_atEnd)
            Center(
              child: TextButton(
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: const Text('加载更多回复'),
              ),
            ),
          if (_atEnd && _replies.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '没有更多回复了',
                  style: AppTextStyle.caption1.of(context).copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
