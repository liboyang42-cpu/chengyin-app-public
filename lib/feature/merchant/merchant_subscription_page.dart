import '../../core/network/request_session_scope.dart';
import '../auth/auth_controller.dart';
import '../../core/network/session_data.dart';
import '../../data/api/merchant_api.dart';
import '../../l10n/strings.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_presentation.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import 'merchant_error_view.dart';

/// 我的付费权益:`POST /api/merchant/subscription`。空列表 = 没有生效权益,不是加载失败。
final merchantSubscriptionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      final api = ref.watch(merchantApiProvider);
      return readSessionData(ref, api.mySubscriptions);
    });

/// 商业化能力与收费开关:`POST /api/merchant/commerce/capabilities`。
final merchantCommerceCapabilitiesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
      final api = ref.watch(merchantApiProvider);
      return readSessionData(ref, () => api.commerceCapabilities());
    });

/// 权益类型字典。对齐后端 `MerchantCommerceService` 的 BIZ_* 常量。
String subscriptionTypeLabel(String? type, {AppLocalizations? strings}) {
  switch (type) {
    case 'premium_template':
      return (strings?.merchantSubscriptionPremium ?? '高级模板权益');
    case 'promotion_slot':
      return (strings?.merchantSubscriptionPromotion ?? '推广位权益');
    case 'brand_home':
      return (strings?.merchantSubscriptionBrand ?? '品牌主页权益');
    case 'custom_event':
      return (strings?.merchantSubscriptionCustomEvent ?? '活动定制权益');
    default:
      return type ?? (strings?.merchantSubscriptionEntitlement ?? '权益');
  }
}

