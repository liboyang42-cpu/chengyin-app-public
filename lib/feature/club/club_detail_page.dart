import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'club_ai_design_sheet.dart';
import 'club_manage_stage.dart';
import 'club_member_actions.dart';
import 'club_ops_access.dart';
import 'club_posts_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/status_view.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../data/api/club_api.dart' show ClubApiException;
import '../../data/api/club_topic_ops_api.dart';
import '../../data/models/club.dart';
import '../../data/models/club_access.dart';
import '../../data/models/club_manage.dart';
import '../../data/models/club_stats.dart';
import '../../data/models/club_topic_ops.dart';
import '../../data/models/my_project.dart';
import '../auth/login_gate.dart';
import '../auth/auth_controller.dart';
import '../../data/models/coop_invite_row.dart';
import '../coop/coop_list_page.dart' show coopInviteListProvider;
import 'club_controller.dart';
import 'club_login_gate.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';

/// 俱乐部详情:封面/简介 + 成员区 + 加入/退出按钮。
class ClubDetailPage extends ConsumerWidget {
  const ClubDetailPage({super.key, required this.clubId});
  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(clubDetailProvider(clubId));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).clubMainDetail)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubMainDetail),
              Expanded(
                child: detail.when(
                  loading: () => const CySkeleton(type: CySkeletonType.detail),
                  // 游客态整页 401(实测生产):详情接口对无 token 的请求返
                  // {"code":401,"msg":"登录状态已失效，请重新登录"}。说成「网络」
                  // 会把人指去查 WiFi,而重试按多少次都还是 401 —— 改成登录引导。
                  error: (Object err, StackTrace st) => clubLoginRequired(err)
                      ? ClubLoginGate(
                          message: stringsOf(context).clubMainDetailLogin,
                          onSignedIn: () =>
                              ref.invalidate(clubDetailProvider(clubId)),
                        )
                      : StatusView(
                          message: stringsOf(context).clubMainDetailLoadError,
                          sub: stringsOf(context).clubMainNetworkRetry,
                          icon: CupertinoIcons.exclamationmark_triangle,
                          onRetry: () =>
                              ref.invalidate(clubDetailProvider(clubId)),
                        ),
                  data: (Club club) => _DetailBody(club: club),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.club});
  final Club club;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _busy = false;
  late String _activeTab = widget.club.isOwner || widget.club.isJoined
      ? 'posts'
      : 'overview';

  Future<void> _toggle() async {
    // 游客先登录(加入/退出俱乐部需账号)。
    if (!await requireLogin(context, ref)) return;
    if (!mounted) return;
    final club = widget.club;
    setState(() => _busy = true);
    try {
      final api = ref.read(clubApiProvider);
      if (club.isJoined) {
        await api.quit(club.id);
      } else {
        await api.join(club.id);
      }
      if (!mounted) return;
      // 成功后刷新详情(连带按钮态/成员数)与成员列表。
      ref.invalidate(clubDetailProvider(club.id));
      ref.invalidate(clubMembersProvider(club.id));
      ref.invalidate(clubListProvider);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        club.isJoined ? stringsOf(context).clubMainLeaveFailed : stringsOf(context).clubMainJoinFailed,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGroupChat() async {
    // 「进入群聊」落 /im/chat/:id —— 同一族 IM 入口都先过登录门,
    // 否则会话过期后这一个按钮会拿回一句 401 原文(b1 报告 P1-1)。
    if (!await requireLogin(context, ref) || !mounted) return;
    final club = widget.club;
    setState(() => _busy = true);
    try {
      final int cid = await ref
          .read(clubApiProvider)
          .chatConversationId(club.id);
      if (!mounted) return;
      context.push(
        '/im/chat/$cid',
        extra: <String, String>{
          'name': club.name.isEmpty ? stringsOf(context).clubMainGroupChat : club.name,
        },
      );
    } catch (e) {
      if (!mounted) return;
      // ★ 后端那句「加入俱乐部后才能进群聊」是**业务态不是故障**,
      //   照原文提示,别渲成「群聊打不开」(API 注释写死了这条)。
      CyNativeNotice.show(
        context,
        clubApiErrorMessage(context, e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareClub() async {
    final club = widget.club;
    await SharePlus.instance.share(
      ShareParams(
        subject: club.name.isEmpty ? stringsOf(context).clubMainChengyinClub : club.name,
        text:
            '${stringsOf(context).clubMainShareIntro(club.name.isEmpty ? stringsOf(context).clubMainThisClub : club.name)}\n'
            'https://api.example.invalid/club/${club.id}',
      ),
    );
  }

  void _openMerchantCoop() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(stringsOf(context).clubMainStartPartnership),
        message: Text(stringsOf(context).clubMainPartnershipHint),
        actions: <Widget>[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              context.push('/my-projects');
            },
            child: Text(stringsOf(context).clubMainChoosePartnershipTheme),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              context.push('/coop/list');
            },
            child: Text(stringsOf(context).clubMainViewPartnerships),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(stringsOf(context).cancel),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    final bool merchantViewer =
        ref.watch(authControllerProvider).user?.effectiveRole == 'merchant';
    final ClubAccess? access = ref.watch(clubAccessProvider(club.id)).value;
    final ClubManageFlags flags = ClubManageFlags(club: club, access: access);
    final tabs = <CyTab>[
      CyTab(key: 'posts', label: stringsOf(context).clubMainPostTab),
      CyTab(key: 'events', label: stringsOf(context).clubMainEvents),
      CyTab(key: 'overview', label: stringsOf(context).clubMainOverview),
      if (flags.showManageTab)
        CyTab(key: 'manage', label: stringsOf(context).clubMainManage, badge: club.pendingJoinRequestCount),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: CyTokens.space7),
      children: <Widget>[
        _ClubHeader(
          club: club,
          busy: _busy,
          merchantViewer: merchantViewer,
          onJoin: _toggle,
          onChat: _openGroupChat,
          onShare: _shareClub,
          onMerchantCoop: _openMerchantCoop,
          onOwnerPrimary: () => setState(() => _activeTab = 'manage'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
          child: CyTabs(
            key: const Key('club-detail-tabs'),
            tabs: tabs,
            active: _activeTab,
            onChanged: (value) => setState(() => _activeTab = value),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: switch (_activeTab) {
            'posts' => ClubPostsSection(
              clubId: club.id,
              canPost: club.isJoined || club.isOwner,
            ),
            'events' => _ClubEventsTab(club: club),
            'manage' when flags.showManageTab => _ClubManageTab(
              club: club,
              access: access,
            ),
            _ => _ClubOverviewTab(club: club),
          },
        ),
      ],
    );
  }
}

class _ClubHeader extends StatelessWidget {
  const _ClubHeader({
    required this.club,
    required this.busy,
    required this.merchantViewer,
    required this.onJoin,
    required this.onChat,
    required this.onShare,
    required this.onMerchantCoop,
    required this.onOwnerPrimary,
  });

  final Club club;
  final bool busy;
  final bool merchantViewer;
  final VoidCallback onJoin;
  final VoidCallback onChat;
  final VoidCallback onShare;
  final VoidCallback onMerchantCoop;
  final VoidCallback onOwnerPrimary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        0,
        CyTokens.pageX,
        CyTokens.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              _Cover(url: club.cover),
              Positioned(
                left: CyTokens.space3,
                bottom: -24,
                child: CyAvatar(url: club.logo, size: 64),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            club.name.isEmpty ? stringsOf(context).clubMainUnnamedClub : club.name,
            style: textTheme.headlineSmall,
          ),
          const SizedBox(height: CyTokens.space2),
          Wrap(
            spacing: CyTokens.space3,
            runSpacing: CyTokens.space1,
            children: <Widget>[
              _HeaderMeta(
                Icons.sell_outlined,
                club.clubType ?? club.city ?? stringsOf(context).clubMainCityExploration,
              ),
              _HeaderMeta(
                Icons.workspace_premium_outlined,
                stringsOf(context).clubMainHeaderMemberCount(club.memberCount),
              ),
              _HeaderMeta(Icons.public, club.needsApproval ? stringsOf(context).clubMainApprovalRequired : stringsOf(context).clubMainPublic),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          CupertinoButton(
            key: const Key('club-share'),
            padding: EdgeInsets.zero,
            onPressed: onShare,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(CupertinoIcons.share, size: 18),
                const SizedBox(width: CyTokens.space1),
                Text(stringsOf(context).clubMainShareClub),
              ],
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          if (club.isOwner)
            Row(
              children: <Widget>[
                Expanded(
                  child: CyNativeButton(
                    key: const Key('club-group-chat'),
                    onPressed: busy ? null : onChat,
                    label: stringsOf(context).clubMainOpenChat,
                    role: CyNativeButtonRole.secondary,
                    width: double.infinity,
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: CyNativeButton(
                    key: const Key('club-owner-primary'),
                    onPressed: onOwnerPrimary,
                    label: stringsOf(context).clubMainManageProject,
                    width: double.infinity,
                  ),
                ),
              ],
            )
          else if (club.isJoined)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                key: const Key('club-group-chat'),
                onPressed: busy ? null : onChat,
                label: stringsOf(context).clubMainOpenChat,
                width: double.infinity,
              ),
            )
          else if (merchantViewer)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                key: const Key('club-merchant-coop'),
                onPressed: onMerchantCoop,
                label: stringsOf(context).clubMainStartPartnership,
                width: double.infinity,
              ),
            )
          else if (club.joinPending)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                onPressed: null,
                label: stringsOf(context).clubMainAwaitingApproval,
                width: double.infinity,
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                onPressed: busy ? null : onJoin,
                label: club.myJoinStatus == 2 ? stringsOf(context).clubMainReapplyJoin : stringsOf(context).clubMainJoinClub,
                width: double.infinity,
              ),
            ),
          if (club.isJoined && !club.isOwner)
            Align(
              alignment: Alignment.center,
              child: CupertinoButton(
                onPressed: busy ? null : onJoin,
                child: Text(stringsOf(context).clubMainLeaveClub),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 14, color: AppColors.textDisabled),
      const SizedBox(width: 4),
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}

class _ClubEventsTab extends ConsumerWidget {
  const _ClubEventsTab({required this.club});
  final Club club;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(clubTopicsProvider(club.id))
      .when(
        loading: () => const CySkeleton(type: CySkeletonType.detail),
        error: (error, stack) => StatusView(
          message: stringsOf(context).clubMainEventsLoadError,
          onRetry: () => ref.invalidate(clubTopicsProvider(club.id)),
        ),
        data: (rows) => rows.isEmpty
            ? StatusView(
                message: stringsOf(context).clubMainNoRoutes,
                sub: club.isOwner
                    ? stringsOf(context).clubMainPublishRouteHint
                    : stringsOf(context).clubMainWaitForRouteHint,
              )
            : Column(
                children: rows
                    .map(
                      (row) => CyCell(
                        title: row.name.isEmpty ? stringsOf(context).clubMainUnnamedProject : row.name,
                        subtitle:
                            stringsOf(context).clubMainRecruiting(row.dateText.isEmpty ? stringsOf(context).clubMainTimeTbd : stringsOf(context).clubMainDeparture(row.dateText), row.signupCount),
                        leading: const Icon(Icons.route_outlined),
                        // 举报活动挂在活动卡上(真源 ev-acts wxml:206-208,
                        // canReport = canSeeMembers):落到具体场次才立得住案。
                        trailing: club.isOwner || club.isJoined
                            ? CupertinoButton(
                                key: Key('club-topic-report-${row.id}'),
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(44, 44),
                                onPressed: () => _reportTopicActivity(
                                  context,
                                  ref,
                                  club: club,
                                  topicId: row.id,
                                ),
                                child: Text(stringsOf(context).clubMainReportEvent),
                              )
                            : null,
                        onTap: () => context.push('/topic/${row.id}'),
                      ),
                    )
                    .toList(),
              ),
      );
}

class _ClubOverviewTab extends ConsumerWidget {
  const _ClubOverviewTab({required this.club});
  final Club club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranks = ref.watch(
      clubLeaderboardProvider((clubId: club.id, sort: ClubRankSort.composite)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CySectionTitle(stringsOf(context).clubMainIntroduction),
        const SizedBox(height: CyTokens.space2),
        Text(club.description?.isNotEmpty == true ? club.description! : stringsOf(context).clubMainNoIntroduction),
        if (club.leaderName?.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          CySectionTitle(stringsOf(context).clubMainOrganizer),
          const SizedBox(height: CyTokens.space1),
          Text(club.leaderName!),
        ],
        if ((club.city ?? club.address)?.isNotEmpty == true) ...<Widget>[
          const SizedBox(height: CyTokens.space4),
          CySectionTitle(stringsOf(context).clubMainCity),
          const SizedBox(height: CyTokens.space1),
          Text((club.city ?? club.address)!),
        ],
        const SizedBox(height: CyTokens.space5),
        CySectionTitle(stringsOf(context).clubMainMembersHeading(club.memberCount)),
        const SizedBox(height: CyTokens.space2),
        if (club.isOwner || club.isJoined)
          _MemberSection(
            clubId: club.id,
            memberCount: club.memberCount,
            viewerIsCreator: club.isOwner,
          )
        else
          Text(stringsOf(context).clubMainJoinToSeeMembers),
        const SizedBox(height: CyTokens.space5),
        CySectionTitle(stringsOf(context).clubMainContributionRank),
        const SizedBox(height: CyTokens.space2),
        ranks.when(
          loading: () => StatusView(message: stringsOf(context).clubMainRankLoading),
          error: (_, _) => CyCell(
            title: stringsOf(context).clubMainRankLoadError,
            subtitle: stringsOf(context).clubMainReloadHint,
            onTap: () => ref.invalidate(
              clubLeaderboardProvider((
                clubId: club.id,
                sort: ClubRankSort.composite,
              )),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Text(stringsOf(context).clubMainNoCompletions)
              : Column(
                  children: rows
                      .take(5)
                      .map(
                        (row) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CyAvatar(url: row.avatar, size: 36),
                          title: Text(row.nickname ?? stringsOf(context).clubMainPlayer),
                          subtitle: Text(
                            stringsOf(context).clubMainRankMetrics(row.clearCount.toString(), row.mileage.toString(), row.durationMin.toString()),
                          ),
                          trailing: Text('${row.score}'),
                        ),
                      )
                      .toList(),
                ),
        ),
        CyCell(
          title: stringsOf(context).clubMainFullRank,
          subtitle: stringsOf(context).clubMainRankSorts,
          onTap: () => context.push('/club/${club.id}/leaderboard'),
        ),
        // 治理与安全(小程序 detail wxml:383-392):封禁申诉/举报俱乐部只有
        // 这一个入口。申诉**不设闸** —— 被限期封禁的人恰恰看不见成员区,
        // 用 canSeeMembers 拦申诉等于把唯一的出路一起锁了。
        const SizedBox(height: CyTokens.space5),
        CySectionTitle(stringsOf(context).clubMainGovernanceSafety),
        const SizedBox(height: CyTokens.space1),
        Text(
          stringsOf(context).clubMainAppealExplanation,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: CyTokens.space2),
        CyCell(
          key: const Key('club-governance-appeal'),
          title: stringsOf(context).clubMainBanAppeal,
          onTap: () => context.push('/club/${club.id}/governance?mode=appeal'),
        ),
        if (club.isOwner || club.isJoined)
          CyCell(
            key: const Key('club-governance-report-club'),
            title: stringsOf(context).clubMainReportClub,
            onTap: () => context.push(
              '/club/${club.id}/governance'
              '?mode=report&targetType=CLUB&targetId=${club.id}',
            ),
          ),
      ],
    );
  }
}

ClubManageCopy _localizedManageCopy(BuildContext context, ClubManageStage stage) =>
    switch (stage) {
      ClubManageStage.publish => ClubManageCopy(
        stringsOf(context).clubMainStagePublish, stringsOf(context).clubMainStagePublishHint,
      ),
      ClubManageStage.invite => ClubManageCopy(
        stringsOf(context).clubMainStageInvite, stringsOf(context).clubMainStageInviteHint,
      ),
      ClubManageStage.pending => ClubManageCopy(
        stringsOf(context).clubMainStagePending, stringsOf(context).clubMainStagePendingHint,
      ),
      ClubManageStage.accepted => ClubManageCopy(
        stringsOf(context).clubMainStageAccepted, stringsOf(context).clubMainStageAcceptedHint,
      ),
      ClubManageStage.loading => ClubManageCopy(
        stringsOf(context).clubMainStageLoading, stringsOf(context).clubMainStageLoadingHint,
      ),
      ClubManageStage.error => ClubManageCopy(
        stringsOf(context).clubMainStageError, stringsOf(context).clubMainStageErrorHint,
      ),
    };

class _ClubManageTab extends ConsumerWidget {
  const _ClubManageTab({required this.club, this.access});
  final Club club;
  final ClubAccess? access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ClubManageFlags flags = ClubManageFlags(club: club, access: access);
    final AsyncValue<List<ClubTopic>> topics = ref.watch(
      clubTopicsProvider(club.id),
    );
    final merchants = ref.watch(clubCoopMerchantsProvider(club.id));
    final AsyncValue<List<MyProject>> ownerProjects = ref.watch(
      clubOwnerProjectsProvider(club.id),
    );
    final AsyncValue<CoopInviteList> invites = ref.watch(
      coopInviteListProvider,
    );
    final ClubManageStage stage = resolveClubManageStage(
      topics: topics,
      ownerProjects: ownerProjects,
      invites: invites,
    );
    final ClubManageCopy copy = _localizedManageCopy(context, stage);
    final List<ClubTopic> topicRows = topics.value ?? const <ClubTopic>[];
    final MyProject? acceptedProject =
        (ownerProjects.value ?? const <MyProject>[])
            .where((MyProject row) => row.acceptStatus == 'merchantAccepted')
            .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (flags.manageNow)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CyTokens.space4),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            child: Column(
              key: const Key('club-manage-stage'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(stringsOf(context).clubMainNextAction, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: CyTokens.space1),
                Text(
                  copy.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  copy.hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: CyTokens.space3),
                // 阶段式唯一 primary:loading 不给按(error 是「重试」、publish 是
                // 「发布主题」、其余是把人送到那件事发生的地方)。
                CupertinoButton.filled(
                  key: const Key('club-manage-primary'),
                  onPressed: stage == ClubManageStage.loading
                      ? null
                      : () {
                          switch (stage) {
                            case ClubManageStage.loading:
                              break;
                            case ClubManageStage.error:
                              ref.invalidate(clubTopicsProvider(club.id));
                              ref.invalidate(
                                clubOwnerProjectsProvider(club.id),
                              );
                              ref.invalidate(coopInviteListProvider);
                            case ClubManageStage.publish:
                              _chooseTopicModeAndPublish(context, club.id);
                            case ClubManageStage.invite:
                              final ClubTopic? first = topicRows.firstOrNull;
                              if (first != null) {
                                context.push(
                                  '/club/${club.id}/topic/${first.id}',
                                );
                              }
                            case ClubManageStage.pending:
                              context.push(
                                Uri(
                                  path: '/coop/list',
                                  queryParameters: const <String, String>{
                                    'tab': 'sent',
                                  },
                                ).toString(),
                              );
                            case ClubManageStage.accepted:
                              final MyProject? project = acceptedProject;
                              if (project != null) {
                                context.push('/project/home/${project.id}');
                              }
                          }
                        },
                  child: Text(copy.label),
                ),
              ],
            ),
          ),
        if (flags.manageNow) const SizedBox(height: CyTokens.space5),
        if (flags.stats) ...<Widget>[
          CySectionTitle(stringsOf(context).clubMainMembersEventsOverview),
          const SizedBox(height: CyTokens.space2),
          _ClubStatsSection(clubId: club.id),
          const SizedBox(height: CyTokens.space5),
        ],
        _OwnerProjectSection(club: club, flags: flags),
        const SizedBox(height: CyTokens.space5),
        // main 侧新增的「探店日期次」区块:本 PR 没碰它,也不给它加权限闸。
        _ShareEditionSection(club: club),
        const SizedBox(height: CyTokens.space5),
        if (flags.stats) ...<Widget>[
          CySectionTitle(stringsOf(context).clubMainAvailableMerchants),
          const SizedBox(height: CyTokens.space2),
          merchants.when(
            loading: () => StatusView(message: stringsOf(context).clubMainMerchantsLoading),
            error: (_, _) => StatusView(
              message: stringsOf(context).clubMainMerchantsLoadError,
              onRetry: () => ref.invalidate(clubCoopMerchantsProvider(club.id)),
            ),
            data: (rows) => rows.isEmpty
                ? Text(stringsOf(context).clubMainNoMerchants)
                : Column(
                    children: rows.take(8).map((row) {
                      final memberId = (row['memberId'] as num?)?.toInt();
                      final name = (row['name'] ?? row['merchantName'] ?? stringsOf(context).clubMainMerchant)
                          .toString();
                      return CyCell(
                        title: name,
                        subtitle: [
                          row['cityRole'],
                          row['capacity'] == null
                              ? null
                              : stringsOf(context).clubMainCapacity(row['capacity'].toString()),
                          row['availableTime'],
                          row['suitActivityTypes'],
                        ].whereType<Object>().join(' · '),
                        onTap: memberId == null
                            ? null
                            : () => context.push(
                                '/merchant/public-home/member/$memberId',
                              ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: CyTokens.space5),
        ],
        _OpenSettingsSection(clubId: club.id),
        if (flags.toolsPanel) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          CySectionTitle(stringsOf(context).clubMainProjectTools),
          if (flags.publish)
            CyCell(
              title: stringsOf(context).clubMainPublishTheme,
              leading: const Icon(Icons.route_outlined),
              onTap: () =>
                  context.push('/publish/pro?clubId=${club.id}&mode=1'),
            ),
          if (flags.publish)
            CyCell(
              // main 侧 #400 已把「开一场」改成跳运营页预选单次,不发建场请求;
              // 本 PR 只给它补 publish 权限闸,不改接线。
              key: const Key('club-open-event-ops'),
              title: stringsOf(context).clubMainStartSession,
              leading: const Icon(Icons.flag_outlined),
              onTap: () =>
                  context.push('/club/${club.id}/event-ops?recurrence=ONCE'),
            ),
        ],
        if (flags.customers) _CustomerCell(clubId: club.id),
        _ClubOpsCells(club: club, access: access),
        if (flags.customers)
          CyCell(
            title: stringsOf(context).clubMainRegistrationList,
            subtitle: stringsOf(context).clubMainRegistrationHint,
            onTap: () => context.push('/club/${club.id}/enroll'),
          ),
        if (flags.finance) _SettlementCell(clubId: club.id),
        if (flags.finance)
          CyCell(
            title: stringsOf(context).clubMainHoursEvidence,
            onTap: () => context.push('/club/${club.id}/edition-report'),
          ),
        if (flags.toolsPanel)
          CyCell(
            key: const Key('club-ai-design'),
            title: stringsOf(context).clubMainAiPlanning,
            onTap: () => showClubAiDesignSheet(context, clubId: club.id),
          ),
        if (flags.joinRequests)
          CyCell(
            title: stringsOf(context).clubMainJoinRequests(club.pendingJoinRequestCount),
            trailing: club.pendingJoinRequestCount > 0
                ? CyBadge(count: club.pendingJoinRequestCount)
                : null,
            onTap: () => context.push('/club/${club.id}/join-requests'),
          ),
        if (flags.editProfile)
          CyCell(
            title: stringsOf(context).clubMainSettingsDissolve,
            onTap: () => context.push('/club/${club.id}/edit'),
          ),
        if (flags.finance)
          CyCell(
            title: stringsOf(context).clubMainBeforeDissolve,
            subtitle: stringsOf(context).clubMainDepositsSettlements,
            onTap: () => context.push('/club/${club.id}/dissolution-blockers'),
          ),
      ],
    );
  }
}

/// 活动运营 / 角色与权限 / 成员治理 / 通知成员 四行入口。
///
/// 小程序 `pages/club/detail/index.wxml:717,786,796,800` 四条 `cset-row`,
/// 显示条件与 `goEventOps/goClubRoles/goClubGovernance/goClubNotify`
/// (`index.js:773,2056,2071,820`)的守卫**同源** —— 照抄那份闸,
/// 别让「看不见但点得到」或反过来(`index.js:819` 的注释就是这条纪律)。
/// 权限回执没到之前,非主理人先不显示:小程序那三个 can* 也是从 false 起步。
class _ClubOpsCells extends ConsumerWidget {
  const _ClubOpsCells({required this.club, this.access});

  final Club club;
  final ClubAccess? access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ClubManageFlags flags = ClubManageFlags(club: club, access: access);
    if (!flags.eventOps && !flags.roles && !flags.governance && !flags.notify) {
      return const SizedBox.shrink();
    }
    final ClubAccess? scoped = access;
    final int delegated =
        scoped != null && scoped.active && scoped.clubId == club.id
        ? scoped.delegatedRoleCount
        : 0;
    return Column(
      children: <Widget>[
        if (flags.eventOps)
          CyCell(
            key: const Key('club-manage-event-ops'),
            title: stringsOf(context).clubMainEventOperations,
            subtitle: stringsOf(context).clubMainEventOperationsHint,
            onTap: () => context.push('/club/${club.id}/event-ops'),
          ),
        if (flags.roles)
          CyCell(
            key: const Key('club-manage-roles'),
            title: stringsOf(context).clubMainRolesPermissions,
            subtitle: stringsOf(context).clubMainRolesPermissionsHint,
            trailing: delegated > 0
                ? Text(
                    stringsOf(context).clubMainDelegated(delegated),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  )
                : null,
            onTap: () => context.push('/club/${club.id}/roles'),
          ),
        if (flags.governance)
          CyCell(
            key: const Key('club-manage-governance'),
            title: stringsOf(context).clubMainMemberGovernance,
            subtitle: stringsOf(context).clubMainMemberGovernanceHint,
            onTap: () => context.push('/club/${club.id}/governance'),
          ),
        if (flags.notify)
          CyCell(
            key: const Key('club-manage-notify'),
            title: stringsOf(context).clubMainNotifyMembers,
            subtitle: stringsOf(context).clubMainNotifyMembersHint,
            onTap: () => context.push('/club/${club.id}/notify'),
          ),
      ],
    );
  }
}

