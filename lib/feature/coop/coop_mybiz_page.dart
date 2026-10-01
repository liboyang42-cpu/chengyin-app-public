import '../../l10n/strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_mybiz.dart';
import 'coop_guard.dart';

final coopMyBizProvider = FutureProvider.autoDispose<CoopMyBiz>((ref) async {
  final data = await ref.watch(coopApiProvider).myBiz();
  return CoopMyBiz.fromJson(data);
});

/// 商家结算工作台。对齐小程序 `pages/coop/settlement-detail`(source=ledger 档)。
///
/// ★ 只读页,金额一律用后端下发的值。
class CoopMyBizPage extends ConsumerWidget {
  const CoopMyBizPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title = stringsOf(context).coopFinanceUiMyBizTitle;
    final String needLogin = stringsOf(context).coopLoginMyCooperation;
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(coopMyBizProvider);
    return CupertinoPageScaffold(
      // 显式给浅色底,理由见 coop_guard.dart。
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: async.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (Object e, _) => isCoopUnauthorized(e)
            ? coopLoginView(
                context,
                ref,
                navTitle: title,
                message: needLogin,
                refetch: () => ref.invalidate(coopMyBizProvider),
              )
            : StatusView(
                message: stringsOf(context).coopMyBusinessLoadFailed,
                sub: coopErrorSub(e, context: context),
                large: true,
                onRetry: () => ref.invalidate(coopMyBizProvider),
              ),
        data: (CoopMyBiz biz) {
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.invalidate(coopMyBizProvider),
            child: ListView(
              padding: const EdgeInsets.all(CyTokens.pageX),
              children: <Widget>[
                _SummaryCard(biz: biz),
                const SizedBox(height: CyTokens.space4),
                CySectionTitle(stringsOf(context).coopFinanceUiRecords),
                const SizedBox(height: CyTokens.space2),
                if (biz.settlements.isEmpty)
                  StatusView(
                    message: stringsOf(context).coopFinanceUiNoRecords,
                    sub: stringsOf(context).coopFinanceUiNoRecordsHint,
                  )
                else
                  ...biz.settlements.map(
                    (CoopSettlementRow s) => _SettlementTile(
                      row: s,
                      onPressed: () => context.push(
                        '/coop/settlement-detail?source=ledger&recordId=${s.id}',
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.biz});
  final CoopMyBiz biz;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stringsOf(context).coopPerformance90Days,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text('${biz.fulfillmentRate}%', style: textTheme.headlineSmall),
                if (biz.violationCount > 0)
                  Text(
                    stringsOf(context).coopFinanceUiViolations(biz.violationCount),
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).statusDanger,
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
                  stringsOf(context).coopReviews,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                // ★ 均分为 0 且条数为 0 是"还没有评价",不是"评分很差" ——
                //   两者后端都给 avgRating=0,只有 reviewCount 能区分。
                Text(
                  biz.reviewCount > 0 ? stringsOf(context).coopFinanceUiRating(biz.avgRating.toString()) : stringsOf(context).coopNoReviews,
                  key: const Key('coop_mybiz_rating_text'),
                  style: textTheme.headlineSmall,
                ),
                if (biz.reviewCount > 0)
                  Text(
                    stringsOf(context).coopFinanceUiReviewCount(biz.reviewCount),
                    style: textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textTertiary,
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

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.row, required this.onPressed});
  final CoopSettlementRow row;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final strings = stringsOf(context);
    final rule = switch (row.shareMode) {
      0 => strings.coopSettlementTraffic,
      1 => row.shareRate == null ? strings.coopSettlementPercentage : strings.coopSettlementRate('${row.shareRate}'),
      2 => row.fixedFee == null ? strings.coopSettlementFixed : strings.coopSettlementFixedAmount(row.fixedFee!.toStringAsFixed(2)),
      _ => null,
    };
    final title = (row.topicName ?? '').trim().isNotEmpty ? row.topicName!.trim()
        : row.topicId == null ? strings.coopSettlementUnnamed : strings.coopSettlementTopicId(row.topicId!);
    final status = switch (row.status) {
      0 => strings.coopSettlementAwaitingCredit,
      1 => strings.coopSettlementInBalance,
      2 => strings.coopSettlementVoidStatus,
      _ => strings.coopSettlementUnknownStatus,
    };
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
                  child: Text(title, style: textTheme.titleMedium),
                ),
                Flexible(child: CyTag(label: status)),
              ],
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              row.payeeType?.trim().toLowerCase() == 'club' ? strings.coopSettlementClubShare : strings.coopSettlementMerchantShare,
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            // 金额缺席(结算尚未算出)不显示 ¥0.00,直接不提这一行。
            if (row.amount != null)
              Text(
                '¥${row.amount!.toStringAsFixed(2)}',
                style: textTheme.titleLarge,
              ),
            Text(
              <String>[
                ?rule,
                if (row.verifiedHeads != null) strings.coopFinanceUiRedeemedPeople(row.verifiedHeads!),
                if (row.verifiedSales != null)
                  strings.coopFinanceUiRedeemedSales(row.verifiedSales!.toStringAsFixed(2)),
              ].join(' · '),
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
