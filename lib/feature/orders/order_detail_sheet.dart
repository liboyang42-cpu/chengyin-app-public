import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/map/map_launcher.dart';
import '../../core/providers.dart';
import '../../l10n/strings.dart';
import 'registration_order_strings.dart';
import '../../l10n/strings_provider.dart';
import '../auth/auth_controller.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/team_map_api.dart';
import '../../data/models/activity.dart';
import '../../data/models/explore_completion.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'merchant_consent_row.dart';
import 'order_timeline.dart';
import 'completion_display.dart';
import '../team/team_map_strings.dart' show teamApiFailureText;

final orderDetailProvider = FutureProvider.autoDispose
    .family<RegistrationDetail, int>((ref, int orderId) {
      final userId = ref.watch(
        authControllerProvider.select((auth) => auth.user?.id),
      );
      if (userId == null) {
        throw Exception(ref.read(appStringsProvider).loginExpired);
      }
      return ref.watch(activityApiProvider).ticketInfo(orderId);
    });

final orderCompletionProvider = FutureProvider.autoDispose
    .family<ExploreCompletion?, int>((ref, int orderId) async {
      final RegistrationDetail detail = await ref.watch(
        orderDetailProvider(orderId).future,
      );
      if (!detail.isExplorePass || detail.paymentStatus != 2) return null;
      final Map<String, dynamic> data = await ref
          .watch(registrationApiProvider)
          .exploreCompletion(orderId);
      return ExploreCompletion.fromJson(data);
    });

class OrderDetailSheet extends ConsumerWidget {
  const OrderDetailSheet({
    super.key,
    required this.orderId,
    this.scrollController,
    this.onPay,
    this.onCancel,
  });

