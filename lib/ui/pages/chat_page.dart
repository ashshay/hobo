import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';

/// 私信会话。列表是「最新在前」，界面用 reverse 铺，index 0 在屏幕最下面。
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.uid,
    this.gid = '',
    required this.name,
    this.avatar = '',
  });

  final String uid;
  final String gid;
  final String name;
  final String avatar;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  Timer? _poll;
  bool _loading = true;
  bool _loadingMore = false;
  bool _atStart = false;
  bool _sending = false;
  String? _error;
  String _myUid = '';

  bool get _isGroup => widget.gid.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final repo = context.read<Repo>();
    try {
      _myUid = await repo.ownUid();
    } on Object {
      _myUid = repo.session?.uid ?? '';
    }
    await _loadInitial();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _pollNew());
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await context.read<Repo>().chat(
        uid: widget.uid,
        gid: widget.gid,
        count: 20,
        force: true,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _loading = false;
        _atStart = page.messages.length < 20;
      });
      _markSeen();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _markSeen() {
    final newest = _newest();
    if (newest == null) return;
    final token = _isGroup ? widget.gid : (widget.uid);
    context.read<Repo>().store.markChatSeen(token, newest.id);
  }

  ChatMessage? _newest() {
    for (final message in _messages) {
      if (!message.pending && !message.failed) return message;
    }
    return _messages.isEmpty ? null : _messages.first;
  }

  ChatMessage? _oldest() {
    for (final message in _messages.reversed) {
      if (!message.pending && !message.failed) return message;
    }
    return null;
  }

  Future<void> _pollNew() async {
    final newest = _newest();
    if (newest == null || !mounted) return;
    try {
      final page = await context.read<Repo>().chat(
        uid: widget.uid,
        gid: widget.gid,
        sinceId: newest.id,
        count: 20,
        force: true,
      );
      if (!mounted || page.messages.isEmpty) return;
      final known = _messages.map((m) => m.id).toSet();
      final fresh = [
        for (final message in page.messages)
          if (!known.contains(message.id)) message,
      ];
      if (fresh.isEmpty) return;
      setState(() => _messages.insertAll(0, fresh));
      _markSeen();
    } on Object {
      // 轮询失败下一轮再试。
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _atStart) return;
    final oldest = _oldest();
    if (oldest == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await context.read<Repo>().chat(
        uid: widget.uid,
        gid: widget.gid,
        maxId: oldest.id,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        _messages.addAll(page.messages);
        _loadingMore = false;
        _atStart = page.messages.isEmpty;
      });
    } on Object {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final repo = context.read<Repo>();
    _input.clear();
    final local = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      senderId: _myUid,
      recipientId: widget.uid,
      createdAt: '${DateTime.now().millisecondsSinceEpoch}',
      pending: true,
    );
    setState(() => _messages.insert(0, local));
    setState(() => _sending = true);
    try {
      final sent = await repo.sendChat(widget.uid, text, gid: widget.gid);
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == local.id);
        if (sent != null) {
          if (index >= 0) {
            _messages[index] = sent;
          } else {
            _messages.insert(0, sent);
          }
        } else if (index >= 0) {
          _messages[index] = local.copyWith(pending: false);
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == local.id);
        if (index >= 0) _messages[index] = local.copyWith(failed: true);
      });
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendImage() async {
    final repo = context.read<Repo>();
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      showHoboToast(context, '正在上传图片…');
      final fids = await repo.uploadChatImage(
        widget.uid,
        bytes,
        gid: widget.gid,
        mime: picked.mimeType ?? 'image/jpeg',
      );
      final sent = await repo.sendChatImage(
        widget.uid,
        fids,
        gid: widget.gid,
      );
      if (!mounted) return;
      if (sent != null) setState(() => _messages.insert(0, sent));
    } on Object catch (e) {
      if (!mounted) return;
      showHoboToast(context, e.toString(), level: BannerLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HoboPage(
      title: widget.name,
      leading: const HoboBackButton(),
      actions: [
        IconButton(
          onPressed: _loadInitial,
          tooltip: '刷新',
          icon: const GlyphIcon(HoboGlyphs.refresh, size: 20),
        ),
      ],
      body: Column(
        children: [
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const HoboLoading(label: '正在加载聊天记录…');
    if (_messages.isEmpty) {
      return HoboEmpty(
        title: _error ?? '还没有消息',
        message: _error == null ? '打个招呼吧' : '稍后再试',
        action: TextButton(onPressed: _loadInitial, child: const Text('重试')),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 反过来铺的列表：滚到「最大 extent 之外」就是翻到了更早的消息。
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.pixels >
                notification.metrics.maxScrollExtent - 200) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        reverse: true,
        padding: EdgeInsets.fromLTRB(
          16,
          pageTopInset(context),
          16,
          12,
        ),
        itemCount: _messages.length + 1,
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            return _loadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: ActivityIndicator(size: 16)),
                  )
                : _atStart
                ? const SizedBox(height: 8)
                : const SizedBox.shrink();
          }
          final message = _messages[index];
          return _Bubble(
            message: message,
            mine: message.senderId == _myUid,
            avatar: widget.avatar,
            onRetry: message.failed
                ? () {
                    setState(() => _messages.remove(message));
                    _input.text = message.text;
                    _sendText();
                  }
                : null,
            onImageTap: () => openImages(
              context,
              pics: [
                Pic(
                  thumb: message.thumbUrl,
                  large: message.imageUrl,
                ),
              ],
              index: 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposer() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottom),
      color: context.colorScheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: _sendImage,
            tooltip: '发送图片',
            icon: const GlyphIcon(HoboGlyphs.image, size: 22),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120, minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: ShapeDecoration(
                color: context.colorScheme.surfaceContainerHigh,
                shape: AppShape.all(AppCorner.lg),
              ),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: const InputDecoration(
                  hintText: '发消息…',
                  isCollapsed: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _sendText,
            tooltip: '发送',
            icon: const GlyphIcon(HoboGlyphs.send, size: 22),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.avatar,
    this.onRetry,
    this.onImageTap,
  });

  final ChatMessage message;
  final bool mine;
  final String avatar;
  final VoidCallback? onRetry;
  final VoidCallback? onImageTap;

  @override
  Widget build(BuildContext context) {
    if (message.isNotice) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: AppTextStyle.caption1.of(context).copyWith(
              fontSize: 11,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final maxWidth = MediaQuery.sizeOf(context).width * 0.68;
    final content = message.isImage
        ? GestureDetector(
            onTap: onImageTap,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(AppCorner.md),
              child: RemoteImage(
                url: message.thumbUrl.isNotEmpty
                    ? message.thumbUrl
                    : message.imageUrl,
                width: maxWidth,
                height: maxWidth * 0.75,
                fit: BoxFit.cover,
              ),
            ),
          )
        : Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: ShapeDecoration(
              color: mine
                  ? context.colorScheme.primary
                  : context.colorScheme.surfaceContainerHigh,
              shape: AppShape.all(AppCorner.lg),
            ),
            child: Text(
              message.text,
              style: AppTextStyle.body.of(context).copyWith(
                fontSize: 14.5,
                height: 1.35,
                color: mine
                    ? context.colorScheme.onPrimary
                    : context.colorScheme.onSurface,
              ),
            ),
          );
    final bubble = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        content,
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.pending)
              Text(
                '发送中…',
                style: AppTextStyle.caption2.of(context).copyWith(
                  fontSize: 10,
                  color: context.colorScheme.onSurfaceVariant,
                ),
              )
            else if (message.failed)
              GestureDetector(
                onTap: onRetry,
                child: Text(
                  '发送失败，点击重试',
                  style: AppTextStyle.caption2.of(context).copyWith(
                    fontSize: 10,
                    color: context.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            Avatar(url: avatar, size: 32),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
          if (mine) ...[
            const SizedBox(width: 8),
            Avatar(url: context.read<Repo>().session?.uid.isEmpty ?? true
                ? ''
                : _myAvatar(context),
            size: 32),
          ],
        ],
      ),
    );
  }

  String _myAvatar(BuildContext context) {
    final uid = context.read<Repo>().session?.uid ?? '';
    for (final account in context.read<Repo>().store.accounts()) {
      if (account.uid == uid) return account.avatar;
    }
    return '';
  }
}
