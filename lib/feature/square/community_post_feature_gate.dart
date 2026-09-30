import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feature_flags.dart';
import '../../core/widgets/status_view.dart';

enum CommunityPostAccess { read, write }

/// App 端社区帖文灰度门禁。配置拉取失败或字段缺失时保持关闭。
class CommunityPostFeatureGateView extends ConsumerWidget {
  const CommunityPostFeatureGateView({
    super.key,
    required this.access,
    required this.child,
  });

  final CommunityPostAccess access;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flag = switch (access) {
      CommunityPostAccess.read => 'communityPostRead',
      CommunityPostAccess.write => 'communityPostWrite',
    };
    if (ref.watch(featureFlagProvider(flag))) return child;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('社区广场')),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const StatusView(
                key: Key('community-post-closed'),
                message: '社区广场灰度中',
                sub: '内容流暂未开放，你仍可管理自己的草稿、处置和申诉',
                icon: CupertinoIcons.person_2,
              ),
              const SizedBox(height: 12),
              CupertinoButton(
                key: const Key('community-post-closed-drafts'),
                onPressed: () => context.push('/square/drafts'),
                child: const Text('我的草稿'),
              ),
              CupertinoButton(
                key: const Key('community-post-closed-governance'),
                onPressed: () => context.push('/square/governance'),
                child: const Text('社区治理与申诉'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
