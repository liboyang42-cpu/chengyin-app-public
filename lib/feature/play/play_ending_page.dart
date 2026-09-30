import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/play_ending.dart';

/// 结局信的会话参数 —— 与真源 `_sessionParams()`(`pages/play/index.js:488`)同口径:
/// 活动会话只带 activityId,自玩会话(活动为 0/缺)才带 topicId。
typedef PlayEndingKey = ({int? activityId, int? topicId});

final playEndingProvider = FutureProvider.autoDispose
    .family<PlayEnding, PlayEndingKey>((ref, PlayEndingKey key) {
      return ref
          .watch(playApiProvider)
          .ending(activityId: key.activityId, topicId: key.topicId);
    });

/// 游玩结局。对齐小程序 `pages/play` 的结局部分。
class PlayEndingPage extends ConsumerWidget {
  const PlayEndingPage({super.key, required this.activityId, this.topicId});

  final int activityId;

  /// 自玩(主题直玩)会话没有 activityId,结局信按 topicId 取。
  final int? topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayEndingKey key = (
      activityId: activityId > 0 ? activityId : null,
      topicId: activityId > 0 ? null : topicId,
    );
    final async = ref.watch(playEndingProvider(key));
    final textTheme = Theme.of(context).textTheme;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('这一趟')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => StatusView(
              message: '城市故事暂未加载，不影响本次足迹。',
              sub: e.toString().replaceFirst('Exception: ', ''),
              large: true,
              retryLabel: '重新加载',
              onRetry: () => ref.invalidate(playEndingProvider(key)),
            ),
            data: (PlayEnding ending) {
              // ★ 空结局**不是错误** —— 是还没走完。说清楚,不给重试。
              if (!ending.hasStory) {
                return const StatusView(
                  message: '还没有故事',
                  sub: '走完几个地点之后,这里会把你的这一趟讲一遍',
                  large: true,
                );
              }
              return ListView(
                padding: const EdgeInsets.all(CyTokens.pageX),
                children: <Widget>[
                  if (ending.opener.trim().isNotEmpty) ...<Widget>[
                    Text(
                      ending.opener.trim(),
                      style: textTheme.titleLarge?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: CyTokens.space5),
                  ],
                  ...ending.fragments.map(
                    (EndingFragment f) => _FragmentBlock(f: f),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FragmentBlock extends StatelessWidget {
  const _FragmentBlock({required this.f});
  final EndingFragment f;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = f.body;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '${f.step}',
                style: textTheme.titleMedium?.copyWith(
                  color: CyTokens.textTertiary,
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              Expanded(child: Text(f.name, style: textTheme.titleMedium)),
            ],
          ),
          // ★ 后端已做过一层兜底(碎片文案空则退回描述),这里再空就是真的没有 ——
          //   只保留标题,不渲染一个空段落让人以为没加载出来。
          if (body != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              body,
              style: textTheme.bodyMedium?.copyWith(
                height: 1.7,
                color: CyTokens.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
