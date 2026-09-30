import 'dart:math';

import 'package:dio/dio.dart';

import '../../data/api/page_parity_api.dart';
import '../../data/models/marketing_consent.dart';

/// 订单详情/报名成功弹层里的「商家消息」营销同意行。
/// 1:1 移植小程序 `components/cy/marketing-consent-entry/marketing-consent-entry.js`
/// 的纯判据(pickOffer / loadOffer 静默失败 / 同一 requestId 重试复用)。
class ConsentOffer {
  const ConsentOffer({
    required this.merchantRowId,
    required this.merchantOwnerMemberId,
    required this.merchantName,
  });

  final int merchantRowId;
  final int merchantOwnerMemberId;
  final String merchantName;
}

/// 从同意记录里挑本单商家的 offer:ownerMemberId 必须为正、恰好一条匹配、
/// 且尚未在站内(inAppOptedIn)同意过。0 条或 >1 条(歧义)一律给 null —— 不赌。
ConsentOffer? pickConsentOffer(
  List<MarketingConsent> rows,
  int? ownerMemberId,
) {
  final int owner = ownerMemberId ?? 0;
  if (owner <= 0) return null;
  final List<MarketingConsent> matches = rows
      .where((MarketingConsent row) => row.merchantOwnerMemberId == owner)
      .toList(growable: false);
  if (matches.length != 1) return null;
  final MarketingConsent row = matches.single;
  if (row.inAppOptedIn) return null;
  if (row.merchantRowId <= 0) return null;
  return ConsentOffer(
    merchantRowId: row.merchantRowId,
    merchantOwnerMemberId: row.merchantOwnerMemberId,
    merchantName: row.merchantName.isEmpty ? '商家' : row.merchantName,
  );
}

/// 加载 offer 是**静默**的:任何失败都当「没有这条」,绝不打扰用户。
Future<ConsentOffer?> loadConsentOffer(
  PageParityApi api,
  int? ownerMemberId,
) async {
  try {
    return pickConsentOffer(await api.marketingConsents(), ownerMemberId);
  } catch (_) {
    return null;
  }
}

/// 幂等键,格式逐字对齐小程序 `newRequestId`:重试必须复用同一个值。
String newConsentRequestId(String kind) {
  final int rand = Random().nextInt(0xFFFFFF);
  return 'consent-$kind-'
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-'
      '${rand.toRadixString(36)}';
}

/// 提交站内同意。成功返回 null;失败返回给用户的原文案(与小程序逐字同源)。
Future<String?> submitConsent(
  PageParityApi api, {
  required ConsentOffer offer,
  required bool optedIn,
  required String requestId,
}) async {
  try {
    await api.setMarketingConsent(
      merchantRowId: offer.merchantRowId,
      merchantOwnerMemberId: offer.merchantOwnerMemberId,
      channel: 'IN_APP',
      optedIn: optedIn,
      requestId: requestId,
    );
    return null;
  } on PageParityApiException catch (error) {
    final String message = error.message.trim();
    return message.isEmpty ? '同意没有保存成功，请重试' : message;
  } on DioException catch (_) {
    return '网络连接失败，请重试';
  }
}
