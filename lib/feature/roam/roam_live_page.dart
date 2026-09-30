import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/models/activity.dart' show MyRegistration, TicketState;
import '../../data/models/roam.dart';
import '../../data/models/roam_session.dart'
    show RoamHistorySummary, RoamSession;
import '../../data/models/roam_social.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../search/city_node_search_page.dart';
import '../team/team_nearby_page.dart'
    show showTeamMarkerSheet, teamMapApiProvider;
import 'roam_hangout_logic.dart';
import 'roam_history_page.dart';
import 'roam_live_controller.dart';
import 'roam_live_math.dart';
import 'roam_team_markers.dart';

/// 小程序 `pages/roam/index.wxml` 仅在 `screen == 'intro'` 显示五项底栏。
///
/// App 中 [RoamLivePhase.idle] 就是 intro；启动、运行、结算与完成态都是
/// 沉浸式全屏任务，不显示顶级 Tab Bar。
bool roamPhaseShowsPlayerTabBar(RoamLivePhase phase) =>
    phase == RoamLivePhase.idle;

@immutable
class RoamIntroTopic {
  const RoamIntroTopic({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.freeExplore,
  });

  final String title;
  final String subtitle;
  final String route;
  final bool freeExplore;
}

final roamIntroTopicsProvider =
    FutureProvider.autoDispose<List<RoamIntroTopic>>((ref) async {
      final List<MyRegistration> registrations = await ref
          .watch(activityApiProvider)
          .topicTicketList();
      return registrations
          .map(roamIntroTopicFromRegistration)
          .whereType<RoamIntroTopic>()
          .toList(growable: false);
    });

RoamIntroTopic? roamIntroTopicFromRegistration(MyRegistration registration) {
  if (registration.ticketState != TicketState.ready) return null;
  final int? activityId =
      registration.activityId ??
      (registration.ownerType == 2 ? registration.ownerId : null);
  final int? topicId =
      registration.topicId ??
      (registration.ownerType == 1 ? registration.ownerId : null);
  final String route;
  if (activityId != null && activityId > 0) {
    route = '/play/$activityId?registrationId=${registration.id}';
  } else if (topicId != null && topicId > 0) {
    route = '/play/0?topicId=$topicId&registrationId=${registration.id}';
  } else {
    return null;
  }
  return RoamIntroTopic(
    title: (registration.title ?? '').trim().isEmpty
        ? (registration.isFreeExplore ? '自由探索' : '城市定向')
        : registration.title!.trim(),
    subtitle: registration.isFreeExplore ? '任选一处开始探索' : '按顺序走完整条路线',
    route: route,
    freeExplore: registration.isFreeExplore,
  );
}

/// City Fog 实时漫游。
///
/// 本页只承载自由漫游主流程；历史回看继续由 `/roam/session` 负责。
class RoamLivePage extends ConsumerWidget {
  const RoamLivePage({super.key, this.eventId, this.missionCode});

  final int? eventId;
  final String? missionCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RoamLiveState state = ref.watch(roamLiveControllerProvider);
    final List<RoamSession> sessions =
        ref.watch(roamHistoryProvider).value ?? const <RoamSession>[];
    final List<RoamIntroTopic> topics = state.phase == RoamLivePhase.idle
        ? ref.watch(roamIntroTopicsProvider).value ?? const <RoamIntroTopic>[]
        : const <RoamIntroTopic>[];
    final String profileAvatar =
        ref.watch(authControllerProvider).user?.avatar ?? '';
    return Scaffold(
      body: switch (state.phase) {
        RoamLivePhase.starting => const Center(
          child: CupertinoActivityIndicator(),
        ),
        RoamLivePhase.roaming ||
        RoamLivePhase.finishing => _RoamingBody(state: state),
        RoamLivePhase.finished => _SettlementBody(state: state),
        RoamLivePhase.idle => RoamIntroView(
          sessions: sessions,
          topics: topics,
          error: state.error,
          onStart: () => _start(context, ref),
          onStartAndShoot: () =>
              _start(context, ref, openCameraAfterStart: true),
          onOpenRules: () => _showRoamRules(context),
          onOpenHistory: () => context.push('/roam/history'),
          onOpenStampAlbum: () => context.push('/roam/stamp-album'),
          onOpenBadges: () =>
              unawaited(_openNeedsLogin(context, ref, '/badges')),
          onOpenTopic: (String route) => context.push(route),
          onOpenOfficialEvents: () => context.push('/official-events'),
          onDiscoverShops: () =>
              unawaited(_openNeedsLogin(context, ref, '/merchant/discover')),
          onOpenSearchMap: () => context.push(searchMapLocation()),
          onOpenProfile: () => context.go('/profile'),
          profileAvatar: profileAvatar,
        ),
      },
    );
  }

  /// 护照瓷贴里指向整页需登录路由的落点(勋章墙 / 发现店铺)。游客在入口
  /// 先就地弹登录、登完接着进目标页 —— 不能让他 push 后被路由静默弹回首页
  /// (B1 二轮报告 N3:首轮问题 2 同型、新入口;正常路径本就由动作点先弹登录)。
  Future<void> _openNeedsLogin(
    BuildContext context,
    WidgetRef ref,
    String route,
  ) async {
    if (!await requireLogin(context, ref) || !context.mounted) return;
    context.push(route);
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref, {
    bool openCameraAfterStart = false,
  }) async {
    if (!await requireLogin(context, ref) || !context.mounted) return;
    final bool accepted = await cyConfirm(
      context,
      title: '开启实时定位',
      content: '仅在本页前台使用定位，用来绘制足迹、揭示迷雾和校验到店；离开页面即停止。',
      confirmText: '同意并开始',
      cancelText: '暂不开启',
    );
    if (!context.mounted) return;
    await ref
        .read(roamLiveControllerProvider.notifier)
        .start(
          purposeAccepted: accepted,
          eventId: eventId,
          missionCode: missionCode,
        );
    if (!context.mounted || !openCameraAfterStart) return;
    if (ref.read(roamLiveControllerProvider).phase == RoamLivePhase.roaming) {
      await context.push('/roam/stamp-camera');
    }
  }

  Future<void> _showRoamRules(BuildContext context) {
    return showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.38,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              _RoamRulesSheet(scrollController: scrollController),
    );
  }
}

