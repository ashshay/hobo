import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../routes.dart';
import '../widgets/common.dart';
import '../widgets/user_list.dart';

/// 关注 / 粉丝列表。
class RelationsPage extends StatefulWidget {
  const RelationsPage({
    super.key,
    required this.uid,
    required this.name,
    required this.kind,
  });

  final String uid;
  final String name;
  final RelationKind kind;

  @override
  State<RelationsPage> createState() => _RelationsPageState();
}

class _RelationsPageState extends State<RelationsPage> {
  late final UserListController _controller = UserListController(
    (page, {required force}) => context.read<Repo>().relations(
      widget.uid,
      widget.kind,
      page: page,
      force: force,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.ensureLoaded(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.kind == RelationKind.following ? '关注' : '粉丝';
    return HoboPage(
      title: '${widget.name}的$title',
      leading: const HoboBackButton(),
      actions: [
        HoboBarAction(
          label: '刷新',
          onPressed: _controller.refresh,
        ),
      ],
      body: UserListView(
        controller: _controller,
        onOpen: (user) => openUser(context, user),
        emptyTitle: '还没有$title',
      ),
    );
  }
}
