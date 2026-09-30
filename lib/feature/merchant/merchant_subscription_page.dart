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
      return ref.watch(merchantApiProvider).mySubscriptions();
    });

/// 商业化能力与收费开关:`POST /api/merchant/commerce/capabilities`。
final merchantCommerceCapabilitiesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
      return ref.watch(merchantApiProvider).commerceCapabilities();
    });

/// 权益类型字典。对齐后端 `MerchantCommerceService` 的 BIZ_* 常量。
String subscriptionTypeLabel(String? type) {
  switch (type) {
    case 'premium_template':
      return '高级模板权益';
    case 'promotion_slot':
      return '推广位权益';
    case 'brand_home':
      return '品牌主页权益';
    case 'custom_event':
      return '活动定制权益';
    default:
      return type ?? '权益';
  }
}

class MerchantSubscriptionPage extends ConsumerWidget {
  const MerchantSubscriptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(merchantSubscriptionsProvider);
    final caps = ref.watch(merchantCommerceCapabilitiesProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('增值服务')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: subs.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              what: '增值服务',
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
                      const CySectionTitle('已生效的权益'),
                      const SizedBox(height: CyTokens.space2),
                      if (rows.isEmpty)
                        Text(
                          '暂时没有生效中的权益',
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
                      const CySectionTitle('能力与配额'),
                      const SizedBox(height: CyTokens.space2),
                      caps.when(
                        loading: () => const CupertinoActivityIndicator(),
                        error: (Object e, _) => Text(
                          e.toString().replaceFirst('Exception: ', ''),
                          style: TextStyle(
                            color: CyPalette.of(context).textSecondary,
                          ),
                        ),
                        data: (Map<String, dynamic> c) =>
                            _CapabilitiesCard(data: c),
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
              endDate == null ? '永久有效' : '有效期至 $endDate',
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
            if (maxUsage != null)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space1),
                child: Text(
                  '已用 ${usedCount ?? 0} / $maxUsage',
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
  const _CapabilitiesCard({required this.data});
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
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> order = await ref
          .read(merchantApiProvider)
          .createCommerceOrder(<String, dynamic>{
            'bizType': 'premium_template',
            'requestId': _requestId,
          });
      if (!mounted) return;
      final ({String text, bool isError}) outcome = await _readBackOrder(
        order,
      );
      if (!mounted) return;
      CyNativeNotice.show(context, outcome.text, isError: outcome.isError);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 建单之后**回读服务端真值**再说话,不拿「已创建订单」当成功。
  ///
  /// 真源 `pages/merchant/decor/index.js` 是一条「建单(:489)→ 拉起微信支付
  /// → 轮询终态(:435 / `utils/checkout/payment-verifier.js`)」的链。App 端
  /// **不调起微信支付**买数字权益(设计文档 `docs/ios27-design-language.md`
  /// 表 9:虚拟道具禁用,走 IAP;iOS 直接不摆购买按钮),所以这里只做
  /// 「建单 + 回读 `commerce/order/status`」,状态照原样说给用户。
  Future<({String text, bool isError})> _readBackOrder(
    Map<String, dynamic> order,
  ) async {
    final String immediate = _knownStatus(order['paymentStatus']);
    if (immediate == 'success') {
      _refreshQuota();
      return (text: '权益已到账', isError: false);
    }
    if (immediate == 'failed') {
      return (text: '订单已关闭,请重新选择权益', isError: true);
    }
    final String orderSn = (order['orderSn'] ?? '').toString();
    if (orderSn.isEmpty) {
      // 没有订单号就查不了状态 —— 说不知道,不编一个「已创建」。
      return (text: '订单已创建,但回执里没有订单号,状态待确认', isError: true);
    }
    final String status = await ref
        .read(merchantApiProvider)
        .commerceOrderStatus(orderSn);
    switch (status) {
      case 'success':
        _refreshQuota();
        return (text: '权益已到账', isError: false);
      case 'failed':
        return (text: '订单已关闭,请重新选择权益', isError: true);
      case 'pending':
        return (text: '订单已创建,尚未完成支付', isError: false);
      default:
        // 读不懂的状态是「待确认」,不是失败:说成失败会让人重复下单。
        return (text: '订单已创建,支付状态待确认', isError: true);
    }
  }

  static String _knownStatus(Object? raw) {
    final String status = (raw ?? '').toString();
    return const <String>{'success', 'pending', 'failed'}.contains(status)
        ? status
        : 'unknown';
  }

  void _refreshQuota() {
    ref.invalidate(merchantSubscriptionsProvider);
    ref.invalidate(merchantCommerceCapabilitiesProvider);
  }

  Future<void> _showUnavailableInfo() async {
    await cyConfirm(
      context,
      title: 'App 内暂不提供购买',
      content: '当前版本暂不提供高级模板权益购买。',
      confirmText: '知道了',
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
            '已用 $used / $limit(剩 $remaining)',
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
          _quota(context, '高级模板', premium),
          _quota(context, '城市据点', cityNode),
          const SizedBox(height: CyTokens.space1),
          SizedBox(
            width: double.infinity,
            child: CyNativeButton(
              onPressed: _busy
                  ? null
                  : selfCheckoutAvailable
                  ? _order
                  : _showUnavailableInfo,
              label: selfCheckoutAvailable ? '开通高级模板权益' : 'App 内暂不提供购买',
              role: CyNativeButtonRole.secondary,
              loading: selfCheckoutAvailable && _busy,
            ),
          ),
        ],
      ),
    );
  }
}
