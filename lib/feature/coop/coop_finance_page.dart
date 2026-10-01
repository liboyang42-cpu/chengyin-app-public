import '../../l10n/strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_finance.dart';
import '../merchant/merchant_money.dart';
import '../withdrawal/withdrawal_contact_dialog.dart';
import 'coop_guard.dart';

final coopFinanceProvider = FutureProvider.autoDispose<List<CoopFinanceRow>>((
  ref,
) {
  return ref.watch(coopApiProvider).finance();
});

/// 提现行三态(真源 `scene-merchant-profit/index.js:80-149`):
/// 入账口径只认服务端 `myIncomeArrived` —— **已结算≠已入账**,
/// 有结算了却读不到金额/入账事实就是 unknown,禁把未知说成 0。
enum _WithdrawState { positive, zero, unknown }

class _WithdrawFacts {
  const _WithdrawFacts(this.state);
  final _WithdrawState state;
  bool get canWithdraw => state == _WithdrawState.positive;

  /// 按钮下面那行原因(真源 wxml:15-16 的 withdraw-reason)。
  String? reason(BuildContext context) => switch (state) {
    _WithdrawState.unknown => stringsOf(context).coopFinanceUiUnknownCredited,
    _WithdrawState.zero => stringsOf(context).coopFinanceUiNoCreditedShare,
    _WithdrawState.positive => null,
  };
}

_WithdrawFacts _withdrawFacts(List<CoopFinanceRow> rows) {
  double total = 0;
  for (final CoopFinanceRow row in rows) {
    final double? income = double.tryParse(cny(row.myIncome) ?? '');
    if (row.settled &&
        (income == null || (income > 0 && !row.myIncomeArrived))) {
      return const _WithdrawFacts(_WithdrawState.unknown);
    }
    if (row.settled && income != null && (income == 0 || row.myIncomeArrived)) {
      total += income;
    }
  }
  return _WithdrawFacts(
    total > 0 ? _WithdrawState.positive : _WithdrawState.zero,
  );
}

/// 合作结算(发起人视角)。对齐小程序 `pages/coop/settlement-detail`。
///
/// ★ 只读页,**前端一个金额都不算** —— 所有数额由服务端下发。
class CoopFinancePage extends ConsumerWidget {
  const CoopFinancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title = stringsOf(context).coopFinanceUiTitle;
    final String needLogin = stringsOf(context).coopFinanceUiLogin;
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(coopFinanceProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => isCoopUnauthorized(e)
                ? coopLoginView(
                    context,
                    ref,
                    navTitle: title,
                    message: needLogin,
                    refetch: () => ref.invalidate(coopFinanceProvider),
                  )
                : StatusView(
                    // 原文取自小程序同一块 `components/cy/scene-merchant-profit`
                    // 的 cy-error title(它挂在小程序 pages/coop/finance 上)。
                    // 原来这里写的是「合作财务没能加载出来」——
                    // 小程序里**根本没有「合作财务」这个词**(只在开发截图脚本里),
                    // 同一页导航叫「合作结算」、空态叫「还没有合作结算」。
                    message: stringsOf(context).coopFinanceUiFailed,
                    sub: coopErrorSub(e, context: context),
                    large: true,
                    onRetry: () => ref.invalidate(coopFinanceProvider),
                  ),
            data: (List<CoopFinanceRow> rows) {
              // 真源同一层结构:提现行(stat-card 之下、各主题结算之上)不随
              // 列表空态消失 —— 没有主题时也照说「暂无已入账分润」。
              final _WithdrawFacts facts = _withdrawFacts(rows);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _WithdrawEntry(facts: facts),
                  Expanded(
                    child: rows.isEmpty
                        ? StatusView(
                            message: stringsOf(context).coopFinanceUiEmpty,
                            sub: stringsOf(context).coopFinanceUiEmptyHint,
                            large: true,
                          )
                        : RefreshIndicator.adaptive(
                            onRefresh: () async =>
                                ref.invalidate(coopFinanceProvider),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(CyTokens.pageX),
                              itemCount: rows.length,
                              itemBuilder: (BuildContext context, int i) =>
                                  _FinanceTile(
                                    row: rows[i],
                                    onPressed: () => context.push(
                                      '/coop/settlement-detail?source=finance&recordId=${rows[i].topicId}',
                                    ),
                                  ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FinanceTile extends StatelessWidget {
  const _FinanceTile({required this.row, required this.onPressed});
  final CoopFinanceRow row;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final strings = stringsOf(context);
    final income = cny(row.myIncome);
    final hint = income == null ? null : row.myIncomeArrived
        ? strings.coopSettlementArrived : strings.coopFinanceUiWaitingPayment;
    final payout = (row.merchantPayoutTime ?? '').isNotEmpty
        ? strings.coopFinanceUiPartnerPaid(row.merchantPayoutTime!)
        : (row.merchantPayableTime ?? '').isNotEmpty
            ? strings.coopFinanceUiPartnerExpected(row.merchantPayableTime!) : null;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        margin: const EdgeInsets.only(bottom: CyTokens.space3),
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: CyPalette.of(context).borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(row.hasCustomTopicName ? row.topicName : strings.coopSettlementUnnamed, style: textTheme.titleMedium),
                ),
                Flexible(child: CyTag(label: row.settled ? stringsOf(context).coopFinanceUiSettled : stringsOf(context).coopFinanceUiUnsettled)),
              ],
            ),
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        strings.coopSettlementMyShare,
                        style: textTheme.bodySmall?.copyWith(
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // ★ 未结算显示「待结算」而不是 ¥0.00 ——
                      //   后者会让发起人以为这单一分没赚。
                      Text(income == null ? strings.coopSettlementPending : '¥$income', style: textTheme.titleLarge),
                      // 没金额时不谈到账。
                      if (hint != null)
                        Text(
                          hint,
                          style: textTheme.bodySmall?.copyWith(
                            color: CyPalette.of(context).textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        stringsOf(context).coopFinanceUiPartnerDue,
                        style: textTheme.bodySmall?.copyWith(
                          color: CyPalette.of(context).textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summaryMoney(row.merchantTotal),
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        strings.coopFinanceUiPaid(summaryMoney(row.merchantPaid)),
                        style: textTheme.bodySmall?.copyWith(
                          color: CyPalette.of(context).textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (payout != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                payout,
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space2),
            Text(
              strings.coopFinanceUiSales(summaryMoney(row.totalSales), summaryMoney(row.verifiedSales)),
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 提现行(真源 wxml:13-17 `withdraw-entry`):能提是主按钮,否则次按钮
/// 禁用 + 下面一行原因说清为什么不能提。**点了不发任何提现请求** ——
/// R10 过渡期出口只有「联系平台客服提现」弹窗(R10 见
/// `withdrawal_contact_dialog.dart`,与 /withdrawal 六条入口同一件)。
class _WithdrawEntry extends StatelessWidget {
  const _WithdrawEntry({required this.facts});

  final _WithdrawFacts facts;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CyNativeButton(
            key: const Key('coop-finance-withdraw'),
            label: stringsOf(context).clubSettlementContactWithdrawal,
            role: facts.canWithdraw
                ? CyNativeButtonRole.primary
                : CyNativeButtonRole.secondary,
            onPressed: facts.canWithdraw
                ? () => showWithdrawalContactDialog(context)
                : null,
          ),
          if (facts.reason(context) != null) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              facts.reason(context)!,
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