  final int orderId;
  final ScrollController? scrollController;
  final Future<void> Function()? onPay;
  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RegistrationDetail> async = ref.watch(
      orderDetailProvider(orderId),
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        key: const Key('order-detail-sheet'),
        child: Column(
          children: <Widget>[
            _sheetHeader(context),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                error: (Object error, _) => StatusView(
                  message: stringsOf(context).registrationOrdersCouldNotLoadOrderDetails,
                  sub: localizedOrderError(context, error),
                  large: true,
                  onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
                ),
                data: (RegistrationDetail detail) => _OrderDetailBody(
                  detail: detail,
                  completion: ref.watch(orderCompletionProvider(orderId)),
                  scrollController: scrollController,
                  onPay: onPay,
                  onCancel: onCancel,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHeader(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Text(stringsOf(context).registrationOrdersOrderDetails, style: Theme.of(context).textTheme.titleMedium),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label: stringsOf(context).registrationOrdersCloseOrderDetails,
                button: true,
                child: SizedBox.square(
                  key: const Key('order-detail-close'),
                  dimension: 44,
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: Navigator.of(context).canPop()
                        ? () => CupertinoSheetRoute.popSheet(context)
                        : null,
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderDetailBody extends ConsumerStatefulWidget {
  const _OrderDetailBody({
    required this.detail,
    required this.completion,
    this.scrollController,
    this.onPay,
    this.onCancel,
  });

  final RegistrationDetail detail;
  final AsyncValue<ExploreCompletion?> completion;
  final ScrollController? scrollController;
  final Future<void> Function()? onPay;
  final Future<void> Function()? onCancel;

  @override
  ConsumerState<_OrderDetailBody> createState() => _OrderDetailBodyState();
}

class _OrderDetailBodyState extends ConsumerState<_OrderDetailBody> {
  bool _following = false;
  bool _joining = false;
  bool _followed = false;
  bool _joined = false;
  bool _acting = false;
  bool _teamInviteOnly = false;
  bool _teamCreating = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      ref.invalidate(orderDetailProvider(widget.detail.id));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _openMeetingPoint() async {
    final OrderTicketSnapshot? ticket = widget.detail.omsTicket;
    final MapLaunchResult result = await launchNavigation(
      lat: ticket?.gatherLat,
      lng: ticket?.gatherLng,
      name: ticket?.meetingPoint ?? stringsOf(context).registrationOrdersMeetingPoint,
      address: ticket?.meetingPoint,
      isIOS: defaultTargetPlatform == TargetPlatform.iOS,
    );
    final String message = mapLaunchMessage(result, strings: stringsOf(context));
    if (message.isNotEmpty && mounted) {
      CyNativeNotice.show(
        context,
        message,
        isError: result == MapLaunchResult.noCoordinates,
      );
    }
  }

  Future<void> _follow(ExploreRevisit revisit) async {
    if (_following || revisit.clubLeaderMemberId == null) return;
    setState(() => _following = true);
    try {
      final bool followed = await ref
          .read(registrationApiProvider)
          .toggleFollow(revisit.clubLeaderMemberId!);
      if (mounted) setState(() => _followed = followed);
    } catch (error) {
      if (mounted) _toast(error);
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _join(ExploreRevisit revisit) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      await ref.read(clubApiProvider).join(revisit.clubId);
      if (mounted) setState(() => _joined = true);
    } catch (error) {
      if (mounted) _toast(error);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _toast(Object error) {
    CyNativeNotice.show(context, localizedOrderError(context, error), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final RegistrationDetail d = widget.detail;
    return SingleChildScrollView(
      controller: widget.scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _hero(d),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (d.registrationStatus == 2 && d.verificationStatus != 1)
                  _quickActions(d),
                _productCard(d),
                if (d.ticketPrice != null || d.payableAmount != null)
                  _priceCard(d),
                // 真源顺序:队伍卡/订单进度/商家消息排在支付明细与支付信息之间
                // (scene-member-order-detail/index.wxml)。
                if (_showsTeamCard(d)) _teamCard(d),
                _timelineCard(d),
                if (d.paymentStatus == 2 || d.verificationStatus == 1)
                  CyMerchantConsentRow(
                    cardTitle: stringsOf(context).registrationOrdersMerchantMessages,
                    orderId: d.id,
                    ownerMemberId: d.ownerMemberId,
                  ),
                if (d.paymentStatus == 2) _paymentCard(d),
                if (_hasRegistrant(d)) _registrantCard(d),
                if ((d.verificationTime ?? '').isNotEmpty ||
                    (d.expiresAt ?? '').isNotEmpty)
                  _validityCard(d),
                if (d.entitlements.isNotEmpty) _entitlementsCard(d),
                widget.completion.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (ExploreCompletion? completion) => completion == null
                      ? const SizedBox.shrink()
                      : _completionCard(completion),
                ),
                _refundCard(d),
                _secondaryActions(d),
                if (_showsPrimaryPay(d) && widget.onPay != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space2),
                    child: CyNativeButton(
                      key: const Key('order-detail-primary-pay'),
                      label: _acting ? stringsOf(context).registrationOrdersPaymentInProgress : stringsOf(context).registrationOrdersGoToPayment,
                      onPressed: _acting || widget.onPay == null
                          ? null
                          : () => _act(widget.onPay!),
                      loading: _acting,
                    ),
                  ),
                if (_showsPrimaryTicket(d))
                  Padding(
                    padding: const EdgeInsets.only(top: CyTokens.space2),
                    child: CyNativeButton(
                      key: const Key('order-detail-primary-ticket'),
                      label: stringsOf(context).registrationOrdersViewTickets,
                      onPressed: () => _openTicket(d),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _showsPrimaryPay(RegistrationDetail d) => d.registrationStatus == 1;

  bool _showsPrimaryTicket(RegistrationDetail d) =>
      d.registrationStatus == 2 &&
      d.verificationStatus != 1 &&
      d.refundable != false;

  bool _canCancel(RegistrationDetail d) =>
      d.registrationStatus == 1 || d.refundable == true;

  void _openTicket(RegistrationDetail d) {
    context.push('/tickets?focusId=${d.id}&stype=${d.ownerType == 1 ? 0 : 2}');
  }

  Widget _hero(RegistrationDetail d) => SizedBox(
    height: 220,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CyNetImage(d.imgUrl, fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Colors.transparent, Colors.black87],
            ),
          ),
        ),
        Positioned(
          left: CyTokens.pageX,
          right: CyTokens.pageX,
          bottom: CyTokens.space4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                localOrderModelText(context, d.ticketState.label),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((d.title ?? '').isNotEmpty)
                Text(
                  d.title!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _quickActions(RegistrationDetail d) => _section(
    children: <Widget>[
      _linkRow(
        d.ownerType == 1 ? stringsOf(context).registrationOrdersOpenRoute : stringsOf(context).registrationOrdersContinueExploring,
        () => context.push(
          '/tickets?focusId=${d.id}&stype=${d.ownerType == 1 ? 0 : 2}',
        ),
      ),
      Divider(
        height: 1,
        thickness: 1,
        color: CyPalette.of(context).borderSubtle,
      ),
      _linkRow(
        d.ownerType == 1 ? stringsOf(context).registrationOrdersRouteDetails : stringsOf(context).registrationOrdersBackToSessionDetails,
        () => context.push(
          d.ownerType == 1 ? '/topic/${d.ownerId}' : '/activity/${d.ownerId}',
        ),
      ),
    ],
  );

  Widget _productCard(RegistrationDetail d) {
    final OrderTicketSnapshot? ticket = d.omsTicket;
    return _section(
      title: d.title ?? stringsOf(context).registrationOrdersUnnamedProject,
      subtitle: d.description,
      children: <Widget>[
        _row(stringsOf(context).registrationOrdersOrderType, d.ownerType == 1 ? stringsOf(context).registrationOrdersCityRoute : stringsOf(context).registrationOrdersSession),
        if ((d.registrationNo ?? '').isNotEmpty) _row(stringsOf(context).registrationOrdersOrderNumber, d.registrationNo!),
        if ((d.eventStartDate ?? '').isNotEmpty)
          _row(stringsOf(context).registrationOrdersDate, _date(d.eventStartDate!)),
        if ((ticket?.startTime ?? '').isNotEmpty)
          _row(stringsOf(context).registrationOrdersSession, _timeRange(ticket!.startTime!, ticket.endTime)),
        if ((ticket?.meetingPoint ?? '').isNotEmpty)
          _tapRow(
            stringsOf(context).registrationOrdersMeetingPoint,
            ticket!.hasCoordinates
                ? '${ticket.meetingPoint} ›'
                : stringsOf(context).registrationOrdersCoordinatesMissing(ticket.meetingPoint.toString()),
            _openMeetingPoint,
          ),
      ],
    );
  }

  Widget _priceCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersPriceBreakdown,
    children: <Widget>[
      if (d.ticketPrice != null)
        _row(
          d.ticketName ?? stringsOf(context).registrationOrdersTicket,
          '${_money(d.ticketPrice!)} × ${d.orderNum ?? 1}',
        ),
      if ((d.pointPaymentAmount ?? 0) > 0)
        _row(
          d.pointUsed == null ? stringsOf(context).registrationOrdersPointsDeduction : stringsOf(context).registrationOrdersPointsUsed(d.pointUsed.toString()),
          '-${_money(d.pointPaymentAmount!)}',
        ),
      if ((d.wechatPaymentAmount ?? 0) > 0)
        _row(stringsOf(context).registrationOrdersAmountPaidViaWechat, _money(d.wechatPaymentAmount!)),
      if (d.payableAmount != null)
        _row(stringsOf(context).registrationOrdersTotalPaid, _money(d.payableAmount!), strong: true),
    ],
  );

  bool _showsTeamCard(RegistrationDetail d) =>
      d.ownerType == 2 && d.registrationStatus == 2 && d.teamMode == 2;

  /// 订单进度时间线(scene-member-order-detail buildOrderTimeline)。
  Widget _timelineCard(RegistrationDetail d) {
    final List<OrderTimelineRow> rows = buildOrderTimeline(d);
    return _section(
      title: stringsOf(context).registrationOrdersOrderProgress,
      children: <Widget>[
        for (final OrderTimelineRow row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: CyTokens.space2),
            child: Row(
              children: <Widget>[
                Icon(
                  row.done
                      ? CupertinoIcons.checkmark_circle_fill
                      : CupertinoIcons.circle,
                  size: 18,
                  color: row.done
                      ? CyPalette.of(context).brand
                      : CyPalette.of(context).textTertiary,
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(child: Text(row.key == 'manual_refund'
                    ? row.label
                    : localOrderModelText(context, row.label))),
                if (row.time.isNotEmpty)
                  Text(
                    row.time == '完成后更新'
                        ? localOrderModelText(context, row.time)
                        : row.time,
                    style: CyType.footnote.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 「和队友一起出发」卡 —— 文案逐字对齐 wxml:101-120。
  Widget _teamCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersHeadOutWithYourTeammates,
    subtitle:
        '按主理人设置的人数上限建队。默认公开，队伍会出现在漫游地图「附近的队伍」里等人申请，由你逐个同意；打开「仅邀请」后只有拿到邀请链接的人能进。组队与否不影响活动举行，也不改变订单与退款规则。',
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: CyTokens.space2),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(stringsOf(context).registrationOrdersInvitationOnly)),
            CupertinoSwitch(
              key: const Key('order-detail-team-invite-only'),
              value: _teamInviteOnly,
              onChanged: (bool value) =>
                  setState(() => _teamInviteOnly = value),
            ),
          ],
        ),
      ),
      CyNativeButton(
        key: const Key('order-detail-team-create'),
        label: _teamCreating ? stringsOf(context).registrationOrdersCreating : stringsOf(context).registrationOrdersInviteTeammates,
        role: CyNativeButtonRole.secondary,
        onPressed: _teamCreating ? null : () => _chooseTeamSize(d),
        loading: _teamCreating,
      ),
    ],
  );

  Future<void> _chooseTeamSize(RegistrationDetail d) async {
    final List<int> options = teamMemberOptions(d.teamMaxMembers);
    final int? picked = await showCupertinoModalPopup<int>(
      context: context,
      builder: (BuildContext ctx) => CupertinoActionSheet(
        title: Text(stringsOf(context).registrationOrdersGroupSize),
        actions: <Widget>[
          for (final int size in options)
            CupertinoActionSheetAction(
              key: Key('order-detail-team-size-$size'),
              onPressed: () => Navigator.of(ctx).pop(size),
              child: Text(stringsOf(context).registrationOrdersTeamSize(size)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(stringsOf(context).cancel),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _createTeam(d, picked);
  }

  /// 建队成功即离开订单页进队伍详情(真源 _leave redirect;App 用 push,
  /// 返回键能回到订单 —— 偏差已记报告)。
  Future<void> _createTeam(RegistrationDetail d, int maxMembers) async {
    setState(() => _teamCreating = true);
    try {
      final int teamId = await ref
          .read(activityTeamApiProvider)
          .createActivityTeam(
            ownerId: d.ownerId,
            maxMembers: maxMembers,
            inviteOnly: _teamInviteOnly,
          );
      if (!mounted) return;
      context.push('/team/$teamId');
    } on TeamMapApiException catch (error) {
      if (mounted) {
        CyNativeNotice.show(context, teamApiFailureText(error, stringsOf(context)), isError: true);
      }
    } finally {
      if (mounted) setState(() => _teamCreating = false);
    }
  }

  Widget _paymentCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersPaymentInformation,
    children: <Widget>[
      if ((d.paymentTime ?? '').isNotEmpty)
        _row(stringsOf(context).registrationOrdersPaymentTime, _dateTime(d.paymentTime!)),
      if ((d.paymentTypeLabel ?? '').isNotEmpty)
        _row(stringsOf(context).registrationOrdersPaymentMethod, d.paymentTypeLabel!),
      if ((d.wechatPaymentAmount ?? 0) > 0)
        _row(stringsOf(context).registrationOrdersAmountPaidViaWechat, _money(d.wechatPaymentAmount!)),
      if ((d.pointPaymentAmount ?? 0) > 0)
        _row(stringsOf(context).registrationOrdersAmountPaidWithPoints, _money(d.pointPaymentAmount!)),
      if ((d.transactionId ?? '').isNotEmpty) _row(stringsOf(context).registrationOrdersWechatTransactionId, d.transactionId!),
    ],
  );

  bool _hasRegistrant(RegistrationDetail d) =>
      (d.realName ?? '').isNotEmpty ||
      (d.phone ?? '').isNotEmpty ||
      (d.participateDate ?? '').isNotEmpty;

  Widget _registrantCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersRegistrantDetails,
    children: <Widget>[
      if ((d.realName ?? '').isNotEmpty) _row(stringsOf(context).registrationOrdersName, d.realName!),
      if ((d.phone ?? '').isNotEmpty) _row(stringsOf(context).registrationOrdersPhone, d.phone!),
      if ((d.participateDate ?? '').isNotEmpty)
        _row(stringsOf(context).registrationOrdersRegistrationDate, _date(d.participateDate!)),
    ],
  );

  Widget _validityCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersReceiptAndValidity,
    children: <Widget>[
      if ((d.verificationTime ?? '').isNotEmpty)
        _row(stringsOf(context).registrationOrdersRedemptionTime, _dateTime(d.verificationTime!)),
      if ((d.expiresAt ?? '').isNotEmpty) _row(stringsOf(context).registrationOrdersBenefitsExpire, _dateTime(d.expiresAt!)),
    ],
  );

  Widget _entitlementsCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersBenefitDetails,
    children: <Widget>[
      for (final Entitlement entitlement in d.entitlements)
        _row(
          entitlement.chapterName ?? stringsOf(context).registrationOrdersChapter((entitlement.chapterId ?? '').toString()),
          localizedEntitlementLabel(context, entitlement),
        ),
    ],
  );

  Widget _completionCard(ExploreCompletion c) {
    final ExploreRevisit? revisit = c.revisit;
    final progress = completionProgressLabel(context, c);
    final awardsEmpty = completionAwardsEmptyLabel(context, c);
    return Column(
      children: <Widget>[
        _section(
          title: stringsOf(context).registrationOrdersVisitCollection,
          children: <Widget>[
            if (progress != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(progress),
              ),
            const SizedBox(height: CyTokens.space2),
            Wrap(
              spacing: CyTokens.space2,
              runSpacing: CyTokens.space2,
              children: <Widget>[
                for (final ExploreStamp stamp in c.stamps)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                      vertical: CyTokens.space1,
                    ),
                    decoration: BoxDecoration(
                      color: CupertinoColors.secondarySystemFill.resolveFrom(
                        context,
                      ),
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          stamp.collected
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.circle,
                          size: 16,
                        ),
                        const SizedBox(width: CyTokens.space1),
                        Text(completionStampLabel(context, stamp)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        _section(
          title: stringsOf(context).registrationOrdersCompletionRewards,
          children: <Widget>[
            if (awardsEmpty != null)
              Text(awardsEmpty)
            else
              for (final ExploreAward award in c.awards)
                _row(award.title, award.amountText ?? ''),
          ],
        ),
        if (revisit != null)
          _section(
            title: stringsOf(context).registrationOrdersComeBackNextTime,
            children: <Widget>[
              _row(stringsOf(context).registrationOrdersHostClub, completionClubLabel(context, revisit)),
              Wrap(
                spacing: CyTokens.space2,
                children: <Widget>[
                  if (revisit.canFollow && !_followed)
                    CyNativeButton(
                      label: _following ? stringsOf(context).registrationOrdersFollowing : stringsOf(context).registrationOrdersFollowHostClub,
                      role: CyNativeButtonRole.secondary,
                      onPressed: _following ? null : () => _follow(revisit),
                      loading: _following,
                    ),
                  if (!revisit.joined && !_joined)
                    CyNativeButton(
                      label: _joining ? stringsOf(context).registrationOrdersSubmitting : stringsOf(context).registrationOrdersJoinClub,
                      role: CyNativeButtonRole.secondary,
                      onPressed: _joining ? null : () => _join(revisit),
                      loading: _joining,
                    ),
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space2,
                    ),
                    onPressed: () => context.push('/club/${revisit.clubId}'),
                    child: Text(stringsOf(context).registrationOrdersViewClub),
                  ),
                ],
              ),
              if (revisit.nextEdition != null)
                _linkRow(
                  '${completionNextName(context, revisit.nextEdition!)}${_shortDate(context, revisit.nextEdition!.startDate)}',
                  () => context.push('/topic/${revisit.nextEdition!.topicId}'),
                )
              else
                Text(stringsOf(context).registrationOrdersTheNextSessionWillAppearHereWhenSalesOpen),
            ],
          ),
      ],
    );
  }

  Widget _refundCard(RegistrationDetail d) => _section(
    title: stringsOf(context).registrationOrdersRefundsAndSupport,
    children: <Widget>[
      Text(
        (d.refundDeadlineDisplay ?? '').isNotEmpty
            ? d.refundDeadlineDisplay!
            : stringsOf(context).orderDisclosureRefundDeadline,
      ),
      const SizedBox(height: CyTokens.space1),
      Text(stringsOf(context).orderDisclosureRefundEstimate),
      if ((d.organizerName ?? '').isNotEmpty) ...<Widget>[
        const SizedBox(height: CyTokens.space2),
        Text(stringsOf(context).registrationOrdersOrganizerName(d.organizerName.toString())),
      ],
    ],
  );

  Widget _secondaryActions(RegistrationDetail d) {
    final List<Widget> actions = <Widget>[
      if (_canCancel(d) && widget.onCancel != null)
        Expanded(
          child: CyNativeButton(
            key: const Key('order-detail-cancel'),
            label: _acting ? stringsOf(context).registrationOrdersProcessing : (d.paymentStatus == 2 ? stringsOf(context).registrationOrdersCancelAndRequestRefund : stringsOf(context).registrationOrdersCancelOrder),
            role: CyNativeButtonRole.destructive,
            onPressed: _acting ? null : () => _act(widget.onCancel!),
            loading: _acting,
          ),
        ),
      Expanded(
        child: CyNativeButton(
          key: const Key('order-detail-contact'),
          label: stringsOf(context).registrationOrdersContactSupport,
          role: CyNativeButtonRole.secondary,
          onPressed: () => context.push('/complaint'),
        ),
      ),
      // 真源底部 sec-pair「联系客服 · 复制订单号」;无单号(未建单成功)不给键。
      if ((d.registrationNo ?? '').isNotEmpty)
        Expanded(
          child: CyNativeButton(
            key: const Key('order-detail-copy-no'),
            label: stringsOf(context).registrationOrdersCopyOrderNumber,
            role: CyNativeButtonRole.secondary,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: d.registrationNo!));
              CyNativeNotice.show(context, stringsOf(context).registrationOrdersOrderNumberCopied);
            },
          ),
        ),
      if (!_showsPrimaryTicket(d))
        Expanded(
          child: CyNativeButton(
            key: const Key('order-detail-secondary-ticket'),
            label: stringsOf(context).registrationOrdersViewTickets,
            onPressed: () => _openTicket(d),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space2),
      child: Row(
        children: <Widget>[
          for (int index = 0; index < actions.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: CyTokens.space2),
            actions[index],
          ],
        ],
      ),
    );
  }

  Widget _section({
    String? title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null)
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            if ((subtitle ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: CyTokens.space1),
              Text(subtitle!),
            ],
            if (title != null || (subtitle ?? '').isNotEmpty)
              const SizedBox(height: CyTokens.space3),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.only(bottom: CyTokens.space2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: Text(label)),
        const SizedBox(width: CyTokens.space3),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: strong ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
        ),
      ],
    ),
  );

  Widget _tapRow(String label, String value, VoidCallback onTap) =>
      CupertinoButton(
        minimumSize: const Size.fromHeight(44),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: CyTokens.textPrimary),
          child: _row(label, value),
        ),
      );

  Widget _linkRow(String label, VoidCallback onTap) => CupertinoButton(
    minimumSize: const Size.fromHeight(44),
    padding: const EdgeInsets.symmetric(vertical: CyTokens.space1),
    onPressed: onTap,
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: CyTokens.textPrimary),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          const Icon(CupertinoIcons.chevron_forward, size: 16),
        ],
      ),
    ),
  );
}

String _money(double value) => '¥${value.toStringAsFixed(2)}';

/// 「队伍人数」档位:`utils/team-up.js` memberOptions —— 2 起,
/// 上限 clamp 到主理人 maxMembers(缺省当 4),且不开超过 4 人的档。
List<int> teamMemberOptions(int? maxMembers) {
  final int upper = math.max(2, math.min(4, maxMembers ?? 4));
  return <int>[for (int n = 2; n <= upper; n++) n];
}

String _date(String value) =>
    value.length >= 10 ? value.substring(0, 10) : value;

String _dateTime(String value) =>
    value.length >= 16 ? value.substring(0, 16) : value;

String _timeRange(String start, String? end) {
  final String s = _dateTime(start);
  if (end == null || end.isEmpty) return s;
  return '$s – ${_dateTime(end)}';
}

String _shortDate(BuildContext context, String? value) {
  if (value == null || value.isEmpty) return '';
  return stringsOf(context).registrationOrdersStarts(value.length >= 10 ? value.substring(5, 10) : value);
}
