import 'club_api_messages.dart';
import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_manage.dart';
import 'club_controller.dart';

/// 解散前待处理:合作保证金 + 未打款结算。
/// 对齐小程序 `pages/club/dissolution-blockers`:
/// - 保证金 retryable → 可点「重试原路退款」;否则只能联系平台逐笔处理;
/// - 结算一律联系平台确认打款(App 无微信客服 open-type,落为提示文案)。
class ClubDissolutionBlockersPage extends ConsumerWidget {
  const ClubDissolutionBlockersPage({super.key, required this.clubId});
  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockers = ref.watch(clubDissolutionBlockersProvider(clubId));
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
              CyPageTitle(stringsOf(context).clubDissolutionPendingTitle),
              Expanded(
                child: blockers.when(
                  loading: () => const CySkeleton(),
                  error: (Object err, StackTrace st) => StatusView(
                    message: stringsOf(context).clubDissolutionLoadFailed,
                    sub: stringsOf(context).clubDissolutionRetryLater,
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () =>
                        ref.invalidate(clubDissolutionBlockersProvider(clubId)),
                  ),
                  data: (DissolutionBlockers b) {
                    if (b.isEmpty) {
                      return StatusView(
                        message: stringsOf(context).clubDissolutionClear,
                        sub: stringsOf(context).clubDissolutionClearBody,
                        icon: CupertinoIcons.checkmark_circle,
                        large: true,
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.all(CyTokens.space4),
                      children: <Widget>[
                        Text(
                          stringsOf(context).clubDissolutionExplanation,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: CyTokens.leadingNormal,
                              ),
                        ),
                        if (b.deposits.isNotEmpty) ...<Widget>[
                          const SizedBox(height: CyTokens.space5),
                          CySectionTitle(stringsOf(context).clubDissolutionDeposits),
                          const SizedBox(height: CyTokens.space2),
                          ...b.deposits.map(
                            (ClubDeposit d) => _DepositCard(
                              deposit: d,
                              onRetry: () =>
                                  _retryRefund(context, ref, d.id, clubId),
                            ),
                          ),
                        ],
                        if (b.settlements.isNotEmpty) ...<Widget>[
                          const SizedBox(height: CyTokens.space5),
                          CySectionTitle(stringsOf(context).clubDissolutionSettlements),
                          const SizedBox(height: CyTokens.space2),
                          ...b.settlements.map(
                            (ClubSettlement s) =>
                                _SettlementCard(settlement: s),
                          ),
                        ],
                      ],
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

  Future<void> _retryRefund(
    BuildContext context,
    WidgetRef ref,
    int inviteId,
    int clubId,
  ) async {
    try {
      await ref.read(clubApiProvider).retryDepositRefund(inviteId);
      if (!context.mounted) return;
      ref.invalidate(clubDissolutionBlockersProvider(clubId));
      CyNativeNotice.show(context, stringsOf(context).clubDissolutionRefundAccepted);
    } catch (e) {
      if (!context.mounted) return;
      CyNativeNotice.show(context, clubApiErrorMessage(context, e), isError: true);
    }
  }
}

class _DepositCard extends StatelessWidget {
  const _DepositCard({required this.deposit, required this.onRetry});
  final ClubDeposit deposit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stringsOf(context).clubDissolutionDeposit(deposit.id),
                    style: textTheme.bodyMedium,
                  ),
                ),
                Flexible(
                  child: Text(
                  _depositStatus(context, deposit.depositStatus),
                  style: textTheme.labelMedium?.copyWith(
                    color: deposit.depositStatus == 5
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              '${deposit.amount == null ? stringsOf(context).clubDissolutionAmountUnknown : deposit.amountText}${deposit.topicId == null ? '' : stringsOf(context).clubDissolutionTopic(deposit.topicId!)}',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            if (deposit.retryable)
              CyNativeButton(
                label: stringsOf(context).clubDissolutionRetryRefund,
                onPressed: onRetry,
                role: CyNativeButtonRole.secondary,
                height: 44,
              )
            else
              _ContactText(text: stringsOf(context).clubDissolutionContactEach),
          ],
        ),
      ),
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({required this.settlement});
  final ClubSettlement settlement;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    stringsOf(context).clubDissolutionSettlement(settlement.id),
                    style: textTheme.bodyMedium,
                  ),
                ),
                Flexible(
                  child: Text(
                  _settlementDirection(context, settlement.direction),
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              '${settlement.amount == null ? stringsOf(context).clubDissolutionAmountUnknown : settlement.amountText}${settlement.topicId == null ? '' : stringsOf(context).clubDissolutionTopic(settlement.topicId!)}',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            _ContactText(text: stringsOf(context).clubDissolutionContactPayment),
          ],
        ),
      ),
    );
  }
}

class _ContactText extends StatelessWidget {
  const _ContactText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        decoration: TextDecoration.underline,
      ),
    );
  }
}

String _depositStatus(BuildContext context, int status) => switch (status) {
  1 => stringsOf(context).clubDissolutionPaying,
  2 => stringsOf(context).clubDissolutionFrozen,
  5 => stringsOf(context).clubDissolutionUnpaid,
  _ => stringsOf(context).clubDissolutionStatusUnknown,
};

String _settlementDirection(BuildContext context, String direction) => switch (direction) {
  'incoming' => stringsOf(context).clubDissolutionIncoming,
  'outgoing' => stringsOf(context).clubDissolutionOutgoing,
  _ => stringsOf(context).clubDissolutionDirectionUnknown,
};