/// 发布主题:先选哪种主题模式,再进发布页(小程序 `onCreateTeam` 的两模式入口)。
/// 管理 tab 的阶段卡与项目列表的「发布主题」共用同一张 action sheet。
Future<void> _chooseTopicModeAndPublish(
  BuildContext context,
  int clubId,
) async {
  final mode = await showCupertinoModalPopup<int>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(stringsOf(context).clubMainChooseThemeMode),
      actions: <Widget>[
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(1),
          child: Text(stringsOf(context).clubMainSequentialMode),
        ),
        CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(2),
          child: Text(stringsOf(context).clubMainFreeMode),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: Text(stringsOf(context).cancel),
      ),
    ),
  );
  if (mode == null || !context.mounted) return;
  context.push('/publish/pro?clubId=$clubId&mode=$mode');
}

// 场次工具与举报活动共用一条「读该主题下的场次」链路(`/api/topic/info-to-user`
// 的 activityList,同小程序 group-code-session.js 那份过滤)。忙旗标整页级,
// 对齐真源 `this._activityToolsLoading` / `this._activityReportLoading`。
bool _sessionListBusy = false;

Future<List<GroupCodeActivity>?> _loadTopicActivities(
  BuildContext context,
  WidgetRef ref,
  int topicId, {
  required String errorText,
}) async {
  if (_sessionListBusy) return null;
  _sessionListBusy = true;
  try {
    return await ref.read(groupCodeApiProvider).activities(topicId);
  } catch (_) {
    if (context.mounted) {
      CyNativeNotice.show(context, errorText, isError: true);
    }
    return null;
  } finally {
    _sessionListBusy = false;
  }
}