class MerchantSubscriptionPage extends ConsumerWidget {
  const MerchantSubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionDataKeyProvider);
    if (session.loading || !session.initialized || session.userId == null) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantSubscriptionTitle)),
        child: Center(child: session.loading || !session.initialized
            ? const CupertinoActivityIndicator()
            : Text(stringsOf(context).loginTitle)),
      );
    }
    final subs = ref.watch(merchantSubscriptionsProvider);
    final caps = ref.watch(merchantCommerceCapabilitiesProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantSubscriptionTitle)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: subs.when(
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              what: stringsOf(context).merchantSubscriptionTitle,
              onRetry: () => ref.invalidate(merchantSubscriptionsProvider),
            ),
            data: (List<Map<String, dynamic>> rows) =>
                RefreshIndicator.adaptive(
                  onRefresh: () async {
                    ref.invalidate(merchantSubscriptionsProvider);
                    ref.invalidate(merchantCommerceCapabilitiesProvider);
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(CyTokens.pageX),
                    children: <Widget>[
                      CySectionTitle(stringsOf(context).merchantSubscriptionActive),
                      const SizedBox(height: CyTokens.space2),
                      if (rows.isEmpty)
                        Text(
                          stringsOf(context).merchantSubscriptionEmpty,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: CyPalette.of(context).textSecondary,
                              ),
                        )
                      else
                        ...rows.map(
                          (Map<String, dynamic> s) => _SubscriptionCard(sub: s),
                        ),
                      const SizedBox(height: CyTokens.space4),
                      CySectionTitle(stringsOf(context).merchantSubscriptionCapabilities),
                      const SizedBox(height: CyTokens.space2),
                      caps.when(
                        skipLoadingOnReload: false,
                        skipLoadingOnRefresh: false,
                        loading: () => const CupertinoActivityIndicator(),
                        error: (Object e, _) => Text(
                          presentError(e, stringsOf(context), originalApiMessage: e is MerchantApiException ? e.message : legacyApiMessage(e)).noticeText,
                          style: TextStyle(
                            color: CyPalette.of(context).textSecondary,
                          ),
                        ),
                        data: (Map<String, dynamic> c) =>
                            _CapabilitiesCard(key: ValueKey(session), data: c),
                      ),
                    ],
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.sub});
  final Map<String, dynamic> sub;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String type = subscriptionTypeLabel(
      sub['subscriptionType'] as String?,
      strings: stringsOf(context),
    );
    final Object? endDate = sub['endDate'];
    final int? maxUsage = (sub['maxUsage'] as num?)?.toInt();
    final int? usedCount = (sub['usedCount'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: CyPalette.of(context).bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: CyPalette.of(context).borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(type, style: textTheme.titleSmall),
            const SizedBox(height: CyTokens.space1),
            // endDate 缺席(NULL)在后端语义里就是"永久" —— 不是没读到。
            Text(
              endDate == null ? stringsOf(context).merchantSubscriptionPermanent : stringsOf(context).merchantSubscriptionExpires(endDate.toString()),
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
            if (maxUsage != null)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space1),
                child: Text(
                  stringsOf(context).merchantSubscriptionUsed(usedCount ?? 0, maxUsage),
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapabilitiesCard extends ConsumerStatefulWidget {
  const _CapabilitiesCard({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  ConsumerState<_CapabilitiesCard> createState() => _CapabilitiesCardState();
}

class _CapabilitiesCardState extends ConsumerState<_CapabilitiesCard> {
  bool _busy = false;
  late final String _requestId;

  @override
  void initState() {
    super.initState();
    _requestId = 'premium_template_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _order() async {
    if (_busy) return;
    final identity = ref.read(sessionDataKeyProvider);
    final owner = identity.userId;
    if (owner == null || identity.loading || !identity.initialized) return;
    final session = ref.read(authControllerProvider.notifier).requestScope(owner);
    final scope = RequestSessionScope(() => mounted &&
        ref.read(sessionDataKeyProvider) == identity && session.isCurrent());
    if (!scope.isCurrent()) return;
    final api = ref.read(merchantApiProvider);
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> order = await RequestSessionScope.run(scope,
          () => api.createCommerceOrder(<String, dynamic>{
            'bizType': 'premium_template',
            'requestId': _requestId,
          }));
      if (!scope.isCurrent()) return;
      final ({String text, bool isError})? outcome = await _readBackOrder(
        order, api, scope,
      );
      if (!scope.isCurrent() || outcome == null) return;
      CyNativeNotice.show(context, outcome.text, isError: outcome.isError);
    } catch (e) {
      if (!scope.isCurrent()) return;
      CyNativeNotice.show(
        context,
        presentError(e, stringsOf(context), originalApiMessage: e is MerchantApiException ? e.message : legacyApiMessage(e)).noticeText,
        isError: true,
      );
    } finally {
      if (scope.isCurrent()) setState(() => _busy = false);
    }
  }

  /// 建单之后**回读服务端真值**再说话,不拿「已创建订单」当成功。
  ///
  /// 真源 `pages/merchant/decor/index.js` 是一条「建单(:489)→ 拉起微信支付
  /// → 轮询终态(:435 / `utils/checkout/payment-verifier.js`)」的链。App 端
  /// **不调起微信支付**买数字权益(设计文档 `docs/ios27-design-language.md`
  /// 表 9:虚拟道具禁用,走 IAP;iOS 直接不摆购买按钮),所以这里只做
  /// 「建单 + 回读 `commerce/order/status`」,状态照原样说给用户。
  Future<({String text, bool isError})?> _readBackOrder(
    Map<String, dynamic> order,
    MerchantApi api,
    RequestSessionScope scope,
  ) async {
    if (!scope.isCurrent()) return null;
    final strings = stringsOf(context);
    final String immediate = _knownStatus(order['paymentStatus']);
    if (immediate == 'success') {
      _refreshQuota(scope);
      return (text: strings.merchantSubscriptionGranted, isError: false);
    }
    if (immediate == 'failed') {
      return (text: strings.merchantSubscriptionClosed, isError: true);
    }
    final String orderSn = (order['orderSn'] ?? '').toString();
    if (orderSn.isEmpty) {
      // 没有订单号就查不了状态 —— 说不知道,不编一个「已创建」。
      return (text: strings.merchantSubscriptionNoOrderNumber, isError: true);
    }
    final String status = await RequestSessionScope.run(scope,
        () => api.commerceOrderStatus(orderSn));
    if (!scope.isCurrent()) return null;
    switch (status) {
      case 'success':
        _refreshQuota(scope);
        return (text: strings.merchantSubscriptionGranted, isError: false);
      case 'failed':
        return (text: strings.merchantSubscriptionClosed, isError: true);
      case 'pending':
        return (text: strings.merchantSubscriptionAwaitingPayment, isError: false);
      default:
        // 读不懂的状态是「待确认」,不是失败:说成失败会让人重复下单。
        return (text: strings.merchantSubscriptionPaymentUnknown, isError: true);
    }
  }

  static String _knownStatus(Object? raw) {
    final String status = (raw ?? '').toString();
    return const <String>{'success', 'pending', 'failed'}.contains(status)
        ? status
        : 'unknown';
  }

  void _refreshQuota(RequestSessionScope scope) {
    if (!scope.isCurrent()) return;
    ref.invalidate(merchantSubscriptionsProvider);
    ref.invalidate(merchantCommerceCapabilitiesProvider);
  }

  Future<void> _showUnavailableInfo() async {
    await cyConfirm(
      context,
      title: stringsOf(context).merchantSubscriptionUnavailable,
      content: stringsOf(context).merchantSubscriptionUnavailableBody,
      confirmText: stringsOf(context).merchantSubscriptionUnderstood,
      showCancel: false,
    );
  }

  Widget _quota(BuildContext context, String label, Map<String, dynamic>? e) {
    final textTheme = Theme.of(context).textTheme;
    if (e == null) return const SizedBox.shrink();
    final int limit = (e['limit'] as num?)?.toInt() ?? 0;
    final int used = (e['used'] as num?)?.toInt() ?? 0;
    final int remaining = (e['remaining'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: textTheme.bodyMedium)),
          Text(
            stringsOf(context).merchantSubscriptionQuota(used, limit, remaining),
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? premium =
        widget.data['premiumTemplate'] as Map<String, dynamic>?;
    final Map<String, dynamic>? cityNode =
        widget.data['cityNode'] as Map<String, dynamic>?;
    final bool selfCheckoutEnabled = widget.data['selfCheckoutEnabled'] == true;
    // 高级模板是数字权益；iOS 不得把后端普通订单当成 Apple IAP。
    final bool selfCheckoutAvailable =
        selfCheckoutEnabled && defaultTargetPlatform != TargetPlatform.iOS;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _quota(context, stringsOf(context).merchantSubscriptionPremiumLabel, premium),
          _quota(context, stringsOf(context).merchantSubscriptionCityNode, cityNode),
          const SizedBox(height: CyTokens.space1),
          SizedBox(
            width: double.infinity,
            child: CyNativeButton(
              onPressed: _busy
                  ? null
                  : selfCheckoutAvailable
                  ? _order
                  : _showUnavailableInfo,
              label: selfCheckoutAvailable ? stringsOf(context).merchantSubscriptionEnable : stringsOf(context).merchantSubscriptionUnavailable,
              role: CyNativeButtonRole.secondary,
              loading: selfCheckoutAvailable && _busy,
            ),
          ),
        ],
      ),
    );
  }
}
