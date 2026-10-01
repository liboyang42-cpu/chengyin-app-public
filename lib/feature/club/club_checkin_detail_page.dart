import '../../l10n/strings.dart';
import '../../core/network/request_session_scope.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_crm.dart';
import 'club_access_gate.dart';
import 'club_controller.dart';
import '../auth/auth_controller.dart';
import 'registration_cancellation_display.dart';
import '../../data/models/registration_cancellation_outcome.dart';

/// K3 核销详情 · 俱乐部端。真源 `pages/club/checkin-detail/index`。
///
/// 为什么俱乐部要自己一页:商家侧那页按商家身份取数,俱乐部进不去也不该进。
/// 这页按 clubId + registrationId 取,归属判定在服务端 SQL 的 where 里。
///
/// ★ 手机号服务端已按岗位权限裁好再下发:有权限是掩码号码,没权限是替代说明。
///   前端原样显示 —— 空会被读成「这客户没留电话」。
class ClubCheckinDetailPage extends ConsumerStatefulWidget {
  const ClubCheckinDetailPage({
    super.key,
    required this.clubId,
    required this.registrationId,
    this.confirmPresenter,
  });

  final int clubId;
  final int registrationId;

  /// 仅供测试注入确认弹窗结果(与 `ClubMemberActions` 同一手法)。
  final CyNativeConfirmPresenter? confirmPresenter;

  @override
  ConsumerState<ClubCheckinDetailPage> createState() =>
      _ClubCheckinDetailPageState();
}

class _ClubCheckinDetailPageState extends ConsumerState<ClubCheckinDetailPage> {
  late final RequestSessionScope _refundScope;
  late final int? _refundOwnerId;
  bool get _ownsRefund => mounted && _refundScope.isCurrent();
  bool _refunding = false;
  String _refundErrorText = '';

  /// 「回执未知」必须与「失败」分开:失败可以直接重试,未知不行 ——
  /// 重试就是重复退款。未知一律去回读这单的状态,CRM 的 REFUNDED 仅由 paymentStatus 推导，不能证明退款到账。
  bool _refundErrorUnknown = false;

  /// A successful HTTP response still requires its detailed cash/points outcome.
  RegistrationCancellationOutcome? _submittedOutcome;

  @override
  void initState() {
    super.initState();
    _refundOwnerId = ref.read(authControllerProvider).user?.id;
    _refundScope = ref.read(authControllerProvider.notifier).requestScope(
      _refundOwnerId ?? -1,
    );
  }

