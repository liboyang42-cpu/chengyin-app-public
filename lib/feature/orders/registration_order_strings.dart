import 'package:flutter/widgets.dart';
import '../../data/models/registration_read_failure.dart';
import '../../data/api/activity_api.dart';
import '../../data/api/club_api.dart';
import '../../data/api/page_parity_api.dart';
import '../../data/api/registration_api.dart' show RegistrationFollowFailure;
import '../../l10n/error_presentation.dart';
import '../../l10n/strings.dart';
import '../../data/models/activity.dart';

/// For known local display getters only. Backend strings must bypass this map.
String localOrderModelText(BuildContext context, String text) => switch (text) {
  '进行中' => stringsOf(context).registrationOrdersInProgress,
  '全部' => stringsOf(context).registrationOrdersAll,
  '待支付' => stringsOf(context).registrationOrdersAwaitingPayment,
  '未开始' => stringsOf(context).registrationOrdersNotStarted,
  '已完成' => stringsOf(context).registrationOrdersCompleted,
  '退款中' => stringsOf(context).registrationOrdersRefundInProgress,
  '已退款' => stringsOf(context).registrationOrdersRefunded,
  '不可退款' => stringsOf(context).registrationOrdersNonRefundable,
  '已取消' => stringsOf(context).registrationOrdersCancelled,
  '订单状态更新中' => stringsOf(context).registrationOrdersUpdatingOrderStatus,
  '退款处理中' => stringsOf(context).registrationOrdersRefundProcessing,
  '待核销' => stringsOf(context).registrationOrdersAwaitingRedemption,
  '已核销' => stringsOf(context).registrationOrdersRedeemed,
  '已失效' => stringsOf(context).registrationOrdersInvalid,
  '未知' => stringsOf(context).registrationOrdersUnknown,
  '已核验' => stringsOf(context).registrationOrdersModelVerified,
  '待使用' => stringsOf(context).registrationOrdersModelReadyToUse,
  '城市定向' => stringsOf(context).registrationOrdersModelCityOrienteering,
  '自由探索' => stringsOf(context).registrationOrdersModelFreeExploration,
  '按路线完成现场节点互动' => stringsOf(context).registrationOrdersModelCompleteOnSiteActivitiesAlongTheRoute,
  '打开票夹后开始探索' => stringsOf(context).registrationOrdersModelOpenYourTicketsToStartExploring,
  '订单已创建' => stringsOf(context).registrationOrdersModelOrderCreated,
  '支付已完成' => stringsOf(context).registrationOrdersModelPaymentCompleted,
  '订单已取消' => stringsOf(context).registrationOrdersModelOrderCancelled,
  '等待支付' => stringsOf(context).registrationOrdersModelAwaitingPayment,
  '完成后更新' => stringsOf(context).registrationOrdersModelUpdatesOnCompletion,
  '权益已核销' => stringsOf(context).registrationOrdersModelBenefitsRedeemed,
  '尚未核销' => stringsOf(context).registrationOrdersModelNotYetRedeemed,
  '等待到店核销' => stringsOf(context).registrationOrdersModelAwaitingInStoreRedemption,
  '本活动未配置候补' => stringsOf(context).registrationOrdersModelNoWaitlistConfiguredForThisActivity,
  '本场候补已关闭' => stringsOf(context).registrationOrdersModelThisSessionSWaitlistIsClosed,
  '仅俱乐部成员可候补' => stringsOf(context).registrationOrdersModelWaitlistIsForClubMembersOnly,
  '你已有该票种报名' => stringsOf(context).registrationOrdersModelYouAlreadyRegisteredForThisTicketType,
  '当前无法参与候补' => stringsOf(context).registrationOrdersModelWaitlistIsCurrentlyUnavailable,
  '候补排队中' => stringsOf(context).registrationOrdersModelOnTheWaitlist,
  '已生成报名订单' => stringsOf(context).registrationOrdersModelRegistrationOrderCreated,
  '报名已确认' => stringsOf(context).registrationOrdersModelRegistrationConfirmed,
  '已退出候补' => stringsOf(context).registrationOrdersModelLeftTheWaitlist,
  '候补名额已过期' => stringsOf(context).registrationOrdersModelWaitlistOfferExpired,
  '等待候补名额' => stringsOf(context).registrationOrdersModelWaitingForAWaitlistPlace,
  '价格待确认' => stringsOf(context).registrationOrdersPriceUnconfirmed,
  '价格已更新，请重新确认' => stringsOf(context).registrationOrdersPriceChanged,
  '订单已过期,请重新报名' => stringsOf(context).registrationOrdersOrderExpired,
  '免费' => stringsOf(context).registrationOrdersFree,
  _ => text,
};

String localizedEntitlementLabel(BuildContext context, Entitlement entitlement) =>
    entitlement.statusLabel ?? localOrderModelText(context, entitlement.label);

String registrationReadFailureSummary(BuildContext context, RegistrationReadKind kind) => switch (kind) {
  RegistrationReadKind.activityTickets => stringsOf(context).ticketWalletActivityError,
  RegistrationReadKind.routeTickets => stringsOf(context).ticketWalletRouteError,
  RegistrationReadKind.orders => stringsOf(context).registrationOrdersCouldNotLoadOrders,
  RegistrationReadKind.detail => stringsOf(context).registrationOrdersCouldNotLoadTicketDetails,
  RegistrationReadKind.dynamicCode => stringsOf(context).ticketPassIssueError,
  RegistrationReadKind.quote => stringsOf(context).registrationFallbackQuote,
  RegistrationReadKind.paymentReadiness => stringsOf(context).registrationFallbackReadiness,
  RegistrationReadKind.paymentParameters => stringsOf(context).registrationFallbackPaymentParameters,
  RegistrationReadKind.completion => stringsOf(context).registrationFallbackCompletion,
  RegistrationReadKind.cancellation => stringsOf(context).clubCheckinRefundUnknown,
};

String localizedOrderError(BuildContext context, Object error) {
  if (error is RegistrationReadFailure) {
    return presentError(error, stringsOf(context),
      fallback: registrationReadFailureSummary(context, error.kind),
      originalApiMessage: error.hasServerMessage ? error.message : null,
    ).noticeText;
  }
  if (error is PageParityApiException) {
    return presentError(error, stringsOf(context),
      fallback: error.localReason == PageParityLocalFailure.teamCreateReceipt
          ? stringsOf(context).teamApiCreateReceipt : null,
      originalApiMessage: error.isLocalFallback ? null : error.message,
    ).noticeText;
  }
  if (error is RegistrationFollowFailure) {
    return presentError(error, stringsOf(context),
      fallback: stringsOf(context).registrationFallbackFollow,
      originalApiMessage: error.originalMessage,
    ).noticeText;
  }
  return presentError(error, stringsOf(context),
    fallback: error is RegistrationCheckoutException ? stringsOf(context).registrationFallbackCheckout : null,
    originalApiMessage: error is RegistrationCheckoutException
        ? (error.hasServerMessage ? error.message : null)
        : error is ClubApiException ? (error.isLocal ? null : error.message) : legacyApiMessage(error),
  ).noticeText;
}
