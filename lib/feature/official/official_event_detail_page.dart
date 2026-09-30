import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/official_event.dart';
import 'official_controller.dart';
import '../../core/widgets/cy_native_notice.dart';

/// 官方活动详情。对齐小程序 `pages/activity/official-detail`。
class OfficialEventDetailPage extends ConsumerWidget {
  const OfficialEventDetailPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(officialEventProvider(id));
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('活动详情')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => StatusView(
              message: '官方活动没能加载出来',
              sub: '活动不存在或网络异常',
              large: true,
              onRetry: () => ref.invalidate(officialEventProvider(id)),
            ),
            data: (OfficialEvent e) => _Body(event: e),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.event});
  final OfficialEvent event;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Future<void> _onCta(OfficialCta cta) async {
    // 不可点的态压根不该走到这儿(按钮已禁用),这里只是二道保险。
    if (!cta.enabled || _busy) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(officialApiProvider);
      switch (cta.type) {
        case OfficialCtaType.signup:
          await api.signup(widget.event.id);
          break;
        case OfficialCtaType.explore:
          await api.complete(widget.event.id);
          break;
        case OfficialCtaType.roam:
          final OfficialMission? mission = _arrivalMission(widget.event);
          if (!mounted) return;
          context.push(
            Uri(
              path: '/roam/official',
              queryParameters: <String, String>{
                'eventId': '${widget.event.id}',
                if (mission != null) 'missionCode': mission.missionCode,
              },
            ).toString(),
          );
          return;
        case OfficialCtaType.wait:
        case OfficialCtaType.ended:
          return;
      }
      // ★ 只 invalidate,不本地改 signed —— V2 契约只认服务端事实。
      ref.invalidate(officialEventProvider(widget.event.id));
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

  OfficialMission? _arrivalMission(OfficialEvent event) {
    for (final OfficialMission mission in event.missions) {
      if (mission.canVerifyArrival && !mission.complete) return mission;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final cta = officialEventCta(e);
    final countdown = officialEventCountdown(e, DateTime.now());
    final rewards = officialEventRewards(e);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space5,
            ),
            children: <Widget>[
              _Poster(event: e, countdown: countdown),
              const SizedBox(height: CyTokens.space4),
              if (e.collective?.enabled == true) ...<Widget>[
                _CollectiveBlock(
                  progress: e.collective!,
                  hasReward: officialEventHasCollectiveReward(e),
                ),
                const SizedBox(height: CyTokens.space3),
              ],
              _StatBlock(event: e, countdown: countdown),
              if (e.isV2) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _V2Contract(event: e),
              ],
              if ((e.story ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _Block(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const CySectionTitle('详情信息'),
                      const SizedBox(height: CyTokens.space2),
                      Text(e.story!, style: CyType.body),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: CyTokens.space3),
              _Block(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const CySectionTitle('活动奖励'),
                    const SizedBox(height: CyTokens.space2),
                    // F22:只展示后端真实配了的奖励;一个字都没配就如实说明,
                    // **不摆默认承诺**(结算时发不出来的奖不如不写)。
                    if (rewards.isEmpty)
                      Text(
                        '主办方尚未配置奖励，页面不承诺任何奖励。',
                        style: CyType.caption1.copyWith(
                          color: CyTokens.textSecondary,
                        ),
                      )
                    else
                      Wrap(
                        spacing: CyTokens.space2,
                        runSpacing: CyTokens.space2,
                        children: rewards
                            .map((String r) => CyTag(label: r))
                            .toList(),
                      ),
                    if (rewards.isNotEmpty) ...<Widget>[
                      const SizedBox(height: CyTokens.space2),
                      Text(
                        '完成活动任务后按上方配置发放\n实际发放结果以活动结算为准',
                        style: CyType.caption1.copyWith(
                          color: CyTokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space2,
              CyTokens.pageX,
              CyTokens.space3,
            ),
            child: SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                // ★ 不可点的态按钮就是禁用的。文案说「已暂停 / 等待可验证任务」
                //   却还能点下去,是本项目反复出现的缺陷类型。
                onPressed: (!cta.enabled || _busy) ? null : () => _onCta(cta),
                label: cta.text,
                loading: _busy,
                width: double.infinity,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.event, required this.countdown});
  final OfficialEvent event;
  final String countdown;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      child: Container(
        height: 200,
        color: CyTokens.bgElevated,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // ★ 封面走 CyNetImage(V4)—— URL 挂了或为空时安静地留一块同色底,
            //   不画系统碎图标(此前这里是裸 `NetworkImage`,没有兜底)。
            CyNetImage(event.coverImg, fit: BoxFit.cover),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, CyTokens.overlay],
                ),
              ),
              padding: const EdgeInsets.all(CyTokens.space3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: CyTokens.space2,
                    children: <Widget>[
                      CyTag(label: officialEventStatusText(event.status)),
                      if ((event.city ?? '').isNotEmpty)
                        CyTag(label: event.city!),
                    ],
                  ),
                  // 真源 od-organizer:「城瘾官方 · 发起」—— 官方活动的主办方是平台,
                  // 不写这一行,用户分不清这是官方办的还是别人挂上来的。
                  const Padding(
                    padding: EdgeInsets.only(top: CyTokens.space1),
                    child: Text('城瘾官方 · 发起'),
                  ),
                  const SizedBox(height: CyTokens.space2),
                  Text(event.title, style: CyType.title2),
                  if ((event.subtitle ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space1),
                      child: Text(
                        event.subtitle!,
                        style: CyType.caption1.copyWith(
                          color: CyTokens.textSecondary,
                        ),
                      ),
                    ),
                  if (countdown.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: CyTokens.space1_5),
                      child: Text(countdown, style: CyType.caption1),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyTokens.borderSubtle),
      ),
      child: child,
    );
  }
}

