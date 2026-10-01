import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_operator.dart';
import '../../data/models/merchant_ledger.dart';

/// Only known app-owned getter outputs belong here; backend labels bypass it.
String merchantOperationModelText(BuildContext context, String text) => switch (text) {
  '待付款' => stringsOf(context).merchantOperationsAwaitingPayment,
  '待发货' => stringsOf(context).merchantOperationsAwaitingShipment,
  '已发货' => stringsOf(context).merchantOperationsShipped,
  '待评价' => stringsOf(context).merchantOperationsAwaitingReview,
  '已完成' => stringsOf(context).merchantOperationsCompleted,
  '已关闭' => stringsOf(context).merchantOperationsClosed,
  '无效订单' => stringsOf(context).merchantOperationsInvalidOrder,
  '售后处理中' => stringsOf(context).merchantOperationsAfterSalesInProgress,
  '退款中' => stringsOf(context).merchantOperationsRefundInProgress,
  '退款成功' => stringsOf(context).merchantOperationsRefundSuccessful,
  '全部' => stringsOf(context).merchantOperationsAll,
  '待结算' => stringsOf(context).merchantOperationsAwaitingSettlement,
  '已结算' => stringsOf(context).merchantOperationsSettled,
  '退款处理中' => stringsOf(context).merchantOperationsRefundProcessing,
  '待回应' => stringsOf(context).merchantOperationsAwaitingResponse,
  '处理中' => stringsOf(context).merchantOperationsProcessing,
  '平台审核中' => stringsOf(context).merchantOperationsPlatformReviewInProgress,
  '平台未通过退款' => stringsOf(context).merchantOperationsRefundNotApprovedByPlatform,
  '等待人工退款' => stringsOf(context).merchantOperationsAwaitingManualRefund,
  '人工退款待复核' => stringsOf(context).merchantOperationsManualRefundAwaitingVerification,
  '平台确认已退款' => stringsOf(context).merchantOperationsRefundConfirmedByPlatform,
  '平台状态待确认' => stringsOf(context).merchantOperationsPlatformStatusUnconfirmed,
  '等待商家意见' => stringsOf(context).merchantOperationsAwaitingMerchantResponse,
  '商家已同意申请' => stringsOf(context).merchantOperationsMerchantAgreedToRequest,
  '商家建议驳回' => stringsOf(context).merchantOperationsMerchantRecommendsRejection,
  '同意申请' => stringsOf(context).merchantOperationsAgreeToRequest,
  '建议驳回' => stringsOf(context).merchantOperationsRecommendRejection,
  '补充凭证' => stringsOf(context).merchantOperationsAddEvidence,
  '报名退款' => stringsOf(context).merchantOperationsRegistrationRefund,
  '退款申请' => stringsOf(context).merchantOperationsRefundRequest,
  '金额待确认' => stringsOf(context).merchantOperationsAmountToBeConfirmed,
  '意见内容不能超过500字' => stringsOf(context).merchantOperationsResponseMustNotExceed500Characters,
  '请填写建议驳回的原因' => stringsOf(context).merchantOperationsEnterAReasonForRecommendingRejection,
  '凭证上传结果无效，请重新上传' => stringsOf(context).merchantOperationsEvidenceUploadResultIsInvalidUploadAgain,
  '请先上传凭证图片' => stringsOf(context).merchantOperationsUploadAnEvidenceImageFirst,
  '店主' => stringsOf(context).merchantOperationsStoreOwner,
  '店长' => stringsOf(context).merchantOperationsManager,
  '核销员' => stringsOf(context).merchantOperationsRedemptionClerk,
  '运营' => stringsOf(context).merchantOperationsOperations,
  '财务' => stringsOf(context).merchantOperationsFinance,
  '未知岗位' => stringsOf(context).merchantOperationsUnknownRole,
  '商家成员' => stringsOf(context).merchantOperationsMerchantMember,
  '核销' => stringsOf(context).merchantOperationsRedemptions,
  '项目' => stringsOf(context).merchantOperationsProjects,
  '客户' => stringsOf(context).merchantOperationsCustomers,
  '营销' => stringsOf(context).merchantOperationsMarketing,
  '基础经营信息' => stringsOf(context).merchantOperationsBasicBusinessInformation,
  '未设置昵称' => stringsOf(context).merchantOperationsNicknameNotSet,
  '不结现金' => stringsOf(context).merchantOperationsNoCashSettlement,
  '本次不产生现金结算' => stringsOf(context).merchantOperationsNoCashSettlementForThisTransaction,
  '待主题结算' => stringsOf(context).merchantOperationsAwaitingThemeSettlement,
  '已入个人账户' => stringsOf(context).merchantOperationsCreditedToPersonalAccount,
  '平台已打款' => stringsOf(context).merchantOperationsPaidByPlatform,
  '调整中' => stringsOf(context).merchantOperationsAdjustmentInProgress,
  '已调整' => stringsOf(context).merchantOperationsAdjusted,
  '核销已撤销' => stringsOf(context).merchantOperationsRedemptionReversed,
  '结算数据异常,已上报' => stringsOf(context).merchantOperationsSettlementDataErrorReported,
  '状态待确认' => stringsOf(context).merchantOperationsStatusUnconfirmed,
  '本期无需打款' => stringsOf(context).merchantOperationsNoPaymentNeededThisPeriod,
  '调整待处理' => stringsOf(context).merchantOperationsAdjustmentPending,
  '结算处理中' => stringsOf(context).merchantOperationsSettlementProcessing,
  '平台已打款 · 已开票' => stringsOf(context).merchantOperationsPaidByPlatformInvoiced,
  '平台已打款 · 未开票' => stringsOf(context).merchantOperationsPaidByPlatformNotInvoiced,
  '已确认' => stringsOf(context).merchantOperationsConfirmed,
  '待对账' => stringsOf(context).merchantOperationsAwaitingReconciliation,
  '未开票' => stringsOf(context).merchantOperationsNotInvoiced,
  '已开票' => stringsOf(context).merchantOperationsInvoiced,
  '已红冲' => stringsOf(context).merchantOperationsInvoiceReversed,
  _ => text,
};

String localizedMerchantRoleName(BuildContext context, MerchantAssignableRole role) =>
    role.hasNameFallback ? merchantOperationModelText(context, role.role.label) : role.name;
String localizedMerchantStoreName(BuildContext context, MerchantOperatorAccess? access) =>
    access == null || access.merchantName == null || access.hasMerchantNameFallback
        ? stringsOf(context).merchantOperationsStore : access.merchantName!;
String localizedMerchantNickname(BuildContext context, MerchantOperator operator) =>
    operator.hasNicknameFallback ? stringsOf(context).merchantOperationsNicknameNotSet : operator.nickname;
String localizedMerchantPermissions(BuildContext context, MerchantAssignableRole role) =>
    role.permissionText.split('、').map((label) => merchantOperationModelText(context, label))
        .join(Localizations.localeOf(context).languageCode == 'zh' ? '、' : ', ');
String localizedMerchantLedgerState(BuildContext context, MerchantRedemption row) {
  if (row.displayState == 'NO_CASH_SETTLEMENT' && (row.noCashReason?.isNotEmpty ?? false)) {
    return row.noCashReason!;
  }
  if (const {'NO_CASH_SETTLEMENT', 'PENDING_SETTLEMENT', 'SETTLED'}.contains(row.displayState)) {
    return merchantOperationModelText(context, row.stateText);
  }
  return row.stateText;
}
