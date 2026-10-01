import '../../l10n/strings.dart';
import 'merchant_operations_strings.dart';
import 'merchant_finance_detail_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../data/models/merchant_finance.dart';
import 'finance_state_text.dart';
import 'finance_timeline_row.dart';
import 'merchant_crm_panels.dart';
import 'merchant_error_view.dart';

final batchDetailProvider = FutureProvider.autoDispose
    .family<PublicTransferBatchDetail, int>((Ref ref, int batchId) {
      return ref.watch(merchantApiProvider).publicTransferBatchDetail(batchId);
    });

/// 对公打款批次明细。
///
/// ★ 之前账本里的批次行**点不进去** —— 我做了列表没做明细,
///   等于留了个死入口(正是我在任务书里要求 worker 别做的事)。
class BatchDetailPage extends ConsumerWidget {
  const BatchDetailPage({super.key, this.batchId});

  /// 缺参 / 非法 id 是**一个界面态**(对齐小程序 `missing-param`),
  /// 不是编程错误:深链 `/merchant/ledger/batch/abc` 会落到这里。
  final int? batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? id = batchId;
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // 标题照小程序 `pages/merchant/ledger/batch-detail/index.wxml:5`(cy-nav-bar title)。
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantFinanceDetailBatchTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: id == null || id <= 0
              ? StatusView(
                  message: stringsOf(context).merchantFinanceDetailBatchIdMissing,
                  sub: stringsOf(context).merchantFinanceDetailBatchIdHint,
                  large: true,
                  onRetry: () => _backToList(context),
                  retryLabel: stringsOf(context).merchantFinanceDetailBack,
                )
              : _Detail(id: id),
        ),
      ),
    );
  }
}

/// 退不出去时(冷启动深链)退回结算列表 —— 与小程序 `onNavBack` 同一条:
/// 有上一页走上一页,没有就回列表,别把人困在一张空页上。
void _backToList(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/merchant/ledger?view=settlement');
  }
}

/// 后端的「记录不可见」是**越权保护**,不是"这条没了" —— 判据与小程序
/// `isMissingRecordResponse` 同一条正则(后端没有错误码,只能认原话)。
bool _isMissingRecord(String message) =>
    RegExp(r'记录(?:不可见|不存在)').hasMatch(message);

String _errorText(Object error) =>
    error.toString().replaceFirst('Exception: ', '');

/// 复制凭证号。★ 复制必须给回执 —— 剪贴板是看不见的,不说一句用户不知道成没成
/// (与 square_share_sheet 的「链接已复制」同一手法)。
Future<void> _copyVoucher(BuildContext context, String voucher) async {
  await Clipboard.setData(ClipboardData(text: voucher));
  if (!context.mounted) return;
  CyNativeNotice.show(context, stringsOf(context).merchantFinanceDetailVoucherCopied);
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PublicTransferBatchDetail> async = ref.watch(
      batchDetailProvider(id),
    );
    void retry() => ref.invalidate(batchDetailProvider(id));
    final PublicTransferBatchDetail? detail = async.value;

    // ★ 刷新/重试失败**不掀桌**:屏上那份详情照旧可用,只在顶上说明它没更新。
    //   掀桌等于把已经拿到的结算事实从用户眼前拿走 —— 而它并没有失效
    //   (小程序 `refreshing` / `stale-error` 两态)。
    if (detail != null) {
      return Column(
        children: <Widget>[
          if (async.isLoading) const _Refreshing(),
          if (async.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              child: CrmInlineError(
                title: stringsOf(context).merchantFinanceDetailBatchStale,
                sub: _errorText(async.error!),
                onAction: retry,
              ),
            ),
          Expanded(child: _Body(detail: detail)),
        ],
      );
    }
    if (async.hasError) return _errorView(context, async.error!, retry);
    return const Center(child: CupertinoActivityIndicator());
  }

  Widget _errorView(BuildContext context, Object error, VoidCallback retry) {
    // 「记录不可见」照原文说,不给点了没用的重试(merchant_api 批次详情注释)。
    if (error is MerchantApiException && _isMissingRecord(error.message)) {
      return StatusView(
        message: stringsOf(context).merchantFinanceDetailBatchUnavailable,
        sub: stringsOf(context).merchantFinanceDetailBatchUnavailableHint,
        large: true,
        onRetry: () => _backToList(context),
        retryLabel: stringsOf(context).merchantFinanceDetailBatchList,
      );
    }
    return merchantErrorView(context, error, what: stringsOf(context).merchantFinanceDetailBatchDetail, onRetry: retry);
  }
}

