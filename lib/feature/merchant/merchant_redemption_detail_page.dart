import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/merchant_finance.dart';
import 'finance_state_text.dart';
import 'finance_timeline_row.dart';

/// 单笔核销详情。台账里点一行进来。
///
/// ★ 这一页存在的意义是**解释那个金额**:台账上只有一个数,
///   商家看到「—」或「¥0.00」时唯一的追问是"为什么"。
///   所以零现金原因、结算状态、结算路径必须都在这里说清。
///
/// 结构 1:1 跟小程序 `pages/merchant/ledger/order-detail`:
///   卡1 hero(金额 + 状态徽标 + 计提/时间/退款/去向))
///   卡2 结算进度时间线(只有走章节供给的结算才画)
///   两态空页(缺参 / 记录不可见)+ 老数据可看时的 refreshing / stale-error。
final merchantRedemptionDetailProvider = FutureProvider.autoDispose
    .family<MerchantRedemptionView, ({String recordType, String recordId})>((
      ref,
      arg,
    ) {
      return ref
          .read(merchantApiProvider)
          .redemptionDetail(recordId: arg.recordId, recordType: arg.recordType);
    });

class MerchantRedemptionDetailPage extends ConsumerWidget {
  const MerchantRedemptionDetailPage({
    super.key,
    required this.recordType,
    required this.recordId,
  });

  final String recordType;
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('核销详情')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: _body(context, ref)),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    // ★ 缺参在**页面层**判,不进网络层:没有标识就没有"重试"这一说,
    //   只有一个动作 —— 退回去重进。
    if (recordType.isEmpty || recordId.isEmpty) {
      return StatusView(
        message: '缺少核销记录标识',
        sub: '请返回核销记录列表重新进入',
        icon: CupertinoIcons.doc_text_search,
        large: true,
        scrollable: true,
        onRetry: () => Navigator.of(context).maybePop(),
        retryLabel: '返回上一页',
      );
    }

    final ({String recordType, String recordId}) key = (
      recordType: recordType,
      recordId: recordId,
    );
    final AsyncValue<MerchantRedemptionView> async = ref.watch(
      merchantRedemptionDetailProvider(key),
    );
    void reload() => ref.invalidate(merchantRedemptionDetailProvider(key));

    final MerchantRedemptionView? detail = async.value;
    if (detail == null) {
      // 加载中(且从没有过数据)= 骨架;错误才是终态。
      final Object? error = async.error;
      if (error == null) {
        return const CySkeleton(type: CySkeletonType.detail, count: 1);
      }
      return _failure(context, error, reload);
    }

    return CustomScrollView(
      slivers: <Widget>[
        CupertinoSliverRefreshControl(
          onRefresh: () => ref
              .refresh(merchantRedemptionDetailProvider(key).future)
              .catchError((Object _) => detail),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space3,
            CyTokens.pageX,
            CyTokens.space5,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              // 手里还有上次的数据时,刷新/失败都**不掀桌子** ——
              // 真源 loadState=refreshing / stale-error 就是这个意思:
              // 先说清"这块现在能不能信",再让老数据继续可读。
              if (async.isLoading) const _Notice('正在更新核销详情', '现有详情仍可查看'),
              if (async.hasError)
                _Notice(
                  '核销详情没有更新',
                  _plainMessage(async.error!),
                  onRetry: reload,
                ),
              _HeroCard(detail: detail),
              if (detail.canReadFinance) _Timeline(detail: detail),
            ],
          ),
        ),
      ],
    );
  }

  /// 没有数据时的**终态**:越权/缺记录不叫"加载失败",也不给点了没用的重试。
  Widget _failure(BuildContext context, Object error, VoidCallback onRetry) {
    final String message = _plainMessage(error);
    if (_isMissingRecord(message)) {
      return StatusView(
        message: '核销记录不可见',
        sub: '这条记录不属于当前商家,或已被移除',
        icon: CupertinoIcons.lock,
        large: true,
        scrollable: true,
        onRetry: () => Navigator.of(context).maybePop(),
        retryLabel: '返回核销列表',
      );
    }
    // 传输层失败说「网络不稳定」;网关 5xx 并到 main 上 #235 落盘的共用话术。
    return StatusView(
      message: '核销详情没加载出来',
      sub: message,
      icon: CupertinoIcons.cloud,
      large: true,
      scrollable: true,
      onRetry: onRetry,
    );
  }
}

