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
    const String title = '合作与结算';
    const String needLogin = '登录后查看我的合作';
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
      navigationBar: const CupertinoNavigationBar(middle: Text(title)),
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
                message: '我的合作没能加载出来',
                sub: coopErrorSub(e),
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
                const CySectionTitle('结算记录'),
                const SizedBox(height: CyTokens.space2),
                if (biz.settlements.isEmpty)
                  const StatusView(
                    message: '还没有结算记录',
                    sub: '你承接的合作产生核销后,结算明细会显示在这里',
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
                  '近 90 天履约率',
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text('${biz.fulfillmentRate}%', style: textTheme.headlineSmall),
                if (biz.violationCount > 0)
                  Text(
                    '${biz.violationCount} 次违约',
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
                  '合作评价',
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                // ★ 均分为 0 且条数为 0 是"还没有评价",不是"评分很差" ——
                //   两者后端都给 avgRating=0,只有 reviewCount 能区分。
                Text(
                  biz.reviewCount > 0 ? '${biz.avgRating} 分' : '还没有评价',
                  key: const Key('coop_mybiz_rating_text'),
                  style: textTheme.headlineSmall,
                ),
                if (biz.reviewCount > 0)
                  Text(
                    '共 ${biz.reviewCount} 条',
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
    final rule = row.shareRuleText;
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
                  child: Text(row.topicTitle, style: textTheme.titleMedium),
                ),
                CyTag(label: row.statusText),
              ],
            ),
            const SizedBox(height: CyTokens.space1),
            Text(
              row.payeeText,
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
                if (row.verifiedHeads != null) '核销 ${row.verifiedHeads} 人',
                if (row.verifiedSales != null)
                  '核销销售额 ¥${row.verifiedSales!.toStringAsFixed(2)}',
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
