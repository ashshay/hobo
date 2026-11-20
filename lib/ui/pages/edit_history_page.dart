import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../widgets/common.dart';
import '../widgets/remote_image.dart';
import '../widgets/weibo_text.dart';

/// 编辑记录：一条微博被改过几版，每版正文与配图。
class EditHistoryPage extends StatefulWidget {
  const EditHistoryPage({super.key, required this.mid});

  final String mid;

  @override
  State<EditHistoryPage> createState() => _EditHistoryPageState();
}

class _EditHistoryPageState extends State<EditHistoryPage> {
  final List<EditVersion> _versions = [];
  bool _loading = true;
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
      final versions = await context.read<Repo>().editHistory(widget.mid);
      if (!mounted) return;
      setState(() {
        _versions
          ..clear()
          ..addAll(versions);
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

  @override
  Widget build(BuildContext context) {
    return HoboPage(
      title: '编辑记录',
      leading: const HoboBackButton(),
      body: _loading
          ? const HoboLoading(label: '正在加载…')
          : _versions.isEmpty
          ? HoboEmpty(
              title: _error ?? '没有编辑记录',
              message: _error == null ? '这条微博发布后没有改过' : null,
              action: TextButton(onPressed: _load, child: const Text('重试')),
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(
                16,
                pageTopInset(context),
                16,
                pageBottomInset(context),
              ),
              itemCount: _versions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final version = _versions[index];
                return HoboCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '第 ${_versions.length - index} 版',
                            style: AppTextStyle.caption1.of(context).copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatWeiboTime(version.createdAt),
                            style: AppTextStyle.caption1.of(context).copyWith(
                              fontSize: 11,
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (version.note.isNotEmpty)
                        Text(
                          version.note,
                          style: AppTextStyle.body.of(context).copyWith(
                            fontSize: 14,
                            color: context.colorScheme.onSurface,
                          ),
                        )
                      else
                        WeiboText(
                          html: version.textHtml,
                          style: AppTextStyle.body.of(context).copyWith(
                            fontSize: 14,
                            height: 1.4,
                            color: context.colorScheme.onSurface,
                          ),
                        ),
                      if (version.pics.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final pic in version.pics.take(3))
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: RemoteImage(
                                  url: pic,
                                  width: 64,
                                  height: 64,
                                  radius: 8,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
