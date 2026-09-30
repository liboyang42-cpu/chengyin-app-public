// 邀请记录页 —— 对应小程序 subpackageMember/myinvite(壳)+
// components/cy/scene-member-invite-history(正文)。
//
// ★ App 一直有「填写邀请人」的入口(设置页),却看不到自己邀请了谁 ——
//   这件事只有输入没有输出。这页把输出补上。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import "../../core/theme/cy_palette.dart";
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/points_statistics.dart';
import 'account_login_gate.dart';
import 'invite_history_logic.dart';

/// 一次性把邀请人和奖励流水都拉回来。
///
/// ⚠️ 奖励流水只拉一页(200 条)。**拉不全时不下「没赚到」的结论** ——
///   `inviteRewardReady` 会转 false,整页文案随之从「待解锁」改成「待同步」,
///   顶部还会横一条说明。这是从小程序原样搬过来的诚实闸。
class InviteHistoryState {
  const InviteHistoryState({
    required this.groups,
    required this.total,
    required this.rewardReady,
    required this.earnedTotal,
  });
  final List<InviteGroup> groups;
  final int total;
  final bool rewardReady;
  final num earnedTotal;
}

const int _kRewardScanSize = 200;

final inviteHistoryProvider = FutureProvider.autoDispose<InviteHistoryState>((
  Ref ref,
) async {
  final invites = await ref
      .watch(registrationApiProvider)
      .invitePage(pageSize: 100);
  // 积分流水失败不该把整页打红 —— 邀请关系本身已经拿到了。
  ({List<dynamic> rows, num? total})? points;
  try {
    final r = await ref
        .watch(pointsApiProvider)
        .page(pageNum: 1, pageSize: _kRewardScanSize);
    points = (rows: r.rows, total: r.total);
  } catch (_) {
    points = null;
  }

  final bool ready = inviteRewardReady(
    fetched: points?.rows.length,
    total: points?.total,
  );
  final Map<String, InviteReward> rewards = points == null
      ? const <String, InviteReward>{}
      : inviteRewardMap(
          points.rows.map(
            (dynamic p) => (
              eventType: p.eventType as int?,
              eventId: p.eventId as String?,
              changePoints: p.changePoints as num?,
              createTime: p.createTime as String?,
            ),
          ),
        );

  num earned = 0;
  for (final InviteReward r in rewards.values) {
    earned += r.points;
  }

  return InviteHistoryState(
    groups: buildInviteGroups(
      members: invites.rows
          .map(
            (InvitedMember m) => (
              id: m.id,
              name: m.displayName,
              avatar: m.avatar,
              createTime: m.createTime,
            ),
          )
          .toList(),
      rewards: rewards,
      rewardReady: ready,
    ),
    total: (invites.total ?? invites.rows.length).toInt(),
    rewardReady: ready,
    earnedTotal: earned,
  );
});

class InviteHistoryPage extends ConsumerWidget {
  const InviteHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 游客深链落地给登录门,不再被路由静默弹回首页(B1 报告 P1-2,
    // 同 roam #208 / 票夹 #231 口径):短路掉注定 401 的请求。
    final bool guest = accountGuest(ref);
    final AsyncValue<InviteHistoryState> state = guest
        ? const AsyncValue<InviteHistoryState>.loading()
        : ref.watch(inviteHistoryProvider);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('邀请记录')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: guest
              ? AccountLoginGate(
                  key: const Key('invites-login-gate'),
                  message: '登录后查看邀请记录',
                  sub: '邀请了谁、奖励到没到账,都记在账号里。',
                  onSignedIn: () => ref.invalidate(inviteHistoryProvider),
                )
              : state.when(
                  // 加载态对齐小程序 `cy-skeleton type="list" count="4"`(不是转圈)。
                  loading: () =>
                      const CySkeleton(type: CySkeletonType.card, count: 4),
                  error: (Object e, StackTrace _) => accountLoginRequired(e)
                      ? AccountLoginGate(
                          message: '登录后查看邀请记录',
                          sub: '邀请了谁、奖励到没到账,都记在账号里。',
                          onSignedIn: () =>
                              ref.invalidate(inviteHistoryProvider),
                        )
                      : StatusView(
                          message: '邀请记录没加载出来',
                          // ★ 说清「你的邀请关系还在」—— 否则用户会以为邀请白做了。
                          sub: '网络可能不稳定,你的邀请关系还在',
                          large: true,
                          onRetry: () => ref.invalidate(inviteHistoryProvider),
                        ),
                  data: (InviteHistoryState s) => s.groups.isEmpty
                      // 空态对齐小程序 `cy-empty`:只说「怎么才会有」,不给重试
                      // (真源的重试只挂在 cy-error 上)。
                      ? StatusView(
                          message: '还没有邀请记录',
                          sub: '好友通过你的邀请加入后,会按时间出现在这里',
                          large: true,
                        )
                      : RefreshIndicator.adaptive(
                          onRefresh: () =>
                              ref.refresh(inviteHistoryProvider.future),
                          child: ListView(
                            padding: const EdgeInsets.all(CyTokens.space4),
                            children: <Widget>[
                              _Summary(s),
                              if (!s.rewardReady) const _SyncNote(),
                              for (final InviteGroup g in s.groups) _Group(g),
                            ],
                          ),
                        ),
                ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(this.s);
  final InviteHistoryState s;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        // 真源 `.ir-summary` 用 `--cy-scene-card-bg`(回退 bg-surface-subtle)。
        color: p.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '累计邀请',
                  style: TextStyle(fontSize: 12, color: p.textTertiary),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      '${s.total}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '人',
                      style: TextStyle(fontSize: 12, color: p.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '首购奖励积分',
                style: TextStyle(fontSize: 12, color: p.textTertiary),
              ),
              const SizedBox(height: 4),
              // ★ 流水没拉全时显示「待同步」而不是「+0」——
              //   「+0」是个数字,会被当成已结算的事实。
              Text(
                s.rewardReady ? '+${pointText(s.earnedTotal)}' : '待同步',
                key: const Key('invite-earned-total'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncNote extends StatelessWidget {
  const _SyncNote();
  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space4),
      child: Text(
        '邀请记录已到达,奖励流水暂未同步',
        key: const Key('invite-sync-note'),
        style: TextStyle(fontSize: 12, color: p.textTertiary),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.g);
  final InviteGroup g;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, CyTokens.space5, 4, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                g.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              Text(
                g.rewardText,
                style: TextStyle(fontSize: 12, color: p.textTertiary),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            // 同 `.ir-card`:场景卡底是 subtle,不是 surface。
            color: p.bgSurfaceSubtle,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
          child: Column(
            children: <Widget>[for (final InviteRow r in g.rows) _Row(r)],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.r);
  final InviteRow r;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(CyTokens.space4),
      child: Row(
        children: <Widget>[
          // 真源 `cy-avatar size="sm" src name`:无图时显示名称首字,
          // 裸 ClipOval(CyNetImage) 只会留一个无字空圆。
          CyAvatar(url: r.avatar, fallback: r.name, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // 真源 `.ir-time` 是 secondary,不是 tertiary。
                  r.timeText,
                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                ),
                Text(
                  r.statusText,
                  style: TextStyle(fontSize: 11, color: p.textTertiary),
                ),
              ],
            ),
          ),
          Text(
            // 真源 `.ir-reward`:label 12 / tertiary —— 奖励状态不许和人名抢亮度。
            r.rewardText,
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              fontWeight: FontWeight.w600,
              color: p.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
