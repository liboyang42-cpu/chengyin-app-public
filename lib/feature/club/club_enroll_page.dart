import '../../l10n/strings.dart';
import '../../core/network/request_session_scope.dart';
import 'registration_cancellation_display.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club.dart';
import '../../data/models/club_manage.dart';
import '../auth/auth_controller.dart';
import 'club_controller.dart';
import 'club_login_gate.dart';
import 'club_ops_access.dart';

/// 报名名册(主理人/管理员视角):列出俱乐部各团的报名人数,展开看每个票种的
/// 报名者名单;主理人可对未核销的报名清退退款(管理员只读名册)。
///
/// 对齐小程序 `pages/club/enroll`:
/// - 权限:owner 可看可退;管理员(role=1)只读名册;其余无权限;
/// - 成团(自动散团引擎)已于 2026-07-15 下线 —— 本页不展示成团进度/门槛,
///   只报人数与名单;
/// - 退款走 `/api/registration/cancel-by-owner`,后端按主题归属授权。
class ClubEnrollPage extends ConsumerStatefulWidget {
  const ClubEnrollPage({super.key, this.clubId, this.clubName, this.topicId});
  final int? clubId;
  final String? clubName;

  /// E-07(真源 `enroll/index.js:46-49,292`):从主题页「核销台账」带着
  /// 本主题进来 —— 到达即展开那一团并拉名单(不隐藏其他团)。
  final int? topicId;

  @override
  ConsumerState<ClubEnrollPage> createState() => _ClubEnrollPageState();
}

class _ClubEnrollPageState extends ConsumerState<ClubEnrollPage> {
  late final RequestSessionScope _refundScope;
  late final int? _refundOwnerId;
  bool get _ownsRefund => mounted && _refundScope.isCurrent();
  int? _resolvedClubId;
  String _resolvedName = '';
  int? _refundingRegId;
  final Set<int> _submittedRefunds = <int>{};

  @override
  void initState() {
    super.initState();
    _refundOwnerId = ref.read(authControllerProvider).user?.id;
    _refundScope = ref.read(authControllerProvider.notifier).requestScope(
      _refundOwnerId ?? -1,
    );
    _resolvedClubId = widget.clubId;
    _resolvedName = widget.clubName ?? '';
    if (widget.clubId == null) _resolveClub();
  }

  /// 无 clubId 时取我的第一个俱乐部(owned 即 owner)。
  Future<void> _resolveClub() async {
    try {
      final owned = await ref.read(clubMyProvider.future);
      if (!mounted) return;
      if (owned.isNotEmpty) {
        setState(() {
          _resolvedClubId = owned.first.id;
          _resolvedName = owned.first.name;
        });
      }
    } catch (_) {
      // 失败 = 无权限或网络问题,停留无权限态。
    }
  }

