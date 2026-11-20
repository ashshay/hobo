import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../widgets/common.dart';
import '../widgets/glyphs.dart';
import '../widgets/remote_image.dart';

/// 投票：选项、比例、投票与取消。
class VotePage extends StatefulWidget {
  const VotePage({super.key, required this.voteId, this.status});

  final String voteId;
  final Status? status;

  @override
  State<VotePage> createState() => _VotePageState();
}

class _VotePageState extends State<VotePage> {
  VoteInfo? _vote;
  final Set<String> _selected = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var voteId = widget.voteId;
      if (voteId.isEmpty) {
        final status = widget.status;
        if (status == null) throw ApiException('找不到投票');
        voteId =
            await context.read<Repo>().resolveStatusVoteId(
              status.id,
              status.textHtml,
            ) ??
            '';
        if (voteId.isEmpty) throw ApiException('找不到投票');
      }
      final vote = await context.read<Repo>().fetchVote(voteId);
      if (!mounted) return;
      setState(() {
        _vote = vote;
        _selected
          ..clear()
          ..addAll(
            vote.options.where((o) => o.selected).map((o) => o.id),
          );
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleOption(VoteOption option) {
    final vote = _vote;
    if (vote == null || vote.hasVoted || vote.isExpired) return;
    setState(() {
      if (vote.isMultiSelect) {
        if (_selected.contains(option.id)) {
          _selected.remove(option.id);
        } else if (_selected.length < vote.maxSelect) {
          _selected.add(option.id);
        } else {
          showHoboToast(context, '最多选 ${vote.maxSelect} 项');
        }
      } else {
        _selected
          ..clear()
          ..add(option.id);
      }
    });
  }

  Future<void> _voteAction() async {
    final vote = _vote;
    if (vote == null || _busy) return;
    final repo = context.read<Repo>();
    setState(() => _busy = true);
    try {
      if (vote.hasVoted) {
        final updated = await repo.uncastVote(vote.id, vote.sk);
        if (!mounted) return;
        setState(() => _vote = updated);
        showHoboToast(context, '已取消投票');
      } else {
        if (_selected.isEmpty) {
          showHoboToast(context, '先选一个选项');
          return;
        }
        final updated = await repo.castVote(
          vote.id,
          _selected.toList(),
          vote.sk,
        );
        if (!mounted) return;
        setState(() => _vote = updated);
        showHoboToast(context, '投票成功');
      }
    } on Object catch (e) {
      if (mounted) {
        showHoboToast(context, e.toString(), level: BannerLevel.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vote = _vote;
    return HoboPage(
      title: '投票',
      leading: const HoboBackButton(),
      body: _loading
          ? const HoboLoading(label: '正在加载投票…')
          : vote == null
          ? HoboEmpty(
              title: _error ?? '投票不见了',
              message: '可能已经结束或删除',
              action: TextButton(onPressed: _load, child: const Text('重试')),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                pageTopInset(context),
                16,
                pageBottomInset(context),
              ),
              children: [
                HoboCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GlyphIcon(
                            HoboGlyphs.vote,
                            size: 18,
                            color: context.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            vote.isExpired ? '投票已结束' : '进行中',
                            style: AppTextStyle.caption1.of(context).copyWith(
                              fontSize: 12,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${vote.partNum} 人参与',
                            style: AppTextStyle.caption1.of(context).copyWith(
                              fontSize: 12,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        vote.title,
                        style: AppTextStyle.title3.of(context).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: context.colorScheme.onSurface,
                        ),
                      ),
                      if (vote.deadlineLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          vote.deadlineLabel,
                          style: AppTextStyle.caption1.of(context).copyWith(
                            fontSize: 11,
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (vote.author != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Avatar(url: vote.author!.avatar, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              vote.author!.name,
                              style: AppTextStyle.caption1.of(context).copyWith(
                                fontSize: 12,
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                for (final option in vote.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _OptionCard(
                      option: option,
                      showResult: vote.hasVoted || vote.isExpired,
                      selected: _selected.contains(option.id),
                      onTap: () => _toggleOption(option),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        vote.isMultiSelect ? '可多选，最多 ${vote.maxSelect} 项' : '单选',
                        style: AppTextStyle.caption1.of(context).copyWith(
                          fontSize: 11,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (!vote.isExpired)
                      TextButton(
                        onPressed: _busy ? null : _voteAction,
                        child: Text(
                          vote.hasVoted ? '取消投票' : '投票',
                          style: TextStyle(
                            color: vote.hasVoted
                                ? context.colorScheme.error
                                : context.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.showResult,
    required this.selected,
    required this.onTap,
  });

  final VoteOption option;
  final bool showResult;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = option.partRatio.clamp(0.0, 100.0) / 100;
    return GestureDetector(
      onTap: showResult ? null : onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: ShapeDecoration(
              color: context.surfaceLevel.next.colorOf(context.colorScheme),
              shape: AppShape.all(AppCorner.md),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: selected
                        ? context.colorScheme.primary
                        : const Color(0x00000000),
                    shape: AppShape.full,
                  ),
                  child: selected
                      ? GlyphIcon(
                          HoboGlyphs.check,
                          size: 13,
                          color: context.colorScheme.onPrimary,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                if (option.pic.isNotEmpty) ...[
                  RemoteImage(url: option.pic, width: 34, height: 34, radius: 6),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    option.title,
                    style: AppTextStyle.body.of(context).copyWith(
                      fontSize: 14,
                      color: context.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (showResult)
                  Text(
                    '${option.ratioLabel} · ${option.partNum}',
                    style: AppTextStyle.caption1.of(context).copyWith(
                      fontSize: 11,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (showResult)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: FractionallySizedBox(
                  widthFactor: ratio == 0 ? 0.0001 : ratio,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      decoration: ShapeDecoration(
                        color: context.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        shape: AppShape.all(AppCorner.md),
                      ),
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
