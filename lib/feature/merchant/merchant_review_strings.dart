import '../../data/api/merchant_review_api.dart';
import 'package:flutter/widgets.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_review.dart';

/// Only call with a local draft validation result, never a backend error.
String? merchantReviewLocalValidation(BuildContext context, String? message) => switch(message) {
  '核销资格已失效，请刷新' => stringsOf(context).merchantPublicReviewEligibilityExpired,
  '请选择 1 到 5 星评分' => stringsOf(context).merchantPublicReviewRatingRequired,
  '评价正文需填写 2 到 1000 字' => stringsOf(context).merchantPublicReviewContentLength,
  '评价图片最多 9 张' => stringsOf(context).merchantPublicReviewImageLimit,
  '评价图片必须来自城瘾安全上传链路' => stringsOf(context).merchantPublicReviewTrustedImages,
  '评价状态已失效，请刷新' => stringsOf(context).merchantPublicReviewReviewExpired,
  '回复内容需填写 1 到 500 字' => stringsOf(context).merchantPublicReviewReplyLength,
  '举报原因需填写 2 到 500 字' => stringsOf(context).merchantPublicReviewReasonLength,
  _ => message,
};
String merchantReviewEligibilityTitle(BuildContext context, MerchantReviewEligibility eligibility) => switch(eligibility.reasonCode) {
  'LOGIN_REQUIRED' => stringsOf(context).merchantPublicReviewLoginRequired,
  'AMBIGUOUS_LEGACY_MERCHANT_SCOPE' => stringsOf(context).merchantPublicReviewAmbiguous,
  'MERCHANT_UNAVAILABLE' => stringsOf(context).merchantPublicReviewMerchantUnavailable,
  _ => stringsOf(context).merchantPublicReviewNoEligibility,
};

String merchantReviewErrorText(BuildContext context, Object error) {
  if (error is MerchantReviewLocalFormatException) {
    if (error.field != null) return stringsOf(context).merchantReviewModelField(error.field!);
    return _merchantReviewModelText(context, error.message);
  }
  if (error is MerchantReviewLocalArgumentError) {
    return _merchantReviewModelText(context, error.localMessage);
  }
  if (error is MerchantReviewApiException && error.isLocalFallback) {
    return switch (error.message) {
      '评价加载失败' => stringsOf(context).merchantReviewApiLoad,
      '回复失败' => stringsOf(context).merchantReviewApiReply,
      '评价提交失败' => stringsOf(context).merchantReviewApiCreate,
      '修改回复失败' => stringsOf(context).merchantReviewApiUpdate,
      '删除回复失败' => stringsOf(context).merchantReviewApiDelete,
      '举报提交失败' => stringsOf(context).merchantReviewApiReport,
      '评价服务回执不完整' => stringsOf(context).merchantReviewApiReceipt,
      _ => error.message,
    };
  }
  return error.toString().replaceFirst('Exception: ', '');
}

String _merchantReviewModelText(BuildContext context, String message) => switch(message) {
  '评价状态不完整' => stringsOf(context).merchantReviewModelStatus,
  '评价资格回执不一致' => stringsOf(context).merchantReviewModelEligibilityMismatch,
  '评分必须在 1 到 5 之间' => stringsOf(context).merchantReviewModelRating,
  '评价图片不完整' => stringsOf(context).merchantReviewModelImages,
  '评价图片地址不安全' => stringsOf(context).merchantReviewModelImageUrl,
  '评价回复权限与状态不一致' => stringsOf(context).merchantReviewModelReplyPermission,
  '评价举报权限与状态不一致' => stringsOf(context).merchantReviewModelReportPermission,
  '评价列表视角不匹配' => stringsOf(context).merchantReviewModelMode,
  '评价分页回执不匹配' => stringsOf(context).merchantReviewModelPagination,
  '评价列表不完整' => stringsOf(context).merchantReviewModelList,
  '评价行不完整' => stringsOf(context).merchantReviewModelRow,
  '公开列表包含未公开评价' => stringsOf(context).merchantReviewModelPublic,
  '评价分页总数不一致' => stringsOf(context).merchantReviewModelTotal,
  '评价均分不完整' => stringsOf(context).merchantReviewModelAverage,
  '评价资格回执不完整' => stringsOf(context).merchantReviewModelEligibility,
  '商家管理列表不应包含个人资格' => stringsOf(context).merchantReviewModelManageEligibility,
  'OSS bucket 配置不合法' => stringsOf(context).merchantReviewModelBucket,
  'OSS endpoint 配置不合法' => stringsOf(context).merchantReviewModelEndpoint,
  '上传回执不符合评价图片安全合同' => stringsOf(context).merchantReviewModelUpload,
  '评价操作回执串单' => stringsOf(context).merchantReviewModelReceiptMismatch,
  '评价提交回执不完整' => stringsOf(context).merchantReviewModelCreateReceipt,
  '公开回复回执不完整' => stringsOf(context).merchantReviewModelReplyReceipt,
  '举报复核回执不完整' => stringsOf(context).merchantReviewModelReportReceipt,
  '文本回执不完整' => stringsOf(context).merchantReviewModelText,
  '时间回执不完整' => stringsOf(context).merchantReviewModelTime,
  '请求标识不合法' => stringsOf(context).merchantReviewModelRequestId,
  'merchantRowId 不合法' => stringsOf(context).merchantReviewModelMerchantId,
  '商家主体信息不完整' => stringsOf(context).merchantReviewModelMerchantIdentity,
  _ => merchantReviewLocalValidation(context, message) ?? message,
};