class _CollectiveBlock extends StatelessWidget {
  const _CollectiveBlock({required this.progress, required this.hasReward});
  final CollectiveProgress progress;

  /// 配了集体券才敢承诺「达标发放」;没配就如实说进度只是进度(真源同此两档)。
  final bool hasReward;

  @override
  Widget build(BuildContext context) {
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('全城已点亮 ${progress.pct}%', style: CyType.headline),
          const SizedBox(height: CyTokens.space2),
          ClipRRect(
            borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            child: LiquidGlassProgressView(
              progress: (progress.pct / 100).clamp(0.0, 1.0).toDouble(),
              height: 6,
              trackTintColor: CyTokens.bgSurfaceStrong,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            '${progress.current} / ${progress.threshold}',
            style: CyType.caption1.copyWith(color: CyTokens.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            hasReward ? '开启且集体达标、本人保持有效报名并完成全部任务后发放集体奖励' : '当前未配置集体奖励，全城进度仅供了解',
            style: CyType.caption1.copyWith(color: CyTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 事实条。真源 `od-facts`(scroll-view scroll-x)六格:
/// 参与 / 我的进度 / 活动周期 / 开放时间 / 活动范围 / 活动任务。
/// 放不下就横滑,不换行也不省略 —— 少一格用户就得靠猜。
class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.event, required this.countdown});
  final OfficialEvent event;
  final String countdown;

  @override
  Widget build(BuildContext context) {
    final OfficialEvent e = event;
    final List<List<String>> facts = <List<String>>[
      <String>['参与', '${e.participants}', '人已报名'],
      if (e.signed)
        <String>[
          '我的进度',
          e.isV2 ? '${e.taskDone}/${e.taskTotal}' : '${e.myProgress}',
          e.isV2 ? '有效任务' : '已完成',
        ],
      <String>['活动周期', officialEventDurationText(e), '总时长'],
      <String>['开放时间', officialEventDateRange(e), '北京时间'],
      <String>[
        '活动范围',
        (e.city ?? '').isEmpty ? '全国' : e.city!,
        countdown.isNotEmpty ? countdown : officialEventStatusText(e.status),
      ],
      if (e.taskTotal > 0) <String>['活动任务', '${e.taskTotal}', '项任务'],
    ];
    return _Block(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final List<String> fact in facts)
              SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      fact[0],
                      style: CyType.caption1.copyWith(
                        color: CyTokens.textTertiary,
                      ),
                    ),
                    const SizedBox(height: CyTokens.space1),
                    Text(fact[1], style: CyType.headline),
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      fact[2],
                      style: CyType.caption1.copyWith(
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _V2Contract extends StatelessWidget {
  const _V2Contract({required this.event});
  final OfficialEvent event;

  @override
  Widget build(BuildContext context) {
    return _Block(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const CySectionTitle('我的活动任务'),
                    Text(
                      '只接受服务端验证的事实,不使用旧进度加一。',
                      style: CyType.caption1.copyWith(
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              CyTag(label: event.eligibleText),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          if (!event.signed)
            Text(
              '报名后发生的新到达或主题完成才会归入本场活动。',
              style: CyType.caption1.copyWith(color: CyTokens.textSecondary),
            ),
          if (event.paused)
            Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space2),
              child: Text(
                '活动暂时暂停:${event.pausedReason ?? '等待运营处理后恢复'}',
                style: CyType.caption1.copyWith(color: CyTokens.statusWarning),
              ),
            ),
          ...event.missions.asMap().entries.map((
            MapEntry<int, OfficialMission> entry,
          ) {
            final m = entry.value;
            return Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Row(
                children: <Widget>[
                  Container(
                    // 任务序号圆点。不用 Material `CircleAvatar` —— 它是
                    // Material 形状件,iOS 27 语言里换成实色圆形容器。
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: m.complete
                          ? CyTokens.statusSuccess
                          : CyTokens.bgSurfaceStrong,
                    ),
                    child: Text(
                      m.complete ? '✓' : '${entry.key + 1}',
                      style: CyType.caption1,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(m.title, style: CyType.body),
                        Text(
                          m.description ?? m.missionType ?? '',
                          style: CyType.caption1.copyWith(
                            color: CyTokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    m.actionText,
                    style: CyType.caption1.copyWith(
                      color: CyTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (event.missions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                '运营方尚未配置可验证任务。',
                style: CyType.caption1.copyWith(color: CyTokens.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