  /// 退款:owner 专属,管理员只读。
  Future<void> _refund(
    TeamRegistrant reg,
    String teamName,
    int clubId,
    int topicId,
  ) async {
    if (!_ownsRefund || _refundingRegId != null) return;
    if (_submittedRefunds.contains(reg.id)) {
      CyNativeNotice.show(context, stringsOf(context).clubCancellationSubmitted);
      ref.invalidate(clubTeamDetailProvider((clubId: clubId, topicId: topicId)));
      return;
    }
    final name = (reg.nickname?.isNotEmpty ?? false) ? reg.nickname! : stringsOf(context).clubEnrollPlayerTarget;
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).clubEnrollRefundTitle,
      content: stringsOf(context).clubEnrollRefundBody(name),
      confirmText: stringsOf(context).clubEnrollRefund,
      danger: true,
    );
    if (!confirmed || !_ownsRefund || _refundingRegId != null || _submittedRefunds.contains(reg.id)) return;

    setState(() => _refundingRegId = reg.id);
    try {
      final outcome = await RequestSessionScope.run(_refundScope,
          () => ref.read(clubApiProvider).cancelRegistrationByOwner(reg.id));
      if (!_ownsRefund) return;
      _submittedRefunds.add(reg.id);
      CyNativeNotice.show(context, registrationCancellationNotice(context, outcome));
      // 重新拉该团报名详情(清退后名单/人数变化)。
      ref.invalidate(
        clubTeamDetailProvider((clubId: clubId, topicId: topicId)),
      );
    } catch (e) {
      if (!_ownsRefund) return;
      if (e is DioException && (e.response == null || (e.response?.statusCode ?? 0) >= 500)) {
        _submittedRefunds.add(reg.id);
        ref.invalidate(clubTeamDetailProvider((clubId: clubId, topicId: topicId)));
        CyNativeNotice.show(context, stringsOf(context).clubCheckinRefundUnknownBody, isError: true);
        return;
      }
      CyNativeNotice.show(context, registrationCancellationError(context, e), isError: true);
    } finally {
      if (_ownsRefund) setState(() => _refundingRegId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    if (ref.read(authControllerProvider).user?.id != _refundOwnerId ||
        (_refundOwnerId != null && !_refundScope.isCurrent())) {
      return CupertinoPageScaffold(child: StatusView(message: stringsOf(context).loginExpired));
    }
    final int? clubId = _resolvedClubId;
    if (clubId == null) {
      // 未传 clubId 且取不到我拥有的俱乐部:提示无权限。
      return CupertinoPageScaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        navigationBar: const CupertinoNavigationBar(),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CyPageTitle(stringsOf(context).clubEnrollTitle),
                Expanded(
                  child: StatusView(
                    message: stringsOf(context).clubEnrollDenied,
                    sub: stringsOf(context).clubEnrollDeniedBody,
                    icon: CupertinoIcons.lock,
                    large: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _EnrollBody(
      clubId: clubId,
      clubName: _resolvedName,
      focusTopicId: widget.topicId,
      refundingRegId: _refundingRegId,
      onRefund: _refund,
    );
  }
}

class _EnrollBody extends ConsumerWidget {
  const _EnrollBody({
    required this.clubId,
    required this.clubName,
    required this.focusTopicId,
    required this.refundingRegId,
    required this.onRefund,
  });

  final int clubId;
  final String clubName;
  final int? focusTopicId;
  final int? refundingRegId;
  final void Function(
    TeamRegistrant reg,
    String teamName,
    int clubId,
    int topicId,
  )
  onRefund;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(clubDetailProvider(clubId));
    final teams = ref.watch(clubTopicsProvider(clubId));
    // 权限:owner 可看可退;管理员(role=1 且 memberId 是自己)只读名册。
    final user = ref.watch(authControllerProvider).user;
    final members = ref.watch(clubMembersProvider(clubId));

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyPageTitle(stringsOf(context).clubEnrollTitle),
              Expanded(
                child: detail.when(
                  loading: () => CySkeleton(label: stringsOf(context).clubEnrollCheckingAccess),
                  error: (Object err, StackTrace st) {
                    // 401 排在网络/业务两态之前(#258 同型):游客从没登录过,
                    // 「暂时无法确认查看权限」+「重新检查」是死路。
                    if (clubLoginRequired(err)) {
                      return ClubLoginGate(
                        message: stringsOf(context).clubEnrollLogin,
                        onSignedIn: () =>
                            ref.invalidate(clubDetailProvider(clubId)),
                      );
                    }
                    // 小程序把「确认查看权限」这一层失败分网络/业务两态,
                    // 两态的标题与重试键文案都不一样。
                    final bool network =
                        clubOpsFailureState(err) ==
                        ClubOpsLoadState.networkError;
                    return StatusView(
                      message: network ? stringsOf(context).clubEnrollNetworkFailed : stringsOf(context).clubEnrollAccessUnknown,
                      sub: clubOpsErrorMessage(err, stringsOf(context).clubEnrollDataUnavailable),
                      icon: CupertinoIcons.exclamationmark_triangle,
                      retryLabel: stringsOf(context).clubEnrollRecheck,
                      onRetry: () => ref.invalidate(clubDetailProvider(clubId)),
                    );
                  },
                  data: (Club club) {
                    final isAdmin =
                        members.value?.any(
                          (ClubMember m) =>
                              m.role == 1 &&
                              user != null &&
                              m.memberId == user.id,
                        ) ??
                        false;
                    final hasPermission = club.isOwner || isAdmin;
                    if (!hasPermission) {
                      return StatusView(
                        message: stringsOf(context).clubEnrollDenied,
                        sub: stringsOf(context).clubEnrollDeniedBody,
                        icon: CupertinoIcons.lock,
                        large: true,
                      );
                    }
                    return teams.when(
                      loading: () => CySkeleton(label: stringsOf(context).clubEnrollLoading),
                      error: (Object err, StackTrace st) {
                        // 名册层同口径:401(token 中途过期)不冒充「加载失败」。
                        if (clubLoginRequired(err)) {
                          return ClubLoginGate(
                            message: stringsOf(context).clubEnrollLogin,
                            onSignedIn: () =>
                                ref.invalidate(clubTopicsProvider(clubId)),
                          );
                        }
                        final bool network =
                            clubOpsFailureState(err) ==
                            ClubOpsLoadState.networkError;
                        return StatusView(
                          message: network ? stringsOf(context).clubEnrollNetworkFailed : stringsOf(context).clubEnrollLoadFailed,
                          sub: network ? stringsOf(context).clubEnrollNetworkRetry : stringsOf(context).clubEnrollDataUnavailable,
                          icon: CupertinoIcons.exclamationmark_triangle,
                          retryLabel: stringsOf(context).clubEnrollReload,
                          onRetry: () =>
                              ref.invalidate(clubTopicsProvider(clubId)),
                        );
                      },
                      data: (List<ClubTopic> list) {
                        if (list.isEmpty) {
                          return StatusView(
                            message: stringsOf(context).clubEnrollNoGroups,
                            sub: stringsOf(context).clubEnrollNoGroupsBody,
                            icon: CupertinoIcons.calendar,
                            large: true,
                          );
                        }
                        final canRefund = club.isOwner;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                CyTokens.pageX,
                                0,
                                CyTokens.pageX,
                                CyTokens.space2,
                              ),
                              child: Text(
                                stringsOf(context).clubEnrollGroupCount(clubName.isEmpty ? stringsOf(context).clubEnrollMyClub : clubName, list.length),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  CyTokens.pageX,
                                  CyTokens.space1,
                                  CyTokens.pageX,
                                  CyTokens.space4,
                                ),
                                itemCount: list.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: CyTokens.space3),
                                itemBuilder: (context, i) => _TeamCard(
                                  team: list[i],
                                  clubId: clubId,
                                  // E-07:带 topicId 进来时那一团到达即展开。
                                  initiallyOpen:
                                      focusTopicId != null &&
                                      list[i].id == focusTopicId,
                                  canRefund: canRefund,
                                  canShowGroupCode: hasPermission,
                                  refundingRegId: refundingRegId,
                                  onRefund: onRefund,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: CyTokens.space4,
                                left: CyTokens.pageX,
                                right: CyTokens.pageX,
                              ),
                              child: Text(
                                stringsOf(context).clubEnrollEscrow,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: CyTokens.textTertiary),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamCard extends ConsumerStatefulWidget {
  const _TeamCard({
    required this.team,
    required this.clubId,
    required this.initiallyOpen,
    required this.canRefund,
    required this.canShowGroupCode,
    required this.refundingRegId,
    required this.onRefund,
  });

  final ClubTopic team;
  final int clubId;
  final bool initiallyOpen;
  final bool canRefund;
  final bool canShowGroupCode;
  final int? refundingRegId;
  final void Function(
    TeamRegistrant reg,
    String teamName,
    int clubId,
    int topicId,
  )
  onRefund;

  @override
  ConsumerState<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends ConsumerState<_TeamCard> {
  late bool _open = widget.initiallyOpen;

  void _toggle() {
    setState(() => _open = !_open);
    // 展开时才订阅 provider,折叠时 autoDispose 释放 —— 不展开的团不发请求。
    if (_open) {
      ref.invalidate(
        clubTeamDetailProvider((
          clubId: widget.clubId,
          topicId: widget.team.id,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final AsyncValue<TeamDetail>? detailState = _open
        ? ref.watch(
            clubTeamDetailProvider((
              clubId: widget.clubId,
              topicId: widget.team.id,
            )),
          )
        : null;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 团头(整行可点,首次展开拉取报名明细)。
          CupertinoButton(
            onPressed: _toggle,
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            child: Padding(
              padding: const EdgeInsets.all(CyTokens.space3),
              child: Row(
                children: <Widget>[
                  _Cover(url: widget.team.imgUrl),
                  const SizedBox(width: CyTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.team.name.isEmpty ? stringsOf(context).clubEnrollUnnamedGroup : widget.team.name,
                          style: textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          stringsOf(context).clubEnrollDateCount(widget.team.dateText.isEmpty ? stringsOf(context).clubEnrollTimePending : widget.team.dateText, widget.team.signupCount),
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (widget.canShowGroupCode) ...<Widget>[
                          const SizedBox(height: CyTokens.space1),
                          Builder(
                            builder: (BuildContext context) {
                              void showGroupCode() => context.push(
                                '/club/group-code?topicId=${widget.team.id}&topicName=${Uri.encodeComponent(widget.team.name)}',
                              );
                              return Semantics(
                                key: Key(
                                  'club-team-group-code-${widget.team.id}',
                                ),
                                container: true,
                                excludeSemantics: true,
                                button: true,
                                label: stringsOf(context).clubEnrollShowCode,
                                onTap: showGroupCode,
                                child: CupertinoButton(
                                  onPressed: showGroupCode,
                                  minimumSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: CyTokens.space2_5,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CyTokens.bgSubtle,
                                      borderRadius: BorderRadius.circular(
                                        CyTokens.radiusPill,
                                      ),
                                    ),
                                    child: Text(
                                      stringsOf(context).clubEnrollShowCode,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: CyTokens.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: reduceMotion ? Duration.zero : CyMotion.fast,
                    child: const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: CyTokens.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (detailState != null)
            _TeamDetailSection(
              detail: detailState,
              clubId: widget.clubId,
              canRefund: widget.canRefund,
              refundingRegId: widget.refundingRegId,
              onRefund: (TeamRegistrant reg, String teamName) =>
                  widget.onRefund(reg, teamName, widget.clubId, widget.team.id),
              onRetry: () => ref.invalidate(
                clubTeamDetailProvider((
                  clubId: widget.clubId,
                  topicId: widget.team.id,
                )),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamDetailSection extends StatelessWidget {
  const _TeamDetailSection({
    required this.detail,
    required this.clubId,
    required this.canRefund,
    required this.refundingRegId,
    required this.onRefund,
    required this.onRetry,
  });

  final AsyncValue<TeamDetail> detail;
  final int clubId;
  final bool canRefund;
  final int? refundingRegId;
  final void Function(TeamRegistrant reg, String teamName) onRefund;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space3,
        0,
        CyTokens.space3,
        CyTokens.space3,
      ),
      child: detail.when(
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: stringsOf(context).clubEnrollDetailsLoading,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CupertinoActivityIndicator(color: CyTokens.textTertiary),
              ),
            ),
          ),
        ),
        error: (Object err, StackTrace st) => Padding(
          padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  stringsOf(context).clubEnrollDetailsFailed,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              CupertinoButton(
                onPressed: onRetry,
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                minimumSize: const Size(44, 44),
                child: Text(stringsOf(context).clubEnrollRetry),
              ),
            ],
          ),
        ),
        data: (TeamDetail d) {
          if (d.tickets.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
              child: Text(
                stringsOf(context).clubEnrollNoTickets,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            );
          }
          final deadline = d.signupDeadlineText;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${stringsOf(context).clubEnrollPaymentCounts(_teamStatusLabel(context, d.teamStatusText), d.paidCount, d.refundableCount)}${deadline.isNotEmpty ? stringsOf(context).clubEnrollDeadline(deadline) : ''}',
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space3),
              for (final TeamTicket t in d.tickets)
                _TicketBlock(
                  ticket: t,
                  clubId: clubId,
                  canRefund: canRefund,
                  refundingRegId: refundingRegId,
                  onRefund: onRefund,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TicketBlock extends StatelessWidget {
  const _TicketBlock({
    required this.ticket,
    required this.clubId,
    required this.canRefund,
    required this.refundingRegId,
    required this.onRefund,
  });

  final TeamTicket ticket;
  final int clubId;
  final bool canRefund;
  final int? refundingRegId;
  final void Function(TeamRegistrant reg, String teamName) onRefund;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            ticket.name,
            style: textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            '${stringsOf(context).clubEnrollSignups(ticket.signups)}${ticket.totalInventory > 0 ? stringsOf(context).clubEnrollCapacity(ticket.totalInventory) : ''}',
            style: textTheme.labelSmall?.copyWith(color: CyTokens.textTertiary),
          ),
          const SizedBox(height: CyTokens.space2),
          if (ticket.regs.isEmpty)
            Text(
              stringsOf(context).clubEnrollEmpty,
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            ...ticket.regs.map(
              (TeamRegistrant r) => _RegistrantRow(
                reg: r,
                clubId: clubId,
                canRefund: canRefund && r.refundable,
                busy: refundingRegId == r.id,
                onRefund: () => onRefund(r, ticket.name),
              ),
            ),
        ],
      ),
    );
  }
}

class _RegistrantRow extends StatelessWidget {
  const _RegistrantRow({
    required this.reg,
    required this.clubId,
    required this.canRefund,
    required this.busy,
    required this.onRefund,
  });

  final TeamRegistrant reg;
  final int clubId;
  final bool canRefund;
  final bool busy;
  final VoidCallback onRefund;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
      child: Row(
        children: <Widget>[
          // 小程序 `enroll/index.wxml:66` 头像可点 → 玩家公开主页。
          // 拿不到 memberId 就不给点,跳 /user/0 会进一个空主页。
          if (reg.memberId > 0)
            CupertinoButton(
              key: Key('club-enroll-user-${reg.id}'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              onPressed: () => context.push('/user/${reg.memberId}'),
              child: CyAvatar(url: reg.avatar, fallback: stringsOf(context).clubEnrollAvatarFallback, size: 28),
            )
          else
            CyAvatar(url: reg.avatar, fallback: stringsOf(context).clubEnrollAvatarFallback, size: 28),
          const SizedBox(width: CyTokens.space2_5),
          Expanded(
            child: Text(
              (reg.nickname?.isNotEmpty ?? false) ? reg.nickname! : stringsOf(context).clubEnrollPlayer,
              style: textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 名册一行只放「已核销/待核销」四个字;票种、实付、门店、操作人这些
          // 只有凭证页装得下 —— 点这一格进去看这条报名单的完整核销事实。
          CupertinoButton(
            key: Key('club-enroll-checkin-${reg.id}'),
            onPressed: () => context.push('/club/$clubId/checkin/${reg.id}'),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
            minimumSize: const Size(44, 44),
            child: Text(
              reg.verificationStatus == 1 ? stringsOf(context).clubEnrollVerified : stringsOf(context).clubEnrollPending,
              style: textTheme.labelSmall,
            ),
          ),
          if (canRefund)
            CupertinoButton(
              onPressed: busy ? null : onRefund,
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              minimumSize: const Size(44, 44),
              color: null,
              child: busy
                  ? const CupertinoActivityIndicator(radius: 7)
                  : Text(stringsOf(context).clubEnrollRefund, style: const TextStyle(color: AppColors.danger)),
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
    final fallback = Container(
      width: 56,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: const Icon(
        Icons.route_outlined,
        size: 20,
        color: AppColors.textDisabled,
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      child: Image.network(
        url!,
        width: 56,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

String _teamStatusLabel(BuildContext context, String status) => switch (status) {
  '已成团' => stringsOf(context).clubEnrollFormed,
  '已散团' => stringsOf(context).clubEnrollDisbanded,
  '募集中' => stringsOf(context).clubEnrollRecruiting,
  _ => status,
};