/// 从一叠场次里定一场:只有一场直接进,多场给底部单选(真源「一周多场时
/// 在这里选，不会被系统菜单截断」)。[title]/[sub] 按调用方各自的口径。
Future<int?> _pickTopicActivity(
  BuildContext context, {
  required List<GroupCodeActivity> activities,
  required String title,
  String sub = '',
}) async {
  if (activities.length == 1) return activities.single.id;
  return showCupertinoModalPopup<int>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(title),
      message: sub.isEmpty ? null : Text(sub),
      actions: activities
          .map(
            (GroupCodeActivity a) => CupertinoActionSheetAction(
              key: Key('topic-activity-pick-${a.id}'),
              onPressed: () => Navigator.of(sheetContext).pop(a.id),
              child: Text(a.name),
            ),
          )
          .toList(),
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: Text(stringsOf(context).cancel),
      ),
    ),
  );
}

/// 场次工具(真源 `index.js:824-911`):先选场次,再在「本场工具」里挑一件事。
/// 三个工具各按各的闸 —— 现场名册要运营或核销,委派角色要 role:manage,
/// 通知本场要 operate。没有俱乐部级全域权限、只有单场 scope 的人靠
/// `access.eventAccesses` 逐场放行,那是 #384 权限矩阵的地盘,这里不抢。
Future<void> _openActivityTools(
  BuildContext context,
  WidgetRef ref, {
  required Club club,
  required int topicId,
}) async {
  final activities = await _loadTopicActivities(
    context,
    ref,
    topicId,
    errorText: stringsOf(context).clubMainSessionsLoadError,
  );
  if (activities == null || !context.mounted) return;
  if (activities.isEmpty) {
    CyNativeNotice.show(context, stringsOf(context).clubMainNoManageableSessions);
    return;
  }
  final int? activityId = await _pickTopicActivity(
    context,
    activities: activities,
    title: stringsOf(context).clubMainChooseSession,
    sub: stringsOf(context).clubMainChooseSessionHint,
  );
  if (activityId == null || !context.mounted) return;
  final ClubAccess? access = ref.read(clubAccessProvider(club.id)).value;
  bool allowed(String permission) =>
      access != null &&
      access.active &&
      access.clubId == club.id &&
      access.has(permission);
  final bool canOperateEvent =
      club.isOwner ||
      allowed(kClubActivityManage) ||
      allowed(kClubEventOperate);
  final bool canCheckInEvent =
      club.isOwner ||
      allowed(kClubActivityManage) ||
      allowed(kClubEventCheckin);
  final tools = <({String label, String route})>[
    if (canOperateEvent || canCheckInEvent)
      (
        label: stringsOf(context).clubMainOnsiteRoster,
        route: '/club/${club.id}/event-ops?activityId=$activityId',
      ),
    if (club.isOwner || allowed(kClubRoleManage))
      (
        label: stringsOf(context).clubMainAssignEventRoles,
        route: '/club/${club.id}/roles?activityId=$activityId',
      ),
    if (canOperateEvent)
      (
        label: stringsOf(context).clubMainNotifySession,
        route: '/club/${club.id}/notify?activityId=$activityId',
      ),
  ];
  if (tools.isEmpty || !context.mounted) return;
  if (tools.length == 1) {
    context.push(tools.first.route);
    return;
  }
  final String? route = await showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(stringsOf(context).clubMainSessionTools),
      actions: tools
          .map(
            (tool) => CupertinoActionSheetAction(
              key: Key('activity-tool-${tool.label}'),
              onPressed: () => Navigator.of(sheetContext).pop(tool.route),
              child: Text(tool.label),
            ),
          )
          .toList(),
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: Text(stringsOf(context).cancel),
      ),
    ),
  );
  if (route != null && context.mounted) context.push(route);
}

