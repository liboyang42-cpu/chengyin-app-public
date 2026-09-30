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
              const CyPageTitle('解散前待处理'),
              Expanded(
                child: blockers.when(
                  loading: () => const CySkeleton(),
                  error: (Object err, StackTrace st) => StatusView(
                    message: '待处理明细没加载出来',
                    sub: '请稍后重试',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () =>
                        ref.invalidate(clubDissolutionBlockersProvider(clubId)),
                  ),
                  data: (DissolutionBlockers b) {
                    if (b.isEmpty) {
                      return const StatusView(
                        message: '资金阻断已处理完',
                        sub: '返回俱乐部编辑页后，可重新发起解散。',
                        icon: CupertinoIcons.checkmark_circle,
                        large: true,
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.all(CyTokens.space4),
                      children: <Widget>[
                        Text(
                          '这些资金事实即使原合作或主题已隐藏也会保留。请逐笔处理，系统确认终态后才能解散俱乐部。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                height: CyTokens.leadingNormal,
                              ),
                        ),
                        if (b.deposits.isNotEmpty) ...<Widget>[
                          const SizedBox(height: CyTokens.space5),
                          const CySectionTitle('合作保证金'),
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
                          const CySectionTitle('未打款结算'),
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
      CyNativeNotice.show(context, '退款已受理');
    } catch (e) {
      if (!context.mounted) return;
      CyNativeNotice.show(context, e.toString(), isError: true);
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
                    '保证金 #${deposit.id}',
                    style: textTheme.bodyMedium,
                  ),
                ),
                Text(
                  deposit.statusText,
                  style: textTheme.labelMedium?.copyWith(
                    color: deposit.depositStatus == 5
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              '${deposit.amountText}${deposit.topicText}',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            if (deposit.retryable)
              CyNativeButton(
                label: '重试原路退款',
                onPressed: onRetry,
                role: CyNativeButtonRole.secondary,
                height: 44,
              )
            else
              _ContactText(text: '联系平台逐笔处理'),
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
                    '结算 #${settlement.id}',
                    style: textTheme.bodyMedium,
                  ),
                ),
                Text(
                  settlement.directionText,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              '${settlement.amountText}${settlement.topicText}',
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            const _ContactText(text: '联系平台确认打款'),
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
