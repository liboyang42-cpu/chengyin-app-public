import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/points_task.dart';
import '../auth/login_gate.dart';

/// 「积分任务」——后台积分规则的真源(`/api/points/result_list`)。
/// (标题取小程序 utils/scene-registry.js 的场景原话;页内入口链接才叫「如何获取积分」。)
///
/// ★★ App 此前这块**完全没有**:积分页空态写着「参与活动或完成任务后…」,
///   却没有任何地方告诉用户有哪些任务、各给多少分。
///   小程序早就把那句静态文案换成了这份动态列表。
///
/// ⚠️ 未登录时后端**有意**拒绝(生产实测 HTTP 401
///   `{"code":401,"msg":"登录状态已失效，请重新登录"}`),抛的是 DioException。
///   抛了要说「登录后可见 + 去登录」,不能渲成「加载失败」——
///   那会让用户以为是网络问题,反复重试一条永远不会成功的死路。
final pointsTasksProvider = FutureProvider.autoDispose<List<PointsTask>>((
  Ref ref,
) async {
  final rows = await ref.watch(registrationApiProvider).pointsResultList();
  return rows
      .map(PointsTask.fromJson)
      .where((PointsTask t) => t.isEarnTask)
      .toList();
});

Future<void> showPointsTasksSheet(BuildContext context) {
  return showCupertinoSheet<void>(
    context: context,
    showDragHandle: true,
    topGap: 0.3,
    scrollableBuilder:
        (BuildContext context, ScrollController scrollController) =>
            _TasksSheet(scrollController: scrollController),
  );
}

class _TasksSheet extends ConsumerWidget {
  const _TasksSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pointsTasksProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        // 小程序场景原话(utils/scene-registry.js 的 points-tasks 标题)。
        middle: Text('积分任务'),
      ),
      child: SafeArea(
        top: false,
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(CyTokens.space6),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (Object e, _) {
            // ⚠️ 未登录是**后端有意**的拒绝,不是故障,只认 HTTP 401
            //   ([isUnauthorizedError])。原来是 `e.toString().contains('登录')`,
            //   而 401 抛的 DioException.toString() 是 6 行英文 —— 判据恒 false,
            //   这个分支**从未命中过**,游客看到的就是那 6 行英文。
            final bool needLogin = isUnauthorizedError(e);
            return StatusView(
              icon: needLogin ? Icons.lock_outline : Icons.cloud_off,
              message: needLogin ? '登录后可见赚分任务' : '赚分任务加载不出来',
              // 未登录给「去登录」这条出路;真故障才给「重试」——
              // 游客重试按多少次都还是 401。
              sub: needLogin
                  ? '任务完成次数是按账号算的'
                  : e.toString().replaceFirst('Exception: ', ''),
              retryLabel: needLogin ? '去登录' : '重试',
              onRetry: needLogin
                  ? () async {
                      if (!await requireLogin(context, ref)) return;
                      ref.invalidate(pointsTasksProvider);
                    }
                  : () => ref.invalidate(pointsTasksProvider),
            );
          },
          data: (List<PointsTask> list) => list.isEmpty
              // 规则表可以合法地是空的(后台一条都没启用)。
              ? const StatusView(
                  icon: CupertinoIcons.tray,
                  // 小程序同一空态原话 —— 也顺手去掉「后台」这种用户看不懂的
                  // 内部词。
                  message: '暂无积分任务',
                  sub: '积分规则上线后会出现在这里',
                )
              : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.space4,
                    0,
                    CyTokens.space4,
                    CyTokens.space4,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CyTokens.space3),
                  itemBuilder: (_, int i) => _TaskRow(task: list[i]),
                ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});
  final PointsTask task;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    // 小程序同一行是张卡(bg + radius + padding),不是裸行。
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.title,
                  // 小程序 .pts-row__name 是 17/600 → Headline 档(T2)。
                  style: CyType.headline.copyWith(color: p.textPrimary),
                ),
                if (task.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    task.description,
                    // .pts-row__desc 是 caption(11) → 梯上同值档 Caption2。
                    style: CyType.caption2.copyWith(color: p.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // 分值走**黑白档**不上色:小程序同一处也是 text-primary,
              // 一分绿会把「赚分」染成状态色(C1)。
              // .pts-row__gain 是 16/700 → Callout + Bold(T3)。
              Text(
                '+${task.points}',
                style: CyType.callout.copyWith(
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: CyTokens.space1),
              // 0 次说「待完成」不说空 —— 小程序同一行原话,
              // 「没做过」本来就是要人去做的那一条。
              // .pts-row__done 是 caption(11) → 同值 Caption2。
              Text(
                task.doneCount > 0 ? '已获 ${task.doneCount} 次' : '待完成',
                style: CyType.caption2.copyWith(color: p.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
