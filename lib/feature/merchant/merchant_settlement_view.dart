import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_finance.dart';
import '../../data/models/merchant_ledger.dart';
import 'finance_state_text.dart';
import 'merchant_error_view.dart';

/// 结算总览(`/api/merchant/finance/overview`)。
final financeOverviewProvider =
    FutureProvider.autoDispose<MerchantSettlementOverview>((Ref ref) {
      return ref.watch(merchantApiProvider).financeOverview();
    });

/// 收入明细(`/api/merchant/finance/settlement-entries`)。
final settlementEntriesProvider = FutureProvider.autoDispose
    .family<MerchantFinancePage<MerchantSettlementEntry>, String>((
      Ref ref,
      String source,
    ) {
      return ref.watch(merchantApiProvider).settlementEntries(source: source);
    });

/// 对公打款批次(`/api/merchant/finance/public-transfer-batches`)。
final transferBatchesProvider =
    FutureProvider.autoDispose<MerchantFinancePage<PublicTransferBatch>>((
      Ref ref,
    ) {
      return ref.watch(merchantApiProvider).publicTransferBatches();
    });

/// 账本的「结算」视图。App 此前**只有核销记录** —— 商家看得到核销、
/// 看不到钱去哪了。三条接口(overview / entries / batches)一直零调用方。
///
/// ★ 版式原则抄小程序注释:**「每页只准一个主数字。毛额/调整/待对公降为
///   卡内 key-value,和主数字拉开量级」** —— 别把四个数字并排。
class MerchantSettlementView extends ConsumerWidget {
  const MerchantSettlementView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(financeOverviewProvider);
    return RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(financeOverviewProvider);
        ref.invalidate(settlementEntriesProvider('all'));
        ref.invalidate(transferBatchesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.pageX),
        children: <Widget>[
          overview.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(CyTokens.space5),
              child: Center(child: CupertinoActivityIndicator()),
            ),
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              onRetry: () => ref.invalidate(financeOverviewProvider),
            ),
            data: (MerchantSettlementOverview o) => _Hero(overview: o),
          ),
          const SizedBox(height: CyTokens.space5),
          const _SectionTitle('收入明细'),
          const SizedBox(height: CyTokens.space2),
          const _EntriesBlock(),
          const SizedBox(height: CyTokens.space5),
          const _SectionTitle('对公打款批次'),
          const SizedBox(height: CyTokens.space2),
          const _BatchesBlock(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);
}

/// 主数字卡。★ 一页只有这一个大字。
class _Hero extends StatelessWidget {
  const _Hero({required this.overview});
  final MerchantSettlementOverview overview;

  /// ★ 标签随正负变(小程序 `netLabel`):负数是**净调整**不是净入账 ——
  ///   写成「净入账 -120」商家会以为自己收到了一笔负钱。
  String get _netLabel {
    final double? v = double.tryParse(
      overview.personalArrivedThisMonthNet ?? '',
    );
    return (v != null && v < 0) ? '本月个人账户净调整' : '本月个人账户净入账';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgElevated,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _netLabel,
            style: textTheme.labelMedium?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            _money(overview.personalArrivedThisMonthNet),
            style: textTheme.headlineMedium?.copyWith(
              // T3:强调用 bold trait(700),不用 w800 堆重。
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          // ★ 判据是**笔数**不是金额:一笔 +100 和一笔 -100 合计是 0,
          //   但确实有两笔待处理(见 MerchantSettlementOverview 的注释)。
          //   ⚠️ 小程序用金额判,那是它的 bug,不跟。
          if (overview.hasPendingAdjustment) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            _Chip(
              text: '${overview.adjustmentPendingCount} 笔调整待处理',
              tone: FinanceTone.warning,
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          _Kv('个人账户毛额', _money(overview.personalArrivedThisMonthGross)),
          _Kv('已执行调整', _money(overview.personalExecutedAdjustmentsThisMonth)),
          _Kv('待对公结算', _money(overview.publicPayablePending)),
        ],
      ),
    );
  }
}

/// ★★ 金额一律**后端给什么显示什么**,前端一个都不算(页面注释写死了)。
///   拿不到就显 `—`,**不兜 0** ——「没拿到」和「是 0」是两件事,
///   这一页说的是钱,兜 0 会让商家以为这个月一分没进。
String _money(String? raw) {
  final String v = (raw ?? '').trim();
  return v.isEmpty ? '—' : '¥$v';
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: CyTokens.space1_5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(k, style: textTheme.bodySmall?.copyWith(color: p.textSecondary)),
          Text(
            v,
            style: textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.tone});
  final String text;
  final FinanceTone tone;

  @override
  Widget build(BuildContext context) {
    final Color c = switch (tone) {
      FinanceTone.warning => CyPalette.of(context).statusWarning,
      FinanceTone.success => CyPalette.of(context).statusSuccess,
      FinanceTone.danger => CyPalette.of(context).statusDanger,
      FinanceTone.neutral => CyPalette.of(context).textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c),
      ),
    );
  }
}

