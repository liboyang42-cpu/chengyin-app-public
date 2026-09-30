import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_native_sheet.dart';
import '../../core/widgets/cy_system_text_input_alert.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_lead.dart';
import '../../data/models/scan_result.dart';

final teamProgressProvider = FutureProvider.autoDispose
    .family<TeamProgress, int>((ref, int activityId) {
      return ref.watch(clubLeadApiProvider).teamProgress(activityId);
    });

/// 带队进度。对齐小程序 `pages/play` 里的 club/lead 部分 —— App 侧此前完全没有。
class TeamLeadPage extends ConsumerStatefulWidget {
  const TeamLeadPage({super.key, required this.activityId});

  final int activityId;

  @override
  ConsumerState<TeamLeadPage> createState() => _TeamLeadPageState();
}

class _TeamLeadPageState extends ConsumerState<TeamLeadPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(teamProgressProvider(widget.activityId));
      if (!mounted) return;
      CyNativeNotice.show(context, done);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 核销队员票。
  ///
  /// ★★ **必须带本团 activityId** —— 小程序注释原话:
  ///   「带队主题的玩家票必须从当前 activity 入口核销。不能复用商家首页的
  ///    通用扫码,否则请求没有场次身份,后端会 fail closed,
  ///    结算也无法区分同主题的不同团」。
  ///
  /// ⚠️ 这里只做**手工输入**那条回落:队长现场多半是对着队员的手机屏幕看码,
  ///   相机在这一页上打开会把队伍进度整块挡住。扫码入口留给商家核销页。
  Future<void> _verifyMemberTicket() async {
    final String? code = await showCySystemTextInputAlert(
      context: context,
      title: '核销队员票',
      placeholder: '队员出示的核销码',
      confirmText: '核销',
      keyboardKind: CySystemKeyboardKind.ascii,
    );
    if (code == null || code.isEmpty || !mounted) return;
    await _run(() async {
      final ScanResult r = await ref
          .read(registrationApiProvider)
          .scanGroupMemberTicket(code: code, activityId: widget.activityId);
      // ★ 三态里只有 redeemed 算成功;needsChoice 在这条链路上不该出现
      //   (队员票没有选章),真出现了也别当成功。
      if (r.outcome != ScanOutcome.redeemed) {
        throw Exception(r.message);
      }
    }, '队员票已核销');
  }

  Future<void> _broadcast() async {
    final ctrl = TextEditingController();
    final text = await showCyNativeSheet<String>(
      // B1:iOS 15+ 原生 sheet(26+ 真玻璃),其余回退 showCupertinoSheet。
      context,
      detents: CyNativeSheetDetents.medium,
      builder: (BuildContext ctx) => CupertinoPopupSurface(
        // 原生承载时不画自带底,透出系统 sheet 材质(S3)。
        isSurfacePainted: !isCyNativeSheet(ctx),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space4 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    CupertinoButton(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space2,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('取消'),
                    ),
                    Expanded(
                      child: Text(
                        '队长广播',
                        textAlign: TextAlign.center,
                        style: CupertinoTheme.of(
                          ctx,
                        ).textTheme.navTitleTextStyle,
                      ),
                    ),
                    CupertinoButton(
                      key: const Key('team-lead-broadcast-send'),
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space2,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                      child: const Text('发送'),
                    ),
                  ],
                ),
                const SizedBox(height: CyTokens.space3),
                CupertinoTextField(
                  key: const Key('team-lead-broadcast-input'),
                  controller: ctrl,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 3,
                  placeholder: '对全队说一句…',
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  padding: const EdgeInsets.all(CyTokens.space3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    await _run(
      () => ref.read(clubLeadApiProvider).broadcast(widget.activityId, text),
      '广播已发出',
    );
  }

  Future<void> _unlockChapter() async {
    final bool confirmed = await cyConfirm(
      context,
      title: '解锁下一章节',
      content: '确认让全队进入下一章节?',
      confirmText: '确认解锁',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(clubLeadApiProvider).unlockChapter(widget.activityId),
      '已解锁下一章',
    );
  }

  Future<void> _settleTeam() async {
    final bool confirmed = await cyConfirm(
      context,
      title: '全团结算',
      content: '将为到场已购票的全体队员核销并入结算,确认结算?',
      confirmText: '结算全团',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(clubLeadApiProvider).settle(widget.activityId),
      '已结算',
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamProgressProvider(widget.activityId));
    final api = ref.read(clubLeadApiProvider);
    final textTheme = Theme.of(context).textTheme;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('带队')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => StatusView(
              message: '带队信息没能加载出来',
              sub: e.toString().replaceFirst('Exception: ', ''),
              large: true,
              onRetry: () =>
                  ref.invalidate(teamProgressProvider(widget.activityId)),
            ),
            data: (TeamProgress p) {
              // ★ 还没开队**不是错误** —— 给「开始带队」而不是错误态。
              if (!p.exists) {
                return StatusView(
                  message: '这一场还没开队',
                  sub: p.isLeader ? '你可以现在开始行程' : '等队长开始行程…',
                  large: true,
                  onRetry: p.isLeader
                      ? () => _run(() => api.start(widget.activityId), '已开始行程')
                      : null,
                  // 小程序 P1 集合屏的队长按钮就是「开始行程」。
                  retryLabel: '开始行程',
                );
              }

              final actions = availableLeadActions(p);
              final blocked = unlockBlockedReason(p);

              return RefreshIndicator.adaptive(
                onRefresh: () async =>
                    ref.invalidate(teamProgressProvider(widget.activityId)),
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  children: <Widget>[
                    // 真源 P1 集合屏(index.wxml:713-714):开队未发车 = 集合态。
                    if (p.exists && p.status == 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: CyTokens.space1),
                        child: Text(
                          '队伍集合中',
                          style: textTheme.labelLarge?.copyWith(
                            color: CyTokens.textSecondary,
                          ),
                        ),
                      ),
                    if ((p.chapterName ?? '').isNotEmpty)
                      Text(
                        '当前章节:${p.chapterName}',
                        style: textTheme.titleMedium,
                      ),
                    // 空队伍不显示「0/0」。
                    if (p.arrivedText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: CyTokens.space1),
                        child: Text(
                          p.arrivedText!,
                          style: textTheme.bodySmall?.copyWith(
                            color: CyTokens.textSecondary,
                          ),
                        ),
                      ),
                    if ((p.broadcast ?? '').trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space3),
                      Container(
                        padding: const EdgeInsets.all(CyTokens.space3),
                        decoration: BoxDecoration(
                          color: CyTokens.bgSurface,
                          borderRadius: BorderRadius.circular(
                            CyTokens.radiusMd,
                          ),
                          border: Border.all(color: CyTokens.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '队长广播',
                              style: textTheme.bodySmall?.copyWith(
                                color: CyTokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: CyTokens.space1),
                            Text(
                              p.broadcast!.trim(),
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: CyTokens.space4),
                    const CySectionTitle('队员'),
                    const SizedBox(height: CyTokens.space2),
                    ...p.members.map(
                      (TeamMember m) => CyCell(
                        title: m.displayName + (m.isLeader ? ' · 队长' : ''),
                        subtitle: m.arrived ? '已到集合点 · 完成 ${m.done}' : '未到达',
                      ),
                    ),
                    const SizedBox(height: CyTokens.space4),
                    // 「我到了」队员也能点 —— 这是唯一一个非队长动作。
                    // ★ 已签过到就收成状态字(真源 :722-723 是二选一,
                    //   不是摆一个再点一次注定失败的按钮)。
                    if (p.meArrived)
                      Padding(
                        padding: const EdgeInsets.only(top: CyTokens.space4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const Icon(
                              CupertinoIcons.checkmark_seal_fill,
                              size: 20,
                              color: CyTokens.statusSuccess,
                            ),
                            const SizedBox(width: CyTokens.space2),
                            Text(
                              '已签到',
                              style: textTheme.bodyMedium?.copyWith(
                                color: CyTokens.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton.tinted(
                          key: const Key('team-lead-arrive'),
                          minimumSize: const Size(44, 44),
                          onPressed: _busy
                              ? null
                              : () => _run(
                                  () => api.arrive(widget.activityId),
                                  '已标记到达',
                                ),
                          child: const Text('我到了'),
                        ),
                      ),
                    // ★ 队长动作按 availableLeadActions 给 —— 非队长一个都不摆。
                    if (blocked != null)
                      Padding(
                        padding: const EdgeInsets.only(top: CyTokens.space2),
                        child: Text(
                          blocked,
                          style: textTheme.bodySmall?.copyWith(
                            color: CyTokens.statusWarning,
                          ),
                        ),
                      ),
                    ...actions.map(
                      (LeadAction a) => Padding(
                        padding: const EdgeInsets.only(top: CyTokens.space2),
                        child: SizedBox(
                          width: double.infinity,
                          child: CupertinoButton.filled(
                            key: Key('team-lead-action-${a.name}'),
                            minimumSize: const Size(44, 44),
                            onPressed: _busy
                                ? null
                                : () {
                                    switch (a) {
                                      case LeadAction.broadcast:
                                        _broadcast();
                                      case LeadAction.verifyMemberTicket:
                                        _verifyMemberTicket();
                                      case LeadAction.unlockChapter:
                                        _unlockChapter();
                                      case LeadAction.settle:
                                        _settleTeam();
                                    }
                                  },
                            child: Text(a.label),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
