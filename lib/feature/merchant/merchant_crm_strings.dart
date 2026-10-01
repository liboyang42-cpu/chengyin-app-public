import '../../data/api/merchant_crm_console_api.dart';
import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_crm_console.dart';
import '../../data/models/merchant_crm_export.dart';

/// Only local enum/option labels; never use with backend data.
String merchantCrmLocalText(BuildContext context, String text) => switch(text) {
  '待核销' => stringsOf(context).merchantCrmPending,
  '异常' => stringsOf(context).merchantCrmAbnormal,
  '沉睡' => stringsOf(context).merchantCrmDormant,
  '复购' => stringsOf(context).merchantCrmRepeat,
  '新客' => stringsOf(context).merchantCrmNew,
  '全部' => stringsOf(context).merchantCrmAll,
  '回头客' => stringsOf(context).merchantCrmReturning,
  '有备注' => stringsOf(context).merchantCrmNoted,
  '这一段' => stringsOf(context).merchantCrmThisSegment,
  _ => text,
};
String merchantCrmCustomerName(BuildContext context, CrmCustomerRow row) => row.name.trim().isEmpty ? stringsOf(context).merchantCrmUnnamed : row.name.trim();
String merchantCrmSegmentName(BuildContext context, CrmSavedSegment row) => row.hasNameFallback ? stringsOf(context).merchantCrmSavedSegment : row.name;
String merchantCrmCouponName(BuildContext context, CrmCoupon row) => row.hasNameFallback ? stringsOf(context).merchantCrmCoupon : row.name;
String merchantCrmSummary(BuildContext context, CrmCustomerPageData? data) {
  final count = data?.segmentCounts['all'];
  if (count == null) return stringsOf(context).merchantCrmCountLoading;
  final monthly = data?.segmentCounts['monthlyNew'];
  return monthly == null ? stringsOf(context).merchantCrmCount(count) : stringsOf(context).merchantCrmCountMonthly(count, monthly);
}
String merchantCrmRelativeTime(BuildContext context, String? value, DateTime now) {
  if (value == null || value.isEmpty) return '';
  final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (parsed == null) return '';
  final days = now.difference(parsed).inDays;
  if (days < 0) return '';
  if (days == 0) return stringsOf(context).merchantCrmToday;
  if (days == 1) return stringsOf(context).merchantCrmYesterday;
  if (days < 30) return stringsOf(context).merchantCrmDays(days);
  if (days < 365) return stringsOf(context).merchantCrmMonths(days ~/ 30);
  return stringsOf(context).merchantCrmYears(days ~/ 365);
}
String merchantCrmAction(BuildContext context, CrmCustomerRow row, DateTime now) => [row.lastAction.trim(), merchantCrmRelativeTime(context, row.lastTime, now)].where((value) => value.isNotEmpty).join(' · ');
String merchantCrmExportStatus(BuildContext context, MerchantCrmExportTask task) => switch(task.status) {
  'PENDING' || 'RUNNING' => stringsOf(context).merchantCrmExportRunning,
  'SUCCESS' => stringsOf(context).merchantCrmExportReady(task.rowCount ?? 0),
  'EXPIRED' => stringsOf(context).merchantCrmExportExpired,
  'FAILED' => stringsOf(context).merchantCrmExportFailed,
  _ => stringsOf(context).merchantCrmExportUnknown,
};