class _EntriesBlock extends ConsumerWidget {
  const _EntriesBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settlementEntriesProvider('all'));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(CyTokens.space4),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (Object e, _) => merchantErrorView(
        context,
        e,
        onRetry: () => ref.invalidate(settlementEntriesProvider('all')),
      ),
      data: (MerchantFinancePage<MerchantSettlementEntry> page) =>
          page.rows.isEmpty
          ? const StatusView(
              icon: CupertinoIcons.tray,
              message: '还没有已成立的收入明细',
              // 说清去哪找 —— 待结算的还在核销记录里。
              sub: '待主题结算的履约会留在核销记录中',
            )
          : Column(
              children: page.rows
                  .map((MerchantSettlementEntry e) => _EntryRow(entry: e))
                  .toList(),
            ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final MerchantSettlementEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    final String state = financeStateText(
      displayState: entry.displayState,
      settlementRoute: entry.settlementRoute,
      destination: entry.destination,
    );
    final String amount = (entry.signedAmount ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.source ?? entry.entryKind ?? '收入',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    // ★ 日期取服务端下发的前 10 位,**不在前端做时区换算**
                    //   (小程序注释原话)。换算一次就和后端对不上账了。
                    Text(
                      _day(entry.occurredAt),
                      style: textTheme.labelSmall?.copyWith(
                        color: p.textTertiary,
                      ),
                    ),
                    const SizedBox(width: CyTokens.space2),
                    _Chip(text: state, tone: financeTone(entry.displayState)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          Text(
            // 后端给的就是带符号的串,原样显示 —— 前端不加减不格式化。
            amount.isEmpty ? '—' : '¥$amount',
            style: textTheme.titleSmall?.copyWith(
              color: amount.startsWith('-') ? p.statusDanger : p.statusSuccess,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 服务端时间串的前 10 位。拿不到就说「未标注日期」,不猜今天。
String _day(String? raw) {
  final String s = (raw ?? '').trim();
  if (s.length < 10) return '未标注日期';
  return s.substring(0, 10);
}

class _BatchesBlock extends ConsumerWidget {
  const _BatchesBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transferBatchesProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(CyTokens.space4),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (Object e, _) => merchantErrorView(
        context,
        e,
        onRetry: () => ref.invalidate(transferBatchesProvider),
      ),
      data: (MerchantFinancePage<PublicTransferBatch> page) => page.rows.isEmpty
          ? const StatusView(
              icon: Icons.account_balance_outlined,
              message: '还没有对公打款批次',
              sub: '按自然月归集,当月有需要打款的收入时才会生成',
            )
          : Column(
              children: page.rows
                  .map((PublicTransferBatch b) => _BatchRow(batch: b))
                  .toList(),
            ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch});
  final PublicTransferBatch batch;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    final String state = batchStateText(
      displayState: batch.displayState,
      netDirection: batch.netDirection,
      paymentState: batch.paymentState,
      invoiceState: batch.invoiceState,
      holdState: batch.holdState,
    );
    final String? invoice = invoiceText(batch.invoiceState);
    final String amount = (batch.amountTotal ?? '').trim();
    // ★ 整行可点进明细 —— 之前这里是死的:列出来却点不进去。
    //   批次 id 拿不到就不给点(点了也查不到,还会跳到一个空页)。
    final int? id = int.tryParse(batch.batchId);
    final VoidCallback? action = id == null
        ? null
        : () => context.push('/merchant/ledger/batch/$id');
    return Semantics(
      key: Key('batch-row-${batch.batchId}'),
      button: id != null,
      label: <String?>[
        batch.periodYm ?? '未标注月份',
        state,
        invoice,
        amount.isEmpty ? '金额未知' : '金额 $amount 元',
      ].whereType<String>().join('，'),
      onTap: action,
      excludeSemantics: true,
      child: CupertinoButton(
        onPressed: action,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        batch.periodYm ?? '未标注月份',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: CyTokens.space2,
                        runSpacing: 2,
                        children: <Widget>[
                          _Chip(
                            text: state,
                            tone: batchTone(
                              displayState: batch.displayState,
                              paymentState: batch.paymentState,
                            ),
                          ),
                          // ★ 发票态认不出来时整块不显示,**不写「未开票」**——
                          //   那会让商家去催一张可能已经开了的票。
                          if (invoice != null)
                            Text(
                              invoice,
                              style: textTheme.labelSmall?.copyWith(
                                color: p.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CyTokens.space2),
                Text(
                  amount.isEmpty ? '—' : '¥$amount',
                  style: textTheme.titleSmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                // 有明细可点时给个指示,别让人不知道能点。
                if (id != null)
                  Icon(Icons.chevron_right, size: 18, color: p.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