/// 卡1:hero。唯一的"大数字" + 支撑这个数字的每一行事实。
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.detail});
  final MerchantRedemptionView detail;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final bool finance = detail.canReadFinance;
    final String? amount = detail.amountText;
    final String stateText = finance
        ? financeRedemptionStateText(
            displayState: detail.displayState,
            noCashReason: detail.noCashReason,
            settlementRoute: detail.settlementRoute,
          )
        : financeFulfillmentStateText(detail.fulfillmentState);

    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            // 有钱可读才说"我的收入" —— 没投影时说这句等于承诺了一个看不到的数。
            finance ? '${detail.titleText} · 我的收入' : detail.titleText,
            style: t.bodyMedium?.copyWith(color: p.textSecondary),
          ),
          // ★ 后端不给金额就**不画金额行**,只画"—/待定"的占位并压成次要色
          //   —— 「没有钱」和「零元」在商家眼里是两件事。
          if (finance) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              amount ?? detail.amountFallback,
              style: t.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: amount == null ? p.textPlaceholder : p.textPrimary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
          // 状态为空时**整块不画** —— 空标签会留下一个孤零零的状态点
          // (小程序 2026-08-19 E12 实拍踩过)。
          if (stateText.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: CyTag(
                label: stateText,
                tone: _variantColor(
                  p,
                  financeStateVariant(
                    canReadFinance: finance,
                    displayState: detail.displayState,
                    fulfillmentState: detail.fulfillmentState,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space3),
          _Kv('核销门店', detail.storeName ?? '门店信息待补充'),
          if (detail.accrualRuleText != null)
            _Kv('计提规则', detail.accrualRuleText!),
          if (detail.occurredAtMinute != null)
            _Kv('核销时间', detail.occurredAtMinute!),
          if (detail.refundText != null) _Kv('退款状态', detail.refundText!),
          // 走协作订单的钱落在个人账户 —— 这一行是**入口**,不是一个事实陈述。
          if (finance && detail.settlementRoute == 'COOP_ORDER')
            _KvLink(
              '结算去向',
              '个人账户 · 去我的资产',
              onTap: () => context.push('/assets'),
            ),
        ],
      ),
    );
  }

  static Color? _variantColor(CyPalette p, String variant) => switch (variant) {
    'warning' => p.statusWarning,
    'success' => p.statusSuccess,
    'danger' => p.statusDanger,
    _ => null,
  };
}

/// 卡2:结算进度。节点 = 进度,节点下小字 = 真发生过的事件时间。
class _Timeline extends StatelessWidget {
  const _Timeline({required this.detail});
  final MerchantRedemptionView detail;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final List<BatchTimelineNode> nodes = redemptionTimeline(
      settlementState: detail.settlementState,
      settlementRoute: detail.settlementRoute,
      occurredAt: detail.occurredAt,
      paidAt: detail.publicSettlementPaidAt,
    );
    // 不是章节供给的结算没有这条线 —— 画一条到不了头的进度比不画更坏。
    if (nodes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: CyTokens.space4),
        const CySectionTitle('结算进度'),
        Container(
          padding: const EdgeInsets.all(CyTokens.space4),
          decoration: BoxDecoration(
            color: p.bgSurface,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            border: Border.all(color: p.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final BatchTimelineNode n in nodes)
                FinanceTimelineRow(node: n),
            ],
          ),
        ),
      ],
    );
  }
}

/// hero 卡里的一行「标签 + 值」。值为空**不画整行**,别摆一排「—」占地方。
class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
          Expanded(child: Text(value, style: t.bodyMedium)),
        ],
      ),
    );
  }
}

/// 可点的 kv 行(结算去向)。整行都是热区,不给一个点不动的行尾箭头。
class _KvLink extends StatelessWidget {
  const _KvLink(this.label, this.value, {required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return CupertinoButton(
      onPressed: onTap,
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      child: Semantics(
        button: true,
        label: '$label，$value',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 76,
                child: Text(
                  label,
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        value,
                        style: t.bodyMedium?.copyWith(color: p.brand),
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 14,
                      color: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行无阻塞提示(刷新中 / 没更新)。不拦操作,只说清这块能不能信。
class _Notice extends StatelessWidget {
  const _Notice(this.title, this.sub, {this.onRetry});
  final String title;
  final String sub;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: t.bodySmall?.copyWith(color: p.textPrimary)),
                Text(
                  sub,
                  style: t.labelSmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            CupertinoButton(
              key: const Key('redemption-detail-retry'),
              onPressed: onRetry,
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
              minimumSize: Size.zero,
              child: Text('重试', style: t.bodySmall?.copyWith(color: p.brand)),
            ),
        ],
      ),
    );
  }
}

/// 异常原文只进日志,不上屏 —— Dio 的传输层异常自带一整段英文(502 那句尤长)。
/// 业务异常(`MerchantApiException.toString() == message`)照后端原文,那句是写给人看的。
String _plainMessage(Object error) {
  if (error is DioException) {
    debugPrint('[merchant-redemption] 核销详情加载失败: $error');
    // HTTP 非 200 但后端仍回了业务 msg(越权那类走的就是这条),原文照贴 ——
    // 判「记录不可见」要靠它,折成"服务不可用"就把越权说成故障了。
    final Object? data = error.response?.data;
    if (data is Map && data['msg'] is String) {
      final String msg = data['msg'] as String;
      if (msg.isNotEmpty) return msg;
    }
    // 有响应 = 服务端的问题,并到共用口径 #235;纯传输层失败才说「网络不稳定」。
    return _isNetworkFailure(error) ? '网络不稳定，请检查连接后重试' : '网络异常，请稍后重试';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

/// 后端的「记录不可见 / 不存在」是**越权保护**,不是"加载失败"(真源同一判据)。
bool _isMissingRecord(String message) =>
    RegExp(r'记录(?:不可见|不存在)').hasMatch(message);

/// 传输层失败才说"网络"。其余一律照后端原文 —— 把业务错误说成网络问题,
/// 用户会一直重试一个永远不会好的请求。
bool _isNetworkFailure(Object error) =>
    error is DioException &&
    (error.response == null ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout);