/// 举报活动(真源 `index.js:2105-2141`):举报必须落到**具体场次**,
/// 所以先 info-to-user 拿 activityList,一场直进、多场选、没有就说没有。
Future<void> _reportTopicActivity(
  BuildContext context,
  WidgetRef ref, {
  required Club club,
  required int topicId,
}) async {
  final activities = await _loadTopicActivities(
    context,
    ref,
    topicId,
    // 真源两条链各说各的失败口径(js:853 场次工具 / js:2135 举报活动)。
    errorText: stringsOf(context).clubMainEventsRetryError,
  );
  if (activities == null || !context.mounted) return;
  if (activities.isEmpty) {
    CyNativeNotice.show(context, stringsOf(context).clubMainNoReportableEvents);
    return;
  }
  final int? activityId = await _pickTopicActivity(
    context,
    activities: activities,
    title: stringsOf(context).clubMainChooseReportSession,
  );
  if (activityId == null || !context.mounted) return;
  context.push(
    '/club/${club.id}/governance'
    '?mode=report&targetType=ACTIVITY&targetId=$activityId',
  );
}

class _OwnerProjectSection extends ConsumerWidget {
  const _OwnerProjectSection({required this.club, required this.flags});

  final Club club;
  final ClubManageFlags flags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(clubTopicsProvider(club.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: CySectionTitle(stringsOf(context).clubMainClubProjects)),
            // 「发布主题」在小程序里挂在阶段卡/添加行上,判据是主理人或活动管理权。
            if (flags.eventOps)
              CupertinoButton(
                key: const Key('club-create-topic'),
                onPressed: () => _chooseTopicModeAndPublish(context, club.id),
                minimumSize: const Size(44, 44),
                child: Text(stringsOf(context).clubMainPublishTheme),
              ),
          ],
        ),
        const SizedBox(height: CyTokens.space2),
        topics.when(
          // 这一块在详情长页靠后，用静态占位，避免离屏骨架常驻呼吸动画。
          loading: () => StatusView(message: stringsOf(context).clubMainProjectsLoading),
          error: (Object error, StackTrace stackTrace) => StatusView(
            message: stringsOf(context).clubMainProjectsLoadError,
            sub: clubApiErrorMessage(context, error),
            onRetry: () => ref.invalidate(clubTopicsProvider(club.id)),
          ),
          data: (List<ClubTopic> rows) {
            if (rows.isEmpty) {
              return StatusView(
                message: stringsOf(context).clubMainNoProjects,
                sub: stringsOf(context).clubMainPublishProjectHint,
              );
            }
            return Column(
              children: rows
                  .map(
                    (row) => CyCell(
                      title: row.name.isEmpty ? stringsOf(context).clubMainUnnamedProject : row.name,
                      subtitle:
                          stringsOf(context).clubMainProjectRegistrations(row.dateText.isEmpty ? stringsOf(context).clubMainTimeTbd : row.dateText, row.signupCount),
                      leading: const Icon(
                        Icons.route_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      // 行本身进「项目主页」(主办/承接双身份聚合);
                      // 「运营」另进俱乐部活动详情 —— 小程序里主理人点主题直接进那一页
                      // (`goTopic` 判 canManage),App 侧两页各有各的用途,都给入口。
                      // 「场次工具」= 真源 manage-project 行上的同名按钮(wxml:490)。
                      // 两个按钮一起按「场次工具」口径显隐(有活动运营权/场次授权才给)。
                      trailing: flags.toolsPanel
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                CupertinoButton(
                                  key: Key(
                                    'club-topic-activity-tools-${row.id}',
                                  ),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(44, 44),
                                  onPressed: () => _openActivityTools(
                                    context,
                                    ref,
                                    club: club,
                                    topicId: row.id,
                                  ),
                                  child: Text(stringsOf(context).clubMainSessionToolsEntry),
                                ),
                                CupertinoButton(
                                  key: Key('club-topic-ops-${row.id}'),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(44, 44),
                                  onPressed: () => context.push(
                                    '/club/${club.id}/topic/${row.id}',
                                  ),
                                  child: Text(stringsOf(context).clubMainOperations),
                                ),
                              ],
                            )
                          : null,
                      onTap: () => context.push('/project/home/${row.id}'),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: CyTokens.space4),
        CySectionTitle(stringsOf(context).clubMainPartnerships),
        const SizedBox(height: CyTokens.space2),
        CyCell(
          title: stringsOf(context).clubMainMyPartnerships,
          subtitle: stringsOf(context).clubMainReceivedPartnershipsHint,
          leading: const Icon(
            Icons.handshake_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onTap: () => context.push('/coop/list'),
        ),
        CyCell(
          title: stringsOf(context).clubMainSentPartnerships,
          subtitle: stringsOf(context).clubMainSentPartnershipsHint,
          leading: const Icon(
            Icons.outbox_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onTap: () => context.push(
            Uri(
              path: '/coop/list',
              queryParameters: const <String, String>{'tab': 'sent'},
            ).toString(),
          ),
        ),
        // 合作池折叠区收编成页(真源 manage-fold wxml:567-610:就地申请带队,
        // 申请记录在「我发出的」)。App 侧整页早就建好,缺的只是这一条路径。
        CyCell(
          key: const Key('club-coop-pool'),
          title: stringsOf(context).clubMainAvailableEvents,
          subtitle: stringsOf(context).clubMainAvailableEventsHint,
          leading: const Icon(
            Icons.explore_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onTap: () => context.push('/coop-pool'),
        ),
      ],
    );
  }
}

/// 探店日期次(真源 manage-fold wxml:504-528 + js:974-1006):
/// 票源归因的**唯一产出口** —— 主理人逐期「带票分享」。候选只认开售冻结
/// 条款里的执行俱乐部(`/api/club-compensation/editions`),并再按
/// executingClubId 过滤一遍(真源 js:994-997,经典项目列表没有这层归属语义)。
class _ShareEditionSection extends ConsumerWidget {
  const _ShareEditionSection({required this.club});
  final Club club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editions = ref.watch(clubEditionsProvider(club.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CySectionTitle(stringsOf(context).clubMainVisitSessions),
        const SizedBox(height: CyTokens.space2),
        editions.when(
          loading: () => StatusView(message: stringsOf(context).clubMainSessionsLoading),
          error: (_, _) => StatusView(
            message: stringsOf(context).clubMainVisitSessionsLoadError,
            onRetry: () => ref.invalidate(clubEditionsProvider(club.id)),
          ),
          data: (List<EditionOption> rows) {
            final mine = rows
                .where((EditionOption e) => e.executingClubId == club.id)
                .toList(growable: false);
            if (mine.isEmpty) {
              return StatusView(
                message: stringsOf(context).clubMainNoShareableSessions,
                sub: stringsOf(context).clubMainVisitSessionsHint,
              );
            }
            return Column(
              children: mine
                  .map(
                    (EditionOption e) => CyCell(
                      title: e.topicName.isEmpty ? stringsOf(context).clubMainSessionNumber(e.id) : e.topicName,
                      subtitle:
                          stringsOf(context).clubMainClubSession(e.dateText.isEmpty ? stringsOf(context).clubMainTimeTbd : e.dateText),
                      showChevron: false,
                      trailing: CupertinoButton(
                        key: Key('club-edition-share-${e.id}'),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(44, 44),
                        onPressed: () => _shareEditionTicket(e),
                        child: Text(stringsOf(context).clubMainShareWithTicket),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  /// 带票链接按真源 `utils/ticket-source.js` 的 `buildSharePath` 拼:
  /// `?id&sourceClubId&clubCode`,clubCode = `club-{cid}-t{topicId}`。
  /// 归因只来自本页 clubId 与冻结条款,不接受外部传入 —— 绝不产假的标记。
  void _shareEditionTicket(EditionOption e) {
    final name = e.topicName.isEmpty ? club.name : e.topicName;
    final code = Uri.encodeComponent('club-${club.id}-t${e.id}');
    SharePlus.instance.share(
      ShareParams(
        subject: name.isEmpty ? stringsOf(context).appName : name,
        text:
            '${name.isEmpty ? stringsOf(context).appName : name} · ${club.name}\n'
            'https://api.example.invalid/topic/${e.id}'
            '?id=${e.id}&sourceClubId=${club.id}&clubCode=$code',
      ),
    );
  }
}

class _MemberSection extends ConsumerWidget {
  const _MemberSection({
    required this.clubId,
    required this.memberCount,
    required this.viewerIsCreator,
  });
  final int clubId;

  /// 我是不是这个俱乐部的**创建者**(后端 `isOwner = club.memberId == 我`)。
  /// ⚠️ 管理成员只有创建者能做,管理员不行 —— 所以不能用「是不是管理员」判。
  final bool viewerIsCreator;

  /// 详情里那个「N 名成员」。★ 它是判「空名单意味着什么」的唯一依据:
  /// 一个 128 人的俱乐部拿到空名单,真相是「这一页没取到」,不是「没有人」。
  final int memberCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(clubMembersProvider(clubId));
    // goMemberProfile 的闸(小程序 detail js:1982):能不能按「客户」打开
    // 这个人。真源还看 club.viewerIsAdmin,App 的 Club 模型没有这个字段,
    // 由 kClubMemberManage 覆盖同一批人。
    final ClubAccess? access = ref.watch(clubAccessProvider(clubId)).value;
    final bool canManageMembers =
        access != null &&
        access.active &&
        access.clubId == clubId &&
        access.has(kClubMemberManage);
    final bool canReadCustomers =
        viewerIsCreator ||
        canManageMembers ||
        (access != null &&
            access.active &&
            access.clubId == clubId &&
            access.canReadMembers);
    // 举报不给自己的行摆(js:2089 myMemberId 比对);App 里用户 id 就是 memberId。
    final int? myMemberId = ref.watch(authControllerProvider).user?.id;
    return members.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: CyTokens.space5),
        child: CySkeleton(type: CySkeletonType.detail),
      ),
      error: (Object err, StackTrace st) => StatusView(
        message: stringsOf(context).clubMainMembersLoadError,
        icon: CupertinoIcons.exclamationmark_triangle,
        onRetry: () => ref.invalidate(clubMembersProvider(clubId)),
      ),
      data: (List<ClubMember> list) {
        if (list.isEmpty) {
          return Text(
            // ★ 同一屏不能自相矛盾:上面写着 128 人、下面说没有人。
            memberCount > 0 ? stringsOf(context).clubMainMemberListUnavailable : stringsOf(context).clubMainNoMembers,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          );
        }
        return Column(
          children: list
              .map(
                (ClubMember m) => _MemberRow(
                  member: m,
                  clubId: clubId,
                  viewerIsCreator: viewerIsCreator,
                  canGovernMembers: viewerIsCreator || canManageMembers,
                  canOpenCustomerDetail: canReadCustomers,
                  isSelf: myMemberId != null && m.memberId == myMemberId,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.clubId,
    required this.viewerIsCreator,
    this.canGovernMembers = false,
    this.canOpenCustomerDetail = false,
    this.isSelf = false,
  });
  final ClubMember member;
  final int clubId;
  final bool viewerIsCreator;

  /// 行右缘「临时封禁」的闸(真源 cset 成员管理面板 js:2076)。
  final bool canGovernMembers;

  /// true → 进客户详情(按人聚合的核销档案);false → 只进公开主页。
  final bool canOpenCustomerDetail;

  /// 这一行是不是我 —— 自己的行不给「举报」。
  final bool isSelf;

  void _openProfile(BuildContext context) {
    if (canOpenCustomerDetail) {
      context.push('/club/$clubId/customers/${member.memberId}');
    } else {
      context.push('/user/${member.memberId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final avatar = member.avatar;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: CupertinoButton(
                  key: Key('club-member-row-${member.memberId}'),
                  // 头像 + 昵称整块可点(真源 cy-avatar 与 member-info 同一 handler)。
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: () => _openProfile(context),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.bgElevated,
                        backgroundImage: (avatar != null && avatar.isNotEmpty)
                            ? NetworkImage(avatar)
                            : null,
                        child: (avatar == null || avatar.isEmpty)
                            ? const Icon(
                                Icons.person_outline,
                                size: 18,
                                color: AppColors.textDisabled,
                              )
                            : null,
                      ),
                      const SizedBox(width: CyTokens.space3),
                      Expanded(
                        child: Text(
                          (member.nickname?.isNotEmpty ?? false)
                              ? member.nickname!
                              : stringsOf(context).clubMainUserNumber(member.memberId),
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ★★★ 徽章此前用 `role == 1` 渲染「创建者」—— 标错人了。
              //   后端 role==1 是**管理员**(ApiClubController:1180
              //   「设置成员角色(创建者:0成员/1管理员)」,1192「管理员至多 2 个,
              //   **主理人之外**」)。创建者是 isOwner,和 role 是两回事。
              //   原来的写法把每个管理员标成创建者,真创建者反而没有徽章。
              if (member.isOwner || member.isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                  ),
                  child: Text(
                    member.isOwner ? stringsOf(context).clubMainCreator : stringsOf(context).clubMainAdministrator,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.accentViolet,
                    ),
                  ),
                ),
              if (!isSelf)
                CupertinoButton(
                  key: Key('club-member-report-${member.memberId}'),
                  minimumSize: const Size(44, CyTokens.btnH),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  // 举报是「向平台反映这个成员」→ governance 报告态带 targetMemberId。
                  onPressed: () => context.push(
                    '/club/$clubId/governance'
                    '?mode=report&targetMemberId=${member.memberId}',
                  ),
                  child: Text(stringsOf(context).clubMainReport, style: textTheme.labelMedium),
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ClubMemberActions(
              clubId: clubId,
              member: member,
              viewerIsCreator: viewerIsCreator,
              canGovernMembers: canGovernMembers,
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.groups_outlined,
          size: 40,
          color: AppColors.textDisabled,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      child: Image.network(
        url!,
        height: 140,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            Container(height: 140, color: AppColors.bgSurface),
      ),
    );
  }
}

/// 俱乐部数据看板(`POST /api/stats/club`,仅主理人)。
///
/// 读不到就在同一个位置说读不到 —— 留空会被读成「这个俱乐部零参与」,
/// 那是另一件事,不能拿加载失败去冒充。
class _ClubStatsSection extends ConsumerWidget {
  const _ClubStatsSection({required this.clubId});

  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(clubStatsProvider(clubId));
    return stats.when(
      loading: () => const CySkeleton(),
      error: (Object error, StackTrace _) => StatusView(
        message: stringsOf(context).clubMainStatsLoadError,
        sub: clubApiErrorMessage(context, error, fallback: stringsOf(context).clubMainStatsRetryError),
        onRetry: () => ref.invalidate(clubStatsProvider(clubId)),
        retryLabel: stringsOf(context).clubMainReload,
      ),
      data: (ClubStats value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _StatCell(value: '${value.topicCount}', label: stringsOf(context).clubMainProjects),
              _StatCell(value: '${value.participants}', label: stringsOf(context).clubMainParticipations),
              _StatCell(value: '${value.completed}', label: stringsOf(context).clubMainCompletions),
              _StatCell(value: value.overallRateText, label: stringsOf(context).clubMainCompletionRate),
            ],
          ),
          const SizedBox(height: CyTokens.space3),
          if (value.topics.isEmpty)
            StatusView(message: stringsOf(context).clubMainNoStats)
          else
            for (final ClubTopicStats topic in value.topics)
              Padding(
                padding: const EdgeInsets.only(bottom: CyTokens.space2),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        topic.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '${topic.completed} / ${topic.participants} · '
                      '${topic.completionRateText}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 「查看客户」入口。右侧那个数走 `/api/club/crm/customers/count`。
/// 读不到就写「暂时读不到」—— 留空会被读成「一个客户都没有」。
class _CustomerCell extends ConsumerWidget {
  const _CustomerCell({required this.clubId});

  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(clubCustomerCountProvider(clubId));
    return CyCell(
      key: const Key('club-manage-customers'),
      title: stringsOf(context).clubMainViewCustomers,
      subtitle: stringsOf(context).clubMainCustomersHint,
      trailing: Text(
        count.when(
          loading: () => '',
          error: (_, _) => stringsOf(context).clubMainUnavailable,
          data: (int total) => total > 0 ? stringsOf(context).clubMainPeopleCount(total) : '',
        ),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
      onTap: () => context.push('/club/$clubId/customers'),
    );
  }
}

/// 「俱乐部分润」入口。钱这一行尤其不能留空:空白会被读成「一分没有」。
class _SettlementCell extends ConsumerWidget {
  const _SettlementCell({required this.clubId});

  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(clubSettlementSummaryProvider(clubId));
    return CyCell(
      key: const Key('club-manage-settlement'),
      title: stringsOf(context).clubMainClubRevenueShare,
      subtitle: stringsOf(context).clubMainRevenueShareHint,
      trailing: Text(
        summary.when(
          loading: () => '',
          error: (_, _) => stringsOf(context).clubMainUnavailable,
          // 金额只透传服务端算好的字符串,前端一分钱都不算;
          // 「金额待核验」时后端不下发合计,这里显示状态话术而非留空/补 0。
          data: (value) =>
              value.amountUnverified ? stringsOf(context).clubMainPendingVerification : value.settledAmountText ?? '',
        ),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
      onTap: () => context.push('/club/$clubId/settlement'),
    );
  }
}

/// 开放设置(小程序 `pages/club/detail` 的稿 M 268:223)。
///
/// 三个开关各写各的端点、各回读各的字段:
/// 界面上那个「已开启/已关闭」要么是**库里的事实**,要么是一条明说没保存成的错误,
/// 不作第三种 —— 所以成功路径不乐观更新,失败路径不留在新位置。
///
/// ⚠️ 自己读 `clubDetailProvider` 拿当前值,而不是让父级传:父级那个 `club`
///   是构建期快照,开关改完不会重建,传进来的值会一直是旧的。
class _OpenSettingsSection extends ConsumerStatefulWidget {
  const _OpenSettingsSection({required this.clubId});

  final int clubId;

  @override
  ConsumerState<_OpenSettingsSection> createState() =>
      _OpenSettingsSectionState();
}

class _OpenSettingsSectionState extends ConsumerState<_OpenSettingsSection> {
  /// 正在保存的开关(同刻只允许一个,与小程序 openSettingSaving 同)。
  String _saving = '';

  /// 哪个开关上次没保存成 + 后端/网络的原话。
  String _errorKey = '';
  String _errorText = '';

  Future<void> _toggle({
    required int clubId,
    required String key,
    required bool next,
    required Club current,
  }) async {
    if (_saving.isNotEmpty) return;
    setState(() {
      _saving = key;
      _errorKey = '';
      _errorText = '';
    });
    try {
      final ClubTopicOpsApi api = ref.read(clubTopicOpsApiProvider);
      final ClubOpenSettingValue saved;
      switch (key) {
        case 'publicVisible':
          saved = await api.setPublicVisible(clubId: clubId, enabled: next);
        case 'memberPost':
          saved = await api.setMemberPost(clubId: clubId, enabled: next);
        default:
          saved = await api.setMerchantCoop(clubId: clubId, enabled: next);
      }
      if (!mounted) return;
      setState(() {
        _saving = '';
        // 回读值落进 provider 的缓存,下一次构建就是服务端的事实。
        ref.invalidate(clubDetailProvider(clubId));
      });
      if (saved.enabled != next) {
        // 服务端回读的与点的不一样(有别的写入者):说清楚,不假装点成了。
        setState(() {
          _errorKey = key;
          _errorText = saved.enabled ? stringsOf(context).clubMainServerEnabled : stringsOf(context).clubMainServerDisabled;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = '';
        _errorKey = key;
        _errorText =
            error is ClubApiException && error.message.trim().isNotEmpty
            ? error.message
            : stringsOf(context).clubMainSwitchSaveError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Club> clubAsync = ref.watch(
      clubDetailProvider(widget.clubId),
    );
    return clubAsync.maybeWhen(
      data: (Club club) {
        if (!club.isOwner) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CySectionTitle(stringsOf(context).clubMainOpenSettings),
            const SizedBox(height: CyTokens.space2),
            _OpenSettingRow(
              rowKey: const Key('club-open-public-visible'),
              title: stringsOf(context).clubMainPublicVisibility,
              sub: stringsOf(context).clubMainPublicVisibilityHint,
              saving: _saving == 'publicVisible',
              enabled: club.publicVisible,
              disabled: _saving.isNotEmpty,
              error: _errorKey == 'publicVisible' ? _errorText : '',
              onRetry: () => _toggle(
                clubId: club.id,
                key: 'publicVisible',
                next: !club.publicVisible,
                current: club,
              ),
              onChanged: (bool next) => _toggle(
                clubId: club.id,
                key: 'publicVisible',
                next: next,
                current: club,
              ),
            ),
            _OpenSettingRow(
              rowKey: const Key('club-open-merchant-coop'),
              title: stringsOf(context).clubMainMerchantAccess,
              sub: stringsOf(context).clubMainMerchantAccessHint,
              saving: _saving == 'merchantCoop',
              enabled: club.merchantUndertakeOpen,
              disabled: _saving.isNotEmpty,
              error: _errorKey == 'merchantCoop' ? _errorText : '',
              onRetry: () => _toggle(
                clubId: club.id,
                key: 'merchantCoop',
                next: !club.merchantUndertakeOpen,
                current: club,
              ),
              onChanged: (bool next) => _toggle(
                clubId: club.id,
                key: 'merchantCoop',
                next: next,
                current: club,
              ),
            ),
            _OpenSettingRow(
              rowKey: const Key('club-open-member-post'),
              title: stringsOf(context).clubMainMemberPosts,
              sub: stringsOf(context).clubMainMemberPostsHint,
              saving: _saving == 'memberPost',
              enabled: club.memberPostAllowed,
              disabled: _saving.isNotEmpty,
              error: _errorKey == 'memberPost' ? _errorText : '',
              onRetry: () => _toggle(
                clubId: club.id,
                key: 'memberPost',
                next: !club.memberPostAllowed,
                current: club,
              ),
              onChanged: (bool next) => _toggle(
                clubId: club.id,
                key: 'memberPost',
                next: next,
                current: club,
              ),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _OpenSettingRow extends StatelessWidget {
  const _OpenSettingRow({
    required this.rowKey,
    required this.title,
    required this.sub,
    required this.saving,
    required this.enabled,
    required this.disabled,
    required this.error,
    required this.onChanged,
    required this.onRetry,
  });

  final Key rowKey;
  final String title;
  final String sub;
  final bool saving;
  final bool enabled;
  final bool disabled;
  final String error;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: rowKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CyCell(
          title: title,
          subtitle: sub,
          trailing: saving
              ? const CupertinoActivityIndicator(radius: 8)
              : CupertinoSwitch(
                  value: enabled,
                  onChanged: disabled ? null : onChanged,
                ),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              0,
              CyTokens.pageX,
              CyTokens.space2,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stringsOf(context).clubMainSwitchFailure(error),
                    style: TextStyle(
                      fontSize: CyTokens.typeCaption,
                      color: CyTokens.statusDanger,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: onRetry,
                  child: Text(
                    stringsOf(context).retry,
                    style: TextStyle(fontSize: CyTokens.typeLabel),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
