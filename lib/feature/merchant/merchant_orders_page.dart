import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import 'merchant_error_view.dart';
import 'merchant_money.dart';

/// 商家订单/异常列表:`POST /api/merchant/orders`。
final merchantOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.watch(merchantApiProvider).merchantOrders();
    });

/// 订单状态字典。对齐后端 `OmsOrder.status` 字段注释
/// (0待付款/1待发货/2已发货/3待评价/4已完成/5已关闭/6无效订单)。
/// ★ 只列出后端明确写死的六档 —— 别的数字不猜含义,原样带出编号。
String orderStatusText(int? status) {
  switch (status) {
    case 0:
      return '待付款';
    case 1:
      return '待发货';
    case 2:
      return '已发货';
    case 3:
      return '待评价';
    case 4:
      return '已完成';
    case 5:
      return '已关闭';
    case 6:
      return '无效订单';
    default:
      return status == null ? '' : '状态 $status';
  }
}

/// 售后状态字典(`OmsOrder.aftersaleStatus`:1无售后或售后关闭/2售后处理中/3退款中/4退款成功)。
/// ★ 1 是"没有售后"—— 不是 0,也不是缺席。只有 ≥2 才该显示售后标签。
String? aftersaleStatusText(int? status) {
  switch (status) {
    case 2:
      return '售后处理中';
    case 3:
      return '退款中';
    case 4:
      return '退款成功';
    default:
      return null;
  }
}

class MerchantOrdersPage extends ConsumerWidget {
  const MerchantOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantOrdersProvider);
    final Widget body = async.when(
      loading: () => const CySkeleton(type: CySkeletonType.card, count: 4),
      error: (Object e, _) => merchantErrorView(
        context,
        e,
        what: '订单',
        onRetry: () => ref.invalidate(merchantOrdersProvider),
      ),
      data: (List<Map<String, dynamic>> rows) {
        if (rows.isEmpty) {
          return StatusView(
            message: '还没有订单',
            sub: '有顾客下单后,会出现在这里',
            large: true,
            scrollable: true,
            icon: Icons.receipt_long_outlined,
          );
        }
        return RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(merchantOrdersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(CyTokens.pageX),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: CyTokens.space2),
            itemBuilder: (_, int i) => _OrderTile(order: rows[i]),
          ),
        );
      },
    );
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: const CupertinoNavigationBar(middle: Text('订单')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: body),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final String orderSn = (order['orderSn'] as String?) ?? '';
    final int? status = (order['status'] as num?)?.toInt();
    final int? aftersale = (order['aftersaleStatus'] as num?)?.toInt();
    final String? createTime = order['createTime'] as String?;
    final String amount = summaryMoney(order['payAmount']);
    final String? aftersaleLabel = aftersaleStatusText(aftersale);

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
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  orderSn.isEmpty ? '订单' : orderSn,
                  style: textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: CyTokens.space2),
              CyTag(label: orderStatusText(status)),
            ],
          ),
          const SizedBox(height: CyTokens.space1_5),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  createTime ?? '',
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
              Text(amount, style: textTheme.bodyMedium),
            ],
          ),
          if (aftersaleLabel != null) ...<Widget>[
            const SizedBox(height: CyTokens.space1_5),
            Text(
              aftersaleLabel,
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).statusWarning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