String merchantCrmCampaignStatus(BuildContext context, CrmCampaignTask row) => switch(row.status) {
  'SUCCESS' => stringsOf(context).merchantCrmPanelSuccess,
  'PARTIAL_FAILED' => stringsOf(context).merchantCrmPanelPartial,
  'NO_ELIGIBLE' => stringsOf(context).merchantCrmPanelNoEligible,
  _ => stringsOf(context).merchantCrmPanelProcessing,
};
String merchantCrmCampaignTitle(BuildContext context, CrmCampaignTask row) => row.title.trim().isNotEmpty ? row.title.trim() : row.channel == 'COUPON' ? stringsOf(context).merchantCrmPanelCouponCampaign : stringsOf(context).merchantCrmPanelInAppCampaign;
String merchantCrmRecipientStatus(BuildContext context, CrmCampaignRecipient row) => row.status == 'DELIVERED' ? stringsOf(context).merchantCrmPanelDelivered : row.failureMessage.trim().isNotEmpty ? row.failureMessage.trim() : stringsOf(context).merchantCrmPanelPending;
String merchantCrmBroadcastStatus(BuildContext context, CrmBroadcastResult row) => switch(row.status) {
  'SUCCESS' => stringsOf(context).merchantCrmPanelSent,
  'PARTIAL_FAILED' => stringsOf(context).merchantCrmPanelPartDelivered,
  _ => stringsOf(context).merchantCrmPanelUndelivered,
};

/// Do not infer provenance by matching a server message.
String merchantCrmErrorText(BuildContext context, MerchantCrmApiException error) {
  if (!error.isLocalFallback) return error.message;
  return switch (error.message) {
    '客户名单加载失败' => stringsOf(context).merchantCrmErrorListLoad,
    '客户名单数据格式异常，请稍后重试' => stringsOf(context).merchantCrmErrorListFormat,
    '批量加标签失败' => stringsOf(context).merchantCrmErrorBatchTag,
    '号码没能取到，请检查网络后重试' => stringsOf(context).merchantCrmErrorContactLoad,
    '服务端没有下发可用号码' => stringsOf(context).merchantCrmErrorContactMissing,
    '保存分群加载失败' => stringsOf(context).merchantCrmErrorSegmentsLoad,
    '保存分群失败' => stringsOf(context).merchantCrmErrorSegmentSave,
    '优惠券加载失败' => stringsOf(context).merchantCrmErrorCouponsLoad,
    '触达预览失败' => stringsOf(context).merchantCrmErrorPreview,
    '触达任务创建失败' => stringsOf(context).merchantCrmErrorCreate,
    '触达发送失败，可从任务列表重试' => stringsOf(context).merchantCrmErrorDispatch,
    '触达历史加载失败，请稍后重试' => stringsOf(context).merchantCrmErrorHistory,
    '网络连接失败，人数没核出来' => stringsOf(context).merchantCrmErrorReachNetwork,
    '可触达人数没算出来，请稍后重试' => stringsOf(context).merchantCrmErrorReachMissing,
    '发送失败，请重试' => stringsOf(context).merchantCrmErrorSend,
    '发送结果异常，请重试并按结果核对' => stringsOf(context).merchantCrmErrorResult,
    '回执加载失败' => stringsOf(context).merchantCrmErrorReceipt,
    '重试失败' => stringsOf(context).merchantCrmErrorRetry,
    '网络连接失败，请稍后重试' => stringsOf(context).merchantCrmErrorNetwork,
    '操作失败' => stringsOf(context).merchantCrmErrorOperation,
    '网络连接失败，点发送可重试（不会重复送达）' => stringsOf(context).merchantCrmPolicyNetworkRetry,
    _ => error.message,
  };
}

String merchantCrmDeliveryPolicy(BuildContext context, String status) => status == 'CONSENT_REQUIRED'
    ? stringsOf(context).merchantCrmPolicyConsentRequired
    : stringsOf(context).merchantCrmPolicyRulesPending;

String merchantCrmBroadcastPreviewText(BuildContext context, CrmBroadcastPreview preview) {
  var text = stringsOf(context).merchantCrmPolicyPreview(preview.deliverableCount, preview.noConsentCount);
  if (preview.frequencyLimitedCount > 0) {
    text += stringsOf(context).merchantCrmPolicyFrequency(preview.frequencyLimitedCount);
  }
  if (preview.filterTotalCount > preview.audienceCount) {
    text += stringsOf(context).merchantCrmPolicyRecipientLimit(preview.recipientLimit);
  }
  return text;
}
