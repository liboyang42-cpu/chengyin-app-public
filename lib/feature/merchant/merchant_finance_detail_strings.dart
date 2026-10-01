import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_finance.dart';
import 'finance_state_text.dart';
import 'merchant_operations_strings.dart';

/// Only synthesized finance labels, never backend reasons or titles.
String merchantFinanceLocalText(BuildContext context, String text) => switch(text) {
  '随主题结算发放至个人账户' => stringsOf(context).merchantFinanceDetailPendingTheme,
  '结算数据对不上，请联系客服' => stringsOf(context).merchantFinanceDetailDataMismatch,
  '核销有效' => stringsOf(context).merchantFinanceDetailActive,
  '批次生成' => stringsOf(context).merchantFinanceDetailBatchCreated,
  '对账确认' => stringsOf(context).merchantFinanceDetailReconciled,
  '平台打款' => stringsOf(context).merchantFinanceDetailPlatformPayment,
  '核销成功' => stringsOf(context).merchantFinanceDetailRedemptionSuccess,
  '生成结算单' => stringsOf(context).merchantFinanceDetailStatementCreated,
  '审核中' => stringsOf(context).merchantFinanceDetailReviewing,
  '已驳回' => stringsOf(context).merchantFinanceDetailRejected,
  '已退款' => stringsOf(context).merchantFinanceDetailRefunded,
  _ => merchantOperationModelText(context, text),
};
String merchantFinanceRedemptionTitle(BuildContext context, MerchantRedemptionView row) => [row.topicName, row.chapterName].any((value) => value != null && value.trim().isNotEmpty) ? row.titleText : stringsOf(context).merchantFinanceDetailRecord;
String merchantFinanceRedemptionState(BuildContext context, MerchantRedemptionView row) {
  if (!row.canReadFinance) return merchantFinanceLocalText(context, financeFulfillmentStateText(row.fulfillmentState));
  if (row.displayState == 'NO_CASH_SETTLEMENT' && (row.noCashReason ?? '').trim().isNotEmpty) return row.noCashReason!.trim();
  return merchantFinanceLocalText(context, financeRedemptionStateText(displayState: row.displayState, noCashReason: row.noCashReason, settlementRoute: row.settlementRoute));
}
String? merchantFinanceBatchAt(BuildContext context, PublicTransferBatch batch, BatchTimelineNode node) {
  if (node.label != '平台打款' || node.at == null) return node.at;
  final voucher = (batch.payVoucherNo ?? '').trim();
  final paid = (batch.paidAt ?? '').trim();
  if (voucher.isEmpty || paid.isEmpty) return node.at;
  final date = paid.length >= 16 ? paid.substring(0, 16) : paid;
  return stringsOf(context).merchantFinanceDetailPaymentAt(date, voucher);
}
