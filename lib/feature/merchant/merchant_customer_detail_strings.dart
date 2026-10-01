import 'package:flutter/widgets.dart';
import '../../data/api/merchant_customer_detail_api.dart';
import '../../l10n/strings.dart';

String merchantCustomerApiError(BuildContext context, MerchantCustomerDetailApiException error) => error.isLocalFallback ? _local(context, error.message) : error.message;
String merchantCustomerApiReceipt(BuildContext context, MerchantCustomerMutationReceipt receipt) => receipt.isLocalFallback ? _local(context, receipt.message) : receipt.message;

String _local(BuildContext context, String message) => switch (message) {
  '经营身份数据不完整，请稍后重试' => stringsOf(context).merchantCustomerApiAccess,
  '客户详情数据不完整，请稍后重试' => stringsOf(context).merchantCustomerApiDetail,
  '客户ID无效' => stringsOf(context).merchantCustomerApiCustomerId,
  '请填写跟进备注' => stringsOf(context).merchantCustomerApiNoteRequired,
  '跟进备注最多500字' => stringsOf(context).merchantCustomerApiNoteLimit,
  '被更正备注ID无效' => stringsOf(context).merchantCustomerApiCorrectionId,
  '备注ID无效' => stringsOf(context).merchantCustomerApiNoteId,
  '备注版本无效' => stringsOf(context).merchantCustomerApiNoteVersion,
  '请填写标签名称' => stringsOf(context).merchantCustomerApiTagRequired,
  '标签最多16字' => stringsOf(context).merchantCustomerApiTagLimit,
  '标签颜色无效' => stringsOf(context).merchantCustomerApiTagColor,
  '标签ID无效' => stringsOf(context).merchantCustomerApiTagId,
  '请求失败' => stringsOf(context).merchantCustomerApiRequest,
  '服务端未返回可确认的结果' => stringsOf(context).merchantCustomerApiResult,
  '网络连接失败，请稍后重试' => stringsOf(context).merchantCustomerApiNetwork,
  '请求标识无效' => stringsOf(context).merchantCustomerApiRequestId,
  '跟进备注已保存' => stringsOf(context).merchantCustomerApiNoteSaved,
  '备注已隐藏' => stringsOf(context).merchantCustomerApiNoteHidden,
  '客户标签已保存' => stringsOf(context).merchantCustomerApiTagSaved,
  '标签已移除' => stringsOf(context).merchantCustomerApiTagRemoved,
  _ => message,
};