class _RoamRulesSheet extends StatelessWidget {
  const _RoamRulesSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: CyTokens.bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text('自由漫游怎么玩')),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space4,
            CyTokens.pageX,
            CyTokens.space6,
          ),
          children: <Widget>[
            Text('不绑定路线，随走随发现城市。', style: textTheme.titleMedium),
            const SizedBox(height: CyTokens.space4),
            const _RoamRuleRow(title: '开始', body: '点“开启定位并出发”后，地图才会回到你身边。'),
            const _RoamRuleRow(title: '探索', body: '走近街区可点亮迷雾；附近内容会在地图上出现。'),
            const _RoamRuleRow(title: '记录', body: '本次足迹保存在本机；演示点只供浏览，不能打卡。'),
          ],
        ),
      ),
    );
  }
}

class _RoamRuleRow extends StatelessWidget {
  const _RoamRuleRow({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(child: Text(body, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 漫游默认根的公开 widget seam。
///
/// 只负责起始页/护照的展示与点击分发；实时定位和服务端回执仍由
/// [roamLiveControllerProvider] 独占，避免视觉改版复制业务状态机。
class RoamIntroView extends StatefulWidget {
  const RoamIntroView({
    super.key,
    required this.sessions,
    required this.topics,
    required this.onStart,
    required this.onStartAndShoot,
    required this.onOpenRules,
    required this.onOpenHistory,
    required this.onOpenStampAlbum,
    required this.onOpenBadges,
    required this.onOpenTopic,
    required this.onOpenOfficialEvents,
    required this.onDiscoverShops,
    required this.onOpenProfile,
    this.onOpenSearchMap,
    this.profileAvatar = '',
    this.error,
  });

  final List<RoamSession> sessions;
  final List<RoamIntroTopic> topics;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStartAndShoot;
  final VoidCallback onOpenRules;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenStampAlbum;
  final VoidCallback onOpenBadges;
  final ValueChanged<String> onOpenTopic;
  final VoidCallback onOpenOfficialEvents;
  final VoidCallback onDiscoverShops;
  final VoidCallback onOpenProfile;

  final VoidCallback? onOpenSearchMap;
  final String profileAvatar;

  @override
  State<RoamIntroView> createState() => _RoamIntroViewState();
}

class _RoamIntroViewState extends State<RoamIntroView> {
  bool _passport = false;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CyTokens.bgPage,
      child: Stack(
        children: <Widget>[
          if (!_passport)
            Positioned.fill(
              top: CyTokens.space8 * 4 + CyTokens.space6,
              child: KeyedSubtree(
                key: const Key('roam-intro-map'),
                child: AppleSceneView(
                  scene: MapScene.build(points: const <MapPoint>[]),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                CyTokens.space4,
                CyTokens.pageX,
                CyTokens.space4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '漫游',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: CyTokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      if (widget.onOpenSearchMap != null)
                        Semantics(
                          button: true,
                          label: '在地图上搜索',
                          child: CupertinoButton(
                            key: const Key('roam-search-map'),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size.square(CyTokens.btnH),
                            onPressed: widget.onOpenSearchMap,
                            child: const ExcludeSemantics(
                              child: Icon(
                                CupertinoIcons.map,
                                color: CyTokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      // 头像不产语义,包法同旁边「在地图上搜索」(§9.4-10)。
                      Semantics(
                        button: true,
                        label: '打开我的',
                        child: CupertinoButton(
                          key: const Key('roam-profile'),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size.square(CyTokens.btnH),
                          onPressed: widget.onOpenProfile,
                          // 头像交给共用层 CyAvatar:URL 失效有兜底(V4),
                          // 也是本页「附近正在走的人」那一排用的同一个组件。
                          child: ExcludeSemantics(
                            child: CyAvatar(
                              url: widget.profileAvatar,
                              size: CyTokens.btnH,
                              bordered: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space4),
                  Row(
                    children: <Widget>[
                      _IntroTab(
                        label: '开始漫游',
                        selected: !_passport,
                        onTap: () => setState(() => _passport = false),
                      ),
                      const SizedBox(width: CyTokens.space4),
                      _IntroTab(
                        label: '漫游护照',
                        selected: _passport,
                        onTap: () => setState(() => _passport = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space4),
                  Expanded(
                    child: _passport
                        ? _PassportBody(
                            sessions: widget.sessions,
                            onOpenHistory: widget.onOpenHistory,
                            onOpenStampAlbum: widget.onOpenStampAlbum,
                            onOpenBadges: widget.onOpenBadges,
                            onOpenOfficialEvents: widget.onOpenOfficialEvents,
                            onDiscoverShops: widget.onDiscoverShops,
                          )
                        : _StartBody(
                            error: widget.error,
                            onStart: widget.onStart,
                            onStartAndShoot: widget.onStartAndShoot,
                            onOpenRules: widget.onOpenRules,
                            onOpenHistory: widget.onOpenHistory,
                            topics: widget.topics,
                            onOpenTopic: widget.onOpenTopic,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroTab extends StatelessWidget {
  const _IntroTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        onPressed: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space1),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: selected ? CyTokens.textPrimary : CyTokens.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _StartBody extends StatelessWidget {
  const _StartBody({
    required this.error,
    required this.onStart,
    required this.onStartAndShoot,
    required this.onOpenRules,
    required this.onOpenHistory,
    required this.topics,
    required this.onOpenTopic,
  });

  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStartAndShoot;
  final VoidCallback onOpenRules;
  final VoidCallback onOpenHistory;
  final List<RoamIntroTopic> topics;
  final ValueChanged<String> onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    // 真源 `.intro-cards` 定高 192rpx = 96pt(space5×4);字体放大时按整档让位。
    final double cardsHeight =
        CyTokens.space5 * 4 + math.max(0, textScale - 1) * CyTokens.space8;
    return Column(
      children: <Widget>[
        SizedBox(
          key: const Key('roam-intro-cards'),
          height: cardsHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              if (topics.isNotEmpty)
                for (int index = 0; index < topics.length; index++) ...<Widget>[
                  _IntroCard(
                    key: Key('roam-intro-topic-$index'),
                    icon: topics[index].freeExplore
                        ? CupertinoIcons.compass
                        : CupertinoIcons.map,
                    title: topics[index].title,
                    subtitle: topics[index].subtitle,
                    onTap: () => onOpenTopic(topics[index].route),
                  ),
                  const SizedBox(width: CyTokens.space3),
                ]
              else ...<Widget>[
                _IntroCard(
                  key: const Key('roam-intro-card-free'),
                  icon: CupertinoIcons.info,
                  title: '自由漫游',
                  subtitle: '走到哪，雾散到哪。没有固定路线。',
                  onTap: onOpenRules,
                ),
                const SizedBox(width: CyTokens.space3),
                _IntroCard(
                  key: const Key('roam-intro-card-history'),
                  icon: CupertinoIcons.map,
                  title: '足迹记录',
                  // 真源 index.js:291 是两句话,后半句「记录只保存在这台手机上」
                  // 是隐私承诺,不许裁。
                  subtitle: '回看每一次走过的城市片段。记录只保存在这台手机上。',
                  onTap: onOpenHistory,
                ),
                const SizedBox(width: CyTokens.space3),
              ],
              // 小程序 `pages/roam/index.js` 的 HANGOUT_INTRO_CARD(9-15 地图组队 P 方案):
              // 首屏固定入口卡「附近的队伍」,不发轻查、不编数字,**永远**排在已报名章节卡之后
              // (小程序的默认卡组与加载完报名卡之后的 `cards.concat([HANGOUT_INTRO_CARD])`
              // 都带着它)。指向 `/team/nearby`,不新增回调 —— 复用 onOpenTopic。
              _IntroCard(
                key: const Key('roam-intro-card-nearby-teams'),
                icon: CupertinoIcons.location_solid,
                title: '附近的队伍',
                subtitle: '看看附近在招募的队伍',
                onTap: () => onOpenTopic('/team/nearby'),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (error != null) ...<Widget>[
          Text(
            error!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CyTokens.statusDanger),
          ),
          const SizedBox(height: CyTokens.space2),
        ],
        const SizedBox(height: CyTokens.space3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _RoundAction(
              icon: CupertinoIcons.info,
              tooltip: '自由漫游玩法说明',
              onTap: onOpenRules,
            ),
            const SizedBox(width: CyTokens.space5),
            Semantics(
              label: '开启定位并开始自由漫游',
              button: true,
              child: CupertinoButton(
                key: const Key('roam-go'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onStart();
                },
                child: Container(
                  width: CyTokens.space8 * 2 + CyTokens.space4,
                  height: CyTokens.space8 * 2 + CyTokens.space4,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: CyTokens.actionPrimaryBg,
                  ),
                  child: const Text(
                    'GO',
                    style: TextStyle(
                      color: CyTokens.actionPrimaryFg,
                      fontSize: CyTokens.typePageTitle,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space5),
            _RoundAction(
              icon: CupertinoIcons.camera,
              tooltip: '开始漫游并拍照',
              onTap: onStartAndShoot,
            ),
          ],
        ),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: MediaQuery.sizeOf(context).width - CyTokens.space7 * 2,
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: const BoxDecoration(
          // 真源 pages/roam/index.wxss:747 卡底就是主 CTA 色(亮岛),非误用。
          color: CyTokens.actionPrimaryBg,
          borderRadius: BorderRadius.all(Radius.circular(CyTokens.radiusLg)),
          // 真源 :748 box-shadow:0 2rpx 16rpx rgba(0,0,0,.4) ds-ok
          boxShadow: [
            BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              key: const Key('roam-intro-card-icon-slot'),
              width: CyTokens.space6 * 2,
              height: CyTokens.space6 * 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 白卡是深底页里的「亮岛」(wxss:749),卡内取色一律用反色语义:
                // textPrimary 在近白底上是 8% 白叠白 = 槽整个消失(同 cy_palette
                // bgSubtle 记过的坑),真源的 #F2F2F2 浅灰槽要靠 fg 压暗还原。
                color: CyTokens.actionPrimaryFg.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              child: Icon(icon, color: CyTokens.actionPrimaryFg),
            ),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    // `.intro-card__title` white-space:nowrap —— 长章节名截断,
                    // 不许换行撑破定高卡带。
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CyTokens.actionPrimaryFg,
                      fontSize: CyTokens.typeCardTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CyTokens.actionPrimaryFg.withValues(alpha: 0.58),
                      fontSize: CyTokens.typeCaption,
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

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: CupertinoButton(
        onPressed: onTap,
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        child: Container(
          width: CyTokens.space7 + CyTokens.space4,
          height: CyTokens.space7 + CyTokens.space4,
          decoration: BoxDecoration(
            color: CyTokens.bgElevated,
            border: Border.all(color: CyTokens.borderStrong),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: CyTokens.textPrimary),
        ),
      ),
    );
  }
}

class _PassportBody extends StatelessWidget {
  const _PassportBody({
    required this.sessions,
    required this.onOpenHistory,
    required this.onOpenStampAlbum,
    required this.onOpenBadges,
    required this.onOpenOfficialEvents,
    required this.onDiscoverShops,
  });

  final List<RoamSession> sessions;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenStampAlbum;
  final VoidCallback onOpenBadges;
  final VoidCallback onOpenOfficialEvents;
  final VoidCallback onDiscoverShops;

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final double cardHeight =
        CyTokens.space8 * 3 +
        CyTokens.space5 +
        math.max(0, textScale - 1) * CyTokens.space8;
    final RoamHistorySummary summary = RoamHistorySummary.fromSessions(
      sessions,
    );
    final int stamps = sessions.fold<int>(
      0,
      (int total, RoamSession session) => total + session.photos.length,
    );
    final int activeDays = sessions
        .map((RoamSession session) => session.dateTime)
        .whereType<DateTime>()
        .map((DateTime date) => '${date.year}-${date.month}-${date.day}')
        .toSet()
        .length;
    return ListView(
      children: <Widget>[
        Row(
          children: <Widget>[
            _PassportStat('${summary.trips}', '漫游'),
            _PassportStat('${summary.shops}', '探店'),
            _PassportStat('$activeDays', '活跃日'),
            _PassportStat(summary.kmText, '公里'),
          ],
        ),
        const SizedBox(height: CyTokens.space5),
        SizedBox(
          height: cardHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _PassportCard(
                key: const Key('roam-passport-history'),
                icon: CupertinoIcons.map,
                title: '漫游记录',
                subtitle: '${summary.trips} 次旅程',
                onTap: onOpenHistory,
              ),
              const SizedBox(width: CyTokens.space3),
              _PassportCard(
                key: const Key('roam-passport-stamps'),
                icon: CupertinoIcons.photo_on_rectangle,
                title: '集邮册',
                subtitle: '$stamps 张邮票',
                onTap: onOpenStampAlbum,
              ),
              const SizedBox(width: CyTokens.space3),
              _PassportCard(
                key: const Key('roam-passport-badges'),
                icon: CupertinoIcons.rosette,
                title: '勋章墙',
                subtitle: '我的徽章',
                onTap: onOpenBadges,
              ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        SizedBox(
          key: const Key('roam-passport-play-cards'),
          height: cardHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _PassportCard(
                key: const Key('roam-passport-official-events'),
                icon: CupertinoIcons.calendar,
                title: '官方活动',
                subtitle: '限时任务与奖励',
                onTap: onOpenOfficialEvents,
              ),
              const SizedBox(width: CyTokens.space3),
              _PassportCard(
                key: const Key('roam-passport-discover-shops'),
                icon: CupertinoIcons.building_2_fill,
                title: '发现附近店铺',
                subtitle: '现在能去哪',
                onTap: onDiscoverShops,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PassportStat extends StatelessWidget {
  const _PassportStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: CyTokens.space1),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PassportCard extends StatelessWidget {
  const _PassportCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        width: CyTokens.space8 * 3,
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyTokens.bgSurface,
          border: Border.all(color: CyTokens.borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: CyTokens.textPrimary),
            const Spacer(),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: CyTokens.space1),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoamingBody extends ConsumerWidget {
  const _RoamingBody({required this.state});

  final RoamLiveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final RoamLivePosition location = state.location!;
    // 附近的队伍 + 主题/活动(小程序 `subpackageRoam/nearby` 的地图图层):
    // 与 `/team/nearby` 列表页共用同一份 `decorateTeam` 输出,不各算一套状态。
    final RoamNearbyLayer nearby =
        ref.watch(roamNearbyLayerProvider).value ?? const RoamNearbyLayer();
    final MapCoordinate center = MapCoordinate(
      latitude: location.latitude,
      longitude: location.longitude,
    );
    final List<MapPoint> route = <MapPoint>[
      for (int i = 0; i < state.track.length; i++)
        MapPoint(
          id: 'track-$i',
          latitude: state.track[i].latitude,
          longitude: state.track[i].longitude,
          sortOrder: i,
        ),
    ];
    final MapScene scene = MapScene(
      points: <MapPoint>[
        for (final RoamPoi poi in state.pois)
          if (_isPoiVisible(poi))
            MapPoint(
              id: 'roam-poi-${poi.id}',
              latitude: poi.lat,
              longitude: poi.lng,
              title: poi.name,
              subtitle: poi.type == 2 ? '商户据点' : '城市地点',
              state:
                  state.discoveredPoiIds.contains(poi.id) ||
                      state.visitedShopIds.contains(poi.id)
                  ? MapPointState.done
                  : MapPointState.normal,
              fenceRadiusMeters: (poi.radiusM ?? 120).toDouble(),
            ),
        // 附近正在走的人:位置是服务端截位后的 ≈100m,只用来「看得出有人在走」。
        for (final RoamRunner runner in state.nearbyRunners)
          MapPoint(
            id: 'runner-${runner.memberId}',
            latitude: runner.lat,
            longitude: runner.lng,
            title: runner.nickname,
            subtitle: '在走 ${roamElapsedLabel(runner.elapsedSec)}',
            state: MapPointState.locked,
          ),
        ...roamNearbyMarkerPoints(teams: nearby.teams, items: nearby.items),
      ],
      routePoints: route,
      center: center,
      userLocation: center,
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        AppleSceneView(
          key: ValueKey<String>(
            roamTileKey(location.latitude, location.longitude),
          ),
          scene: scene,
          // 两类点位互斥:漫游自己的 POI 是 roam-poi- 前缀,附近层(队伍/主题/活动)是纯数字 id。
          onPointTap: (MapPoint point) => unawaited(
            point.id.startsWith('roam-poi-')
                ? _onPointTap(context, ref, point)
                : _openMarker(context, ref, point),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _FogTilesPainter(
              location: location,
              revealedTiles: state.revealedTiles,
            ),
          ),
        ),
        Positioned(
          left: CyTokens.pageX,
          right: CyTokens.pageX,
          top: CyTokens.space3,
          child: _RoamHud(state: state),
        ),
        if (_visiblePois.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: safeBottom + CyTokens.space4,
            height: 164,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              scrollDirection: Axis.horizontal,
              itemCount: _visiblePois.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: CyTokens.space3),
              itemBuilder: (BuildContext context, int index) {
                final RoamPoi poi = _visiblePois[index];
                return _PoiCard(
                  poi: poi,
                  discovered: state.discoveredPoiIds.contains(poi.id),
                  visited: state.visitedShopIds.contains(poi.id),
                  busy: state.actionBusy,
                  onAction: () => _actOnPoi(context, ref, poi),
                );
              },
            ),
          ),
        Positioned(
          left: CyTokens.pageX,
          right: CyTokens.pageX,
          bottom: safeBottom + (_visiblePois.isEmpty ? CyTokens.space4 : 184),
          child: SizedBox(
            height: CyTokens.btnH,
            child: CyNativeButton(
              width: double.infinity,
              onPressed: state.phase == RoamLivePhase.finishing
                  ? null
                  : () => _confirmFinish(context, ref),
              label: state.phase == RoamLivePhase.finishing ? '正在结算…' : '结束漫游',
              loading: state.phase == RoamLivePhase.finishing,
            ),
          ),
        ),
        if (state.optimisticBadge != null)
          Positioned.fill(
            child: _OptimisticBadge(
              badge: state.optimisticBadge!,
              onClose: () => ref
                  .read(roamLiveControllerProvider.notifier)
                  .dismissOptimisticBadge(),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmFinish(BuildContext context, WidgetRef ref) async {
    final bool accepted = await cyConfirm(
      context,
      title: '结束漫游',
      content: '确定结束今天的漫游？结算结果以服务端记录为准。',
      confirmText: '结束并结算',
      cancelText: '继续漫游',
    );
    if (!accepted || !context.mounted) return;
    await ref.read(roamLiveControllerProvider.notifier).finish();
  }

  List<RoamPoi> get _visiblePois => state.pois.where(_isPoiVisible).toList();

  /// 点地图针(源 `bindpoitap`/`onMarkerTap` 两路在 App 合成一路):
  /// 商户针→据点详情;城市地点针→ checkin 三态,反馈全读服务端回执。
  /// 「附近正在走的人」针暂不响应 —— 源的 openRunner 半屏(打招呼/看 TA)
  /// 依赖的入口口径待拍板(gap-spec-roam Q2)。
  Future<void> _onPointTap(
    BuildContext context,
    WidgetRef ref,
    MapPoint point,
  ) async {
    if (!point.id.startsWith('roam-poi-')) return;
    final int? poiId = int.tryParse(point.id.substring('roam-poi-'.length));
    if (poiId == null || state.actionBusy) return;
    final RoamPoi? poi = state.pois
        .where((RoamPoi p) => p.id == poiId)
        .firstOrNull;
    if (poi == null) return;
    if (poi.type == 2) {
      context.push('/roam/poi/${poi.id}');
      return;
    }
    final RoamCheckinResult? result = await ref
        .read(roamLiveControllerProvider.notifier)
        .checkinPin(name: poi.name, poiLat: poi.lat, poiLng: poi.lng);
    if (result == null || !context.mounted) return;
    if (result.outcome == RoamCheckinOutcome.needsScan &&
        result.poiId != null) {
      context.push('/roam/poi/${result.poiId}');
    }
  }

  bool _isPoiVisible(RoamPoi poi) {
    return state.discoveredPoiIds.contains(poi.id) ||
        state.revealedTiles.contains(roamTileKey(poi.lat, poi.lng));
  }

  /// 打卡之后 · 这一站能做什么(小程序原型 f-checkin 的两个入口):
  /// 城市贴纸(拍一张换一张)与今日城市签(写一句换一句)。
  Future<void> _actOnPoi(
    BuildContext context,
    WidgetRef ref,
    RoamPoi poi,
  ) async {
    final RoamLiveController notifier = ref.read(
      roamLiveControllerProvider.notifier,
    );
    if (poi.type == 2) {
      await notifier.visitShop(poi.id);
    } else {
      await notifier.discoverPoi(poi.id);
    }
    if (!context.mounted) return;
    final RoamLiveState next = ref.read(roamLiveControllerProvider);
    final bool hit =
        next.discoveredPoiIds.contains(poi.id) ||
        next.visitedShopIds.contains(poi.id);
    // 没打成卡(太远/失败)时不额外开一屏:原因已经在 HUD 上了。
    if (!hit) return;
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          ListView(
            controller: controller,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      poi.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '已打卡 · 在这儿留下点什么',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _checkinRow(
                context,
                icon: CupertinoIcons.camera,
                title: '城市贴纸',
                sub: '拍一张,传上去,再看别人在此地拍的',
                route:
                    '/roam/citystamp?kind=sticker&place=${Uri.encodeComponent(poi.name)}',
              ),
              _checkinRow(
                context,
                icon: CupertinoIcons.pencil,
                title: '今日城市签',
                sub: '先写再看:写一句,才换来上一个人那张',
                route:
                    '/roam/citystamp?kind=sign&place=${Uri.encodeComponent(poi.name)}',
              ),
              const SizedBox(height: CyTokens.space4),
            ],
          ),
    );
  }

  Widget _checkinRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String sub,
    required String route,
  }) {
    return CupertinoButton(
      minimumSize: const Size(44, 56),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      onPressed: () {
        Navigator.of(context).pop();
        context.push(route);
      },
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: CyTokens.textPrimary),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                Text(sub, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: CyTokens.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// marker 点击分派(真源 `subpackageRoam/nearby/index.js:243` onMarkerTap):
/// 队伍 → 与 `/team/nearby` 列表页同一个半屏;活动 → 活动详情;主题 → 主题页。
/// 漫游自己的点(poi / 附近的人)解析不出身份,原样不理。
Future<void> _openMarker(
  BuildContext context,
  WidgetRef ref,
  MapPoint point,
) async {
  final RoamMarkerHit? hit = parseRoamMarkerId(point.id);
  if (hit == null) return;
  switch (hit.kind) {
    case RoamMarkerKind.team:
      final RoamNearbyLayerController controller = ref.read(
        roamNearbyLayerProvider.notifier,
      );
      final Map<String, dynamic>? row = ref
          .read(roamNearbyLayerProvider)
          .value
          ?.rowOf(hit.id);
      if (row == null) return;
      await showTeamMarkerSheet(
        context: context,
        api: ref.read(teamMapApiProvider),
        row: row,
        onPatch: (Map<String, Object?> patch) =>
            controller.patchTeam(hit.id, patch),
        onDrop: () => controller.dropTeam(hit.id),
        onOpenTeam: (int teamId) => unawaited(context.push('/team/$teamId')),
        onOpenActivity: (int activityId) =>
            unawaited(context.push('/activity/$activityId')),
        // 队长同意会改人数;满员 / 开场会让队伍从地图上消失 —— 以服务端为准重拉。
        onRefresh: () => controller.refreshTeam(hit.id),
      );
    case RoamMarkerKind.activity:
      unawaited(context.push('/activity/${hit.id}'));
    case RoamMarkerKind.topic:
      unawaited(context.push('/topic/${hit.id}'));
  }
}

class _PoiCard extends StatelessWidget {
  const _PoiCard({
    required this.poi,
    required this.discovered,
    required this.visited,
    required this.busy,
    required this.onAction,
  });

  final RoamPoi poi;
  final bool discovered;
  final bool visited;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgGlass,
        border: Border.all(color: CyTokens.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  poi.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              CyTag(label: poi.type == 2 ? '商户' : '地点'),
            ],
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            poi.address ?? poi.description ?? '走近地点，完成发现校验',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: CyNativeButton(
              width: double.infinity,
              onPressed: discovered || visited || busy ? null : onAction,
              label: visited
                  ? '已到店'
                  : (discovered ? '已发现' : (poi.type == 2 ? '到店打卡' : '发现地点')),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoamHud extends ConsumerWidget {
  const _RoamHud({required this.state});

  final RoamLiveState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgGlass,
        border: Border.all(color: CyTokens.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const CyTag(label: '实时探索', brand: true),
              const SizedBox(width: CyTokens.space2),
              Expanded(
                child: Text(
                  '${state.distanceM} m · 新点亮 ${state.newlyRevealed} · 到店 ${state.shops}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CyTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const RoamNearbyLayerRow(),
          if (state.nearbyRunners.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Row(
              children: <Widget>[
                const Icon(
                  CupertinoIcons.person_2,
                  size: 14,
                  color: CyTokens.textSecondary,
                ),
                const SizedBox(width: CyTokens.space1),
                Expanded(
                  child: Text(
                    '附近 ${state.nearbyRunners.length} 人在走',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                CupertinoButton(
                  key: const Key('roam-runners-entry'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      _openRunnersSheet(context, state.nearbyRunners),
                  child: const Text('看看'),
                ),
              ],
            ),
          ],
          if (state.hangoutNear != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            _nearbyHangoutCard(context, ref, state.hangoutNear!),
          ],
          if (state.error != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              state.error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: CyTokens.statusDanger),
            ),
          ],
          if (state.actionMessage != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              state.lastXpAwarded > 0
                  ? '${state.actionMessage} · +${state.lastXpAwarded} 探索值'
                  : state.actionMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: CyTokens.textPrimary),
            ),
          ],
          if (state.boundEvent != null) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    state.boundEvent!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                CupertinoButton(
                  onPressed:
                      state.boundMissionCode == null ||
                          state.arrivalBusy ||
                          state.arrivalCompleted
                      ? null
                      : () => ref
                            .read(roamLiveControllerProvider.notifier)
                            .verifyOfficialArrival(),
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  child: Text(
                    state.arrivalCompleted
                        ? '已验证'
                        : (state.arrivalBusy ? '核验中…' : '验证活动到达'),
                  ),
                ),
              ],
            ),
          ],
          if (state.arrivalMessage != null) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              state.arrivalMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// 附近的人那一排(原型 otherSheet):只显示服务端给的那几样,
  /// 不显示精确坐标,也不给「追过去」的入口。
  Future<void> _openRunnersSheet(
    BuildContext context,
    List<RoamRunner> runners,
  ) {
    return showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          ListView(
            controller: controller,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  CyTokens.space2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '附近正在走的人',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${runners.length} 人在这片 · 位置已做模糊处理',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              for (final RoamRunner runner in runners)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.pageX,
                    vertical: CyTokens.space2,
                  ),
                  child: Row(
                    children: <Widget>[
                      CyAvatar(
                        url: runner.avatar,
                        fallback: runner.nickname,
                        size: 40,
                      ),
                      const SizedBox(width: CyTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(runner.nickname),
                            Text(
                              '${roamSinceLabel(runner.elapsedSec)} · 地盘 ${runner.explorePct}% · '
                              '点亮 ${runner.shops} 家店',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        roamElapsedLabel(runner.elapsedSec),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: CyTokens.space2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
                child: Text(
                  '只显示这会儿正在走的人,走远了就不在这儿了',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: CyTokens.space4),
            ],
          ),
    );
  }

  /// 「附近有人在组局」白卡:数据来自 /api/roam/hangout/nearby,
  /// 点「加入这个局」走 nearby 页(深链 hangoutId 直接开卡)。
  Widget _nearbyHangoutCard(
    BuildContext context,
    WidgetRef ref,
    RoamHangoutItem hangout,
  ) {
    final ({String label, String hm, String short}) when = roamWhenParts(
      hangout.startAt,
    );
    final String sub = <String>[
      when.short.isEmpty ? '常驻 · 不限时间' : when.short,
      hangout.addressName ?? '',
    ].where((String s) => s.isNotEmpty).join(' · ');
    final List<String> faces = hangout.members
        .map((RoamHangoutMember m) => m.avatar ?? '')
        .where((String a) => a.isNotEmpty)
        .take(4)
        .toList();
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyTokens.bgElevated,
        border: Border.all(color: CyTokens.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '附近有人在组局',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              // 纯图标关闭钮要指名道姓(小程序同位 aria-label「关闭附近商家提示」)。
              Semantics(
                button: true,
                label: '关闭附近组局提示',
                child: CupertinoButton(
                  key: const Key('roam-hangout-near-close'),
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => ref
                      .read(roamLiveControllerProvider.notifier)
                      .dismissHangoutNear(),
                  child: const ExcludeSemantics(
                    child: Icon(CupertinoIcons.xmark, size: 16),
                  ),
                ),
              ),
            ],
          ),
          Text(
            hangout.title ?? '附近的局',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: CyTokens.space1),
          Text(sub, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: CyTokens.space2),
          Row(
            children: <Widget>[
              for (final String face in faces)
                Padding(
                  padding: const EdgeInsets.only(right: CyTokens.space1),
                  child: CyAvatar(url: face, size: 24),
                ),
              if (faces.isNotEmpty) const SizedBox(width: CyTokens.space1),
              Expanded(
                child: Text(
                  hangout.memberCount > 0
                      ? '${hangout.memberCount} 人在群里'
                      : '还没人加入',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              CupertinoButton(
                key: const Key('roam-hangout-near-join'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                onPressed: () =>
                    context.push('/roam/nearby?hangoutId=${hangout.id}'),
                child: const Text('加入这个局'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptimisticBadge extends StatelessWidget {
  const _OptimisticBadge({required this.badge, required this.onClose});

  final ShopStreakBadge badge;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CyTokens.overlay,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: Container(
            padding: const EdgeInsets.all(CyTokens.space5),
            decoration: BoxDecoration(
              color: CyTokens.bgElevated,
              border: Border.all(color: CyTokens.borderStrong),
              borderRadius: BorderRadius.circular(CyTokens.radiusXl),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(CupertinoIcons.rosette, size: 48),
                const SizedBox(height: CyTokens.space3),
                Text(badge.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: CyTokens.space2),
                Text(
                  badge.statement ?? '连续到店目标已达成',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CyTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: CyTokens.space2),
                Text(
                  '即时提示 · 最终发章以结算结果为准',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: CyTokens.textTertiary),
                ),
                const SizedBox(height: CyTokens.space4),
                CyNativeButton(label: '继续漫游', onPressed: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettlementBody extends StatelessWidget {
  const _SettlementBody({required this.state});

  final RoamLiveState state;

  @override
  Widget build(BuildContext context) {
    final RoamFinishResult? result = state.finishResult;
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space5),
      children: <Widget>[
        CyPageTitle(
          state.alreadySettled ? '本次漫游已结算' : '漫游完成',
          subtitle: state.alreadySettled
              ? '服务端已完成过这次结算，没有重复发放奖励。'
              : '探索值、点亮数和徽章均来自服务端结算。',
        ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            child: Container(
              padding: const EdgeInsets.all(CyTokens.space4),
              decoration: BoxDecoration(
                color: CyTokens.bgSurface,
                border: Border.all(color: CyTokens.borderSubtle),
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    '+${result.totalXp}',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  Text(
                    '探索值',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CyTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: <Widget>[
                      _SettlementStat('${result.newTiles}', '新格子'),
                      _SettlementStat('${result.newPois}', '新地点'),
                      _SettlementStat('${result.sessionShops}', '到店'),
                    ],
                  ),
                  if (result.medal != null ||
                      result.shopMedal != null) ...<Widget>[
                    const SizedBox(height: CyTokens.space4),
                    const Divider(),
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      result.shopMedal?.name ?? result.medal!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '徽章已由服务端发放',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SettlementStat extends StatelessWidget {
  const _SettlementStat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
        ),
      ],
    );
  }
}

class _FogTilesPainter extends CustomPainter {
  const _FogTilesPainter({required this.location, required this.revealedTiles});

  final RoamLivePosition location;
  final Set<String> revealedTiles;

  @override
  void paint(Canvas canvas, Size size) {
    const double viewportRadiusM = 280;
    const double revealRadiusM = 55;
    final Rect bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(
      bounds,
      Paint()..color = CyTokens.bgPage.withValues(alpha: 0.78),
    );
    final Paint reveal = Paint()..blendMode = BlendMode.clear;
    final double pixelsPerMeter = size.shortestSide / (viewportRadiusM * 2);
    final double longitudeMeters = 111320 * _longitudeScale(location.latitude);
    for (final String key in revealedTiles) {
      final RoamTileBounds? tile = roamTileBounds(key);
      if (tile == null) continue;
      final double eastM =
          (tile.centerLongitude - location.longitude) * longitudeMeters;
      final double northM = (tile.centerLatitude - location.latitude) * 110540;
      canvas.drawCircle(
        Offset(
          size.width / 2 + eastM * pixelsPerMeter,
          size.height / 2 - northM * pixelsPerMeter,
        ),
        revealRadiusM * pixelsPerMeter,
        reveal,
      );
    }
    canvas.restore();
  }

  double _longitudeScale(double latitude) {
    return math.cos(latitude * math.pi / 180).abs().clamp(0.2, 1).toDouble();
  }

  @override
  bool shouldRepaint(covariant _FogTilesPainter oldDelegate) {
    return oldDelegate.location.latitude != location.latitude ||
        oldDelegate.location.longitude != location.longitude ||
        oldDelegate.revealedTiles != revealedTiles;
  }
}