/// 小程序 `cy-progress-status`(title + sub):屏上还有旧详情时说明正在读新的。
class _Refreshing extends StatelessWidget {
  const _Refreshing();

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        0,
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              stringsOf(context).merchantFinanceDetailBatchRefreshing,
              style: CyType.caption1.copyWith(color: p.textSecondary),
            ),
            Text(
              stringsOf(context).merchantFinanceDetailOldDetails,
              style: CyType.caption1.copyWith(color: p.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});
  final PublicTransferBatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    final PublicTransferBatch b = detail.batch;
    final bool paidToMe = batchIsPaidToMerchant(
      netDirection: b.netDirection,
      paymentState: b.paymentState,
    );
    final List<BatchTimelineNode> timeline = batchTimeline(
      netDirection: b.netDirection,
      paymentState: b.paymentState,
      paidAt: b.paidAt,
      payVoucherNo: b.payVoucherNo,
    );
    final String amount = (b.amountTotal ?? '').trim();
    // 明细页比列表页多说一句:这里认不出来说「发票状态待确认」而不是整块藏起来
    // ——列表可以省略,明细页省略会让人以为这批没有发票这回事。
    final rawInvoice = invoiceText(b.invoiceState);
    final String invoice = rawInvoice == null ? stringsOf(context).merchantFinanceDetailInvoiceUnknown : merchantOperationModelText(context, rawInvoice);

    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: p.bgElevated,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                stringsOf(context).merchantFinanceDetailNetAmount(b.periodYm ?? stringsOf(context).merchantFinanceDetailPeriodUnknown),
                style: textTheme.labelMedium?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: CyTokens.space1),
              Text(
                // 后端给什么显示什么;拿不到显 — 不兜 0(这一页说的是钱)。
                amount.isEmpty ? '—' : '¥$amount',
                style: textTheme.headlineMedium?.copyWith(
                  // T3:强调用 bold trait(700),不用 w800 堆重。
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space1,
                children: <Widget>[
                  Text(
                    merchantOperationModelText(context, batchStateText(
                      displayState: b.displayState,
                      netDirection: b.netDirection,
                      paymentState: b.paymentState,
                      invoiceState: b.invoiceState,
                      holdState: b.holdState,
                    )),
                    style: textTheme.labelMedium,
                  ),
                  Text(
                    invoice,
                    style: textTheme.labelMedium?.copyWith(
                      color: p.textTertiary,
                    ),
                  ),
                ],
              ),
              // ★ 打款日期/凭证号**只在真的打给我了之后**才显示。
              //   反方向的批次即使 paymentState=PAID 也不算,那笔是商家欠平台的。
              if (paidToMe) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                if ((b.paidAt ?? '').isNotEmpty) _Kv(stringsOf(context).merchantFinanceDetailPaidDate, b.paidAt!),
                if ((b.payVoucherNo ?? '').isNotEmpty)
                  // 凭证号是拿去跟财务对账的,只在屏上显示带不走没有用 ——
                  // 小程序那行整行可点(`aria-label="复制打款凭证"`)。
                  _Kv(
                    stringsOf(context).merchantFinanceDetailVoucher,
                    stringsOf(context).merchantFinanceDetailVoucherCopy(b.payVoucherNo!),
                    onTap: () => _copyVoucher(context, b.payVoucherNo!),
                    semanticsLabel: stringsOf(context).merchantFinanceDetailCopyVoucher,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        Text(stringsOf(context).merchantFinanceDetailStatement, style: textTheme.titleMedium),
        const SizedBox(height: CyTokens.space2),
        if (detail.earningEntries.isEmpty && detail.adjustments.isEmpty)
          StatusView(
            icon: CupertinoIcons.tray,
            message: stringsOf(context).merchantFinanceDetailEntriesEmpty,
            sub: stringsOf(context).merchantFinanceDetailEntriesEmptyHint,
          )
        else ...<Widget>[
          // ★★ 收入与调整**分开两段**。后端就是分开给的,合并成一个列表
          //   商家看不出哪些是扣减(模型注释写死了这条)。
          ...detail.earningEntries.map(
            (MerchantSettlementEntry e) => _EntryRow(entry: e),
          ),
          if (detail.adjustments.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Text(
              stringsOf(context).merchantFinanceDetailAdjustments,
              style: textTheme.labelMedium?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: CyTokens.space1),
            ...detail.adjustments.map(
              (MerchantSettlementEntry e) => _EntryRow(entry: e),
            ),
          ],
        ],
        if (timeline.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space5),
          Text(stringsOf(context).merchantFinanceDetailPaymentProgress, style: textTheme.titleMedium),
          const SizedBox(height: CyTokens.space2),
          ...timeline.map((BatchTimelineNode n) => FinanceTimelineRow(node: n, displayAt: merchantFinanceBatchAt(context, b, n))),
        ],
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.onTap, this.semanticsLabel});
  final String k;
  final String v;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = CyPalette.of(context);
    final Widget row = Padding(
      padding: const EdgeInsets.only(top: CyTokens.space1_5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(k, style: textTheme.bodySmall?.copyWith(color: p.textSecondary)),
          Text(v, style: textTheme.bodyMedium),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
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
    final String amount = (entry.signedAmount ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space1_5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              entry.source ?? entry.entryKind ?? stringsOf(context).merchantFinanceDetailEntry,
              style: textTheme.bodyMedium,
            ),
          ),
          Text(
            amount.isEmpty ? '—' : '¥$amount',
            style: textTheme.bodyMedium?.copyWith(
              color: amount.startsWith('-')
                  ? CyTokens.statusDanger
                  : p.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