  ({int clubId, int registrationId}) get _key =>
      (clubId: widget.clubId, registrationId: widget.registrationId);

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/club/${widget.clubId}/enroll');
  }

  void _reload() {
    if (_ownsRefund) ref.invalidate(clubCheckinDetailProvider(_key));
  }

  Future<void> _refund(ClubCheckinDetail detail) async {
    // ⚠️ 未知态也要挡在这里:按钮只是灰一下,再点一次就是重复退款。
    if (!_ownsRefund || !detail.canRefund || _refunding || _refundErrorUnknown || _submittedOutcome != null) return;
    final bool confirmed = await cyConfirm(
      context,
      title: stringsOf(context).clubCheckinRefundTitle,
      content: stringsOf(context).clubCheckinRefundBody(detail.displayName),
      confirmText: stringsOf(context).clubCheckinRefund,
      danger: true,
      nativePresenter: widget.confirmPresenter,
    );
    if (!confirmed || !_ownsRefund || _refunding || _refundErrorUnknown || _submittedOutcome != null) return;
    setState(() {
      _refunding = true;
      _refundErrorText = '';
      _refundErrorUnknown = false;
    });
    try {
      final outcome = await RequestSessionScope.run(_refundScope, () => ref
          .read(clubApiProvider)
          .cancelRegistrationByOwner(widget.registrationId));
      if (!_ownsRefund) return;
      setState(() => _refunding = false);
      _submittedOutcome = outcome;
      CyNativeNotice.show(context, registrationCancellationNotice(context, outcome));
      _reload();
    } on Object catch (error) {
      if (!_ownsRefund) return;
      if (_isUnknownOutcome(error)) {
        _markRefundUnknown();
        return;
      }
      setState(() {
        _refunding = false;
        _refundErrorUnknown = false;
        _refundErrorText = registrationCancellationError(context, error);
      });
    }
  }

  /// 网络断在半路 / 5xx:请求可能已经到了服务端,一律按未知处理去回读。
  void _markRefundUnknown() {

    setState(() {
      _refunding = false;
      _refundErrorUnknown = true;
      _refundErrorText = stringsOf(context).clubCheckinRefundUnknownBody;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    if (ref.read(authControllerProvider).user?.id != _refundOwnerId ||
        (_refundOwnerId != null && !_refundScope.isCurrent())) {
      return _scaffold(StatusView(message: stringsOf(context).loginExpired));
    }
    if (widget.clubId <= 0 || widget.registrationId <= 0) {
      return _scaffold(
        StatusView(
          message: stringsOf(context).clubCheckinMissingTitle,
          sub: stringsOf(context).clubCheckinMissingBody,
          icon: CupertinoIcons.doc_text_search,
          large: true,
          onRetry: _goBack,
          retryLabel: stringsOf(context).clubCheckinBack,
        ),
      );
    }
    final detail = ref.watch(clubCheckinDetailProvider(_key));
    return _scaffold(
      detail.when(
        loading: () => const CySkeleton(),
        error: (Object error, StackTrace _) {
          final failure = classifyClubCrmFailure(error);
          if (failure.auth) {
            return StatusView(
              message: stringsOf(context).clubCheckinDenied,
              sub: friendlyOrBackendMessage(
                error,
                fallback: stringsOf(context).clubCheckinDeniedBody,
              ),
              icon: CupertinoIcons.lock,
              large: true,
              onRetry: _goBack,
              retryLabel: stringsOf(context).clubCheckinBack,
            );
          }
          return StatusView(
            message: stringsOf(context).clubCheckinLoadFailed,
            sub: failure.network
                ? stringsOf(context).clubCheckinNetworkRetry
                : friendlyOrBackendMessage(error, fallback: stringsOf(context).clubCheckinRetryLater),
            icon: CupertinoIcons.cloud,
            large: true,
            onRetry: _reload,
            retryLabel: stringsOf(context).clubCheckinReload,
          );
        },
        data: (ClubCheckinDetail value) {

          return _body(context, value);
        },
      ),
    );
  }

  Widget _scaffold(Widget child) {
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
              CyPageTitle(stringsOf(context).clubCheckinTitle),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ClubCheckinDetail detail) {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.only(
        left: CyTokens.pageX,
        right: CyTokens.pageX,
        bottom: CyTokens.space6,
      ),
      children: <Widget>[
        _head(context, palette, detail),
        if (_submittedOutcome != null)
          Text(registrationCancellationNotice(context, _submittedOutcome!)),
        const SizedBox(height: CyTokens.space4),
        _voucherCard(context, palette, detail),
        if (detail.canRefund) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          if (_refundErrorUnknown)
            _inlineError(
              palette,
              title: stringsOf(context).clubCheckinRefundUnknown,
              sub: _refundErrorText,
              actionLabel: stringsOf(context).clubCheckinQueryAgain,
              onAction: _reload,
            )
          else if (_refundErrorText.isNotEmpty)
            _inlineError(
              palette,
              title: stringsOf(context).clubCheckinRefundFailed,
              sub: _refundErrorText,
              actionLabel: stringsOf(context).clubCheckinRetry,
              onAction: () => _refund(detail),
            ),
          const SizedBox(height: CyTokens.space3),
          CyNativeButton(
            key: const Key('club-checkin-refund'),
            label: _refunding ? stringsOf(context).clubCheckinRefunding : stringsOf(context).clubCheckinRefundTitle,
            loading: _refunding,
            role: CyNativeButtonRole.destructive,
            onPressed: _refunding || _refundErrorUnknown || _submittedOutcome != null
                ? null
                : () => _refund(detail),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            stringsOf(context).clubCheckinRefundPolicy,
            style: CyType.caption1.copyWith(color: palette.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _head(
    BuildContext context,
    CyPalette palette,
    ClubCheckinDetail detail,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CyAvatar(url: detail.avatar, fallback: detail.displayName, size: 48),
          const SizedBox(width: CyTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  detail.displayName,
                  style: CyType.headline.copyWith(color: palette.textPrimary),
                ),
                Text(
                  detail.sessionTimeText,
                  style: CyType.footnote.copyWith(color: palette.textSecondary),
                ),
                if (detail.phoneText.isNotEmpty)
                  Text(
                    detail.phoneText,
                    style: CyType.footnote.copyWith(
                      color: detail.phoneVisible
                          ? palette.textSecondary
                          : palette.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                detail.statusText,
                style: TextStyle(
                  color: _statusColor(palette, detail.statusCode),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail.statusTimeText.isNotEmpty)
                Text(
                  detail.statusTimeText,
                  style: CyType.caption1.copyWith(color: palette.textTertiary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _voucherCard(
    BuildContext context,
    CyPalette palette,
    ClubCheckinDetail detail,
  ) {
    final bool refunded = detail.statusCode == 'REFUNDED';
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CyNetImage(
                detail.topicCover,
                width: 56,
                height: 56,
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
              const SizedBox(width: CyTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      detail.sessionTimeText,
                      style: CyType.caption1.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    Text(
                      detail.topicName.isEmpty ? stringsOf(context).clubCheckinUnnamedTopic : detail.topicName,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (detail.orderNo.isNotEmpty)
                      Text(
                        stringsOf(context).clubCheckinOrderNumber(detail.orderNo),
                        style: CyType.caption1.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _divider(palette),
          _kv(palette, stringsOf(context).clubCheckinTicket, detail.ticketText),
          _kv(palette, stringsOf(context).clubCheckinOrderTime, detail.orderTimeText),
          _kv(
            palette,
            stringsOf(context).clubCheckinPaid,
            detail.paidAmountText,
            // 已退款把实付压成中性:这笔钱已经不在账上了。
            valueColor: refunded ? palette.textTertiary : palette.textPrimary,
            bold: true,
          ),
          _kv(
            palette,
            stringsOf(context).clubCheckinVerifiedTime,
            detail.verifyTimeText,
            valueColor: detail.statusCode == 'VERIFIED'
                ? CyTokens.statusSuccess
                : palette.textPrimary,
          ),
          _kv(palette, stringsOf(context).clubCheckinStore, detail.storeName),
          _kv(palette, stringsOf(context).clubCheckinOperator, detail.operatorName),
          _divider(palette),
          _rail(palette, detail),
          if (refunded) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              stringsOf(context).clubCheckinRefundedRail,
              style: CyType.caption1.copyWith(color: palette.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  String _railLabel(ClubCheckinRailStep step) => switch (step.key) {
    'signed' => stringsOf(context).clubCheckinRailSigned,
    'contacted' => stringsOf(context).clubCheckinRailContacted,
    'verified' => stringsOf(context).clubCheckinRailVerified,
    'reviewed' => stringsOf(context).clubCheckinRailReviewed,
    _ => step.label,
  };

  Widget _rail(CyPalette palette, ClubCheckinDetail detail) {
    return Row(
      children: <Widget>[
        for (final ClubCheckinRailStep step in detail.buildRail())
          Expanded(
            child: Column(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _toneColor(palette, step.tone),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: CyTokens.space1),
                Text(
                  _railLabel(step),
                  style: CyType.caption1.copyWith(
                    color: _toneColor(palette, step.tone),
                    fontWeight: step.current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _inlineError(
    CyPalette palette, {
    required String title,
    required String sub,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Container(
      key: const Key('club-checkin-refund-error'),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyTokens.statusDanger),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: CyTokens.statusDanger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sub,
                  style: CyType.caption1.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _divider(CyPalette palette) => Padding(
    padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
    child: Container(height: 1, color: palette.cardBorder),
  );

  Widget _kv(
    CyPalette palette,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1),
      child: Row(
        children: <Widget>[
          Text(label, style: TextStyle(color: palette.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: valueColor ?? palette.textPrimary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _toneColor(CyPalette palette, String tone) => switch (tone) {
    'success' => CyTokens.statusSuccess,
    'warning' => CyTokens.statusWarning,
    'danger' => CyTokens.statusDanger,
    _ => palette.textTertiary,
  };

  Color _statusColor(CyPalette palette, String statusCode) =>
      switch (statusCode) {
        'VERIFIED' || 'REVIEWED' => CyTokens.statusSuccess,
        'REFUNDED' => palette.textTertiary,
        _ => CyTokens.statusWarning,
      };
}

/// 「回执未知 ≠ 失败」:没连上 / 超时 / 5xx 时服务端可能已经受理了这笔退款。
bool _isUnknownOutcome(Object error) {
  if (error is! DioException) return false;
  final int? status = error.response?.statusCode;
  if (error.response == null) return true;
  return status != null && status >= 500;
}
