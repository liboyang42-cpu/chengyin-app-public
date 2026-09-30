import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_finance.dart';
import '../../data/models/coop_mybiz.dart';
import '../merchant/merchant_money.dart';
import 'coop_guard.dart';

@immutable
class CoopSettlementRef {
  const CoopSettlementRef({required this.source, required this.recordId});

  final String source;
  final String recordId;

  @override
  bool operator ==(Object other) =>
      other is CoopSettlementRef &&
      other.source == source &&
      other.recordId == recordId;

  @override
  int get hashCode => Object.hash(source, recordId);
}

class CoopSettlementDetail {
  const CoopSettlementDetail.merchant(this.merchant) : finance = null;
  const CoopSettlementDetail.finance(this.finance) : merchant = null;

  final CoopSettlementRow? merchant;
  final CoopFinanceRow? finance;
}

final coopSettlementDetailProvider = FutureProvider.autoDispose
    .family<CoopSettlementDetail, CoopSettlementRef>((ref, key) async {
      if (key.recordId.isEmpty) throw Exception('缺少结算记录标识');
      if (key.source == 'finance') {
        final int? topicId = int.tryParse(key.recordId);
        final rows = await ref.watch(coopApiProvider).finance();
        final row = rows.where((r) => r.topicId == topicId).firstOrNull;
        if (row == null) throw Exception('这条结算记录不存在或已不可见');
        return CoopSettlementDetail.finance(row);
      }
      if (key.source != 'ledger' && key.source != 'mybiz') {
        throw Exception('结算记录来源无效');
      }
      final int? id = int.tryParse(key.recordId);
      final data = await ref.watch(coopApiProvider).myBiz();
      final rows = CoopMyBiz.fromJson(data).settlements;
      final row = rows.where((r) => r.id == id).firstOrNull;
      if (row == null) throw Exception('这条结算记录不存在或已不可见');
      return CoopSettlementDetail.merchant(row);
    });

class CoopSettlementDetailPage extends ConsumerWidget {
  const CoopSettlementDetailPage({
    super.key,
    required this.source,
    required this.recordId,
  });

  final String source;
  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const String title = '结算详情';
    const String needLogin = '登录后查看结算详情';
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final key = CoopSettlementRef(source: source, recordId: recordId);
    final async = ref.watch(coopSettlementDetailProvider(key));
    return CupertinoPageScaffold(
      // 显式给浅色底,理由见 coop_guard.dart。
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: const Text(title),
        leading: Semantics(
          label: '返回',
          button: true,
          child: CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () {
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go(
                source == 'finance'
                    ? '/coop-finance'
                    : '/merchant/ledger?view=settlement&source=coop',
              );
            },
            child: const ExcludeSemantics(child: Icon(CupertinoIcons.back)),
          ),
        ),
      ),
      child: async.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (Object error, _) => isCoopUnauthorized(error)
            ? coopLoginView(
                context,
                ref,
                navTitle: title,
                message: needLogin,
                refetch: () =>
                    ref.invalidate(coopSettlementDetailProvider(key)),
              )
            : StatusView(
                message: '结算详情没加载出来',
                sub: coopErrorSub(error),
                large: true,
                onRetry: () =>
                    ref.invalidate(coopSettlementDetailProvider(key)),
              ),
        data: (detail) => _DetailBody(detail: detail),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});
  final CoopSettlementDetail detail;

  @override
  Widget build(BuildContext context) {
    final merchant = detail.merchant;
    final finance = detail.finance;
    final title = merchant?.topicTitle ?? finance!.topicName;
    final perspective = merchant != null ? '承接分润' : '主办分润';
    final amount = merchant != null
        ? (merchant.amount == null
              ? '—'
              : '¥${merchant.amount!.toStringAsFixed(2)}')
        : (finance!.settled ? summaryMoney(finance.myIncome) : '—');
    final String status;
    if (merchant != null) {
      status = merchant.statusText;
    } else if (!finance!.settled) {
      status = '待结算';
    } else {
      final income = cny(finance.myIncome);
      if (income == null) {
        status = '金额待确认';
      } else if (double.tryParse(income) == 0) {
        status = '无需入账';
      } else {
        status = finance.myIncomeArrived ? '已入账' : '待入账';
      }
    }
    final lines = merchant != null
        ? <_DetailLine>[
            _DetailLine('收款方', merchant.payeeText),
            if (merchant.verifiedSales != null)
              _DetailLine(
                '核销销售额',
                '¥${merchant.verifiedSales!.toStringAsFixed(2)}',
              ),
            if (merchant.verifiedHeads != null)
              _DetailLine('核销人数', '${merchant.verifiedHeads} 人'),
            if (merchant.shareRuleText != null)
              _DetailLine('分润方式', merchant.shareRuleText!),
            _DetailLine('我的分润', amount, strong: true),
          ]
        : <_DetailLine>[
            if (finance!.totalSales != null)
              _DetailLine('总销售额', summaryMoney(finance.totalSales)),
            if (finance.verifiedSales != null)
              _DetailLine('核销销售额', summaryMoney(finance.verifiedSales)),
            if (finance.platformAmount != null)
              _DetailLine('平台服务费', summaryMoney(finance.platformAmount)),
            if (finance.merchantTotal != null)
              _DetailLine('商家应收', summaryMoney(finance.merchantTotal)),
            _DetailLine('我的分润', amount, strong: true),
          ];
    final timeline = merchant != null
        ? _merchantTimeline(merchant)
        : _financeTimeline(finance!, status);
    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          perspective,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: CyPalette.of(context).textTertiary,
                              ),
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CyTokens.space3),
                  CyTag(label: status),
                ],
              ),
              const SizedBox(height: CyTokens.space5),
              Text(
                '我的分润',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
              const SizedBox(height: CyTokens.space1_5),
              Text(
                amount,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const CySectionTitle('金额分解'),
              const SizedBox(height: CyTokens.space2),
              for (var i = 0; i < lines.length; i++) ...<Widget>[
                _AmountRow(line: lines[i]),
                if (i != lines.length - 1)
                  // 分隔线交给系统语义色(§3.6 分工);`Divider` 是 Material 件。
                  Container(
                    height: 1,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space5),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const CySectionTitle('结算进度'),
              const SizedBox(height: CyTokens.space2),
              for (var i = 0; i < timeline.length; i++)
                _TimelineRow(
                  event: timeline[i],
                  isLast: i == timeline.length - 1,
                ),
            ],
          ),
        ),
        const SizedBox(height: CyTokens.space5),
      ],
    );
  }
}

class _DetailLine {
  const _DetailLine(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;
}

class _TimelineEvent {
  const _TimelineEvent(this.label, this.value);

  final String label;
  final String value;
}

String _dateText(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return '';
  return text.length > 16 ? text.substring(0, 16) : text;
}

List<_TimelineEvent> _merchantTimeline(CoopSettlementRow row) {
  final events = <_TimelineEvent>[
    if (_dateText(row.createTime).isNotEmpty)
      _TimelineEvent('结算记录已创建', _dateText(row.createTime)),
    if (_dateText(row.settleTime).isNotEmpty)
      _TimelineEvent('合作已结算', _dateText(row.settleTime)),
  ];
  switch (row.status) {
    case 0:
      final payable = _dateText(row.payableTime);
      events.add(
        payable.isEmpty
            ? const _TimelineEvent('等待入账', '时间待确认')
            : _TimelineEvent('预计入账', payable),
      );
    case 1:
      final paid = _dateText(row.payoutTime);
      events.add(_TimelineEvent('已入余额', paid.isEmpty ? '到账时间待确认' : paid));
    case 2:
      final updated = _dateText(row.updateTime);
      events.add(_TimelineEvent('结算已作废', updated.isEmpty ? '时间待确认' : updated));
    default:
      if (events.isEmpty) {
        events.add(const _TimelineEvent('结算状态待确认', '请稍后刷新'));
      }
  }
  return events;
}

List<_TimelineEvent> _financeTimeline(CoopFinanceRow row, String status) {
  final events = <_TimelineEvent>[
    _TimelineEvent(row.settled ? '主题已结算' : '主题待结算', '当前状态'),
  ];
  switch (status) {
    case '已入账':
      events.add(const _TimelineEvent('我的分润已入账', '已到账'));
    case '待入账':
      events.add(const _TimelineEvent('我的分润待入账', '等待到账'));
    case '无需入账':
      events.add(const _TimelineEvent('本期无需入账', '分润为 0'));
  }
  final payable = _dateText(row.merchantPayableTime);
  if (payable.isNotEmpty) {
    events.add(_TimelineEvent('商家应收可入账', payable));
  }
  final paid = _dateText(row.merchantPayoutTime);
  if (paid.isNotEmpty) {
    events.add(_TimelineEvent('商家应收已打款', paid));
  }
  return events;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: child,
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.line});

  final _DetailLine line;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              line.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space4),
          Text(
            line.value,
            textAlign: TextAlign.right,
            style:
                (line.strong
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(
                      fontWeight: line.strong ? FontWeight.w700 : null,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast});

  final _TimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: CyTokens.space3,
            child: Column(
              children: <Widget>[
                const SizedBox(height: CyTokens.space2),
                Container(
                  width: CyTokens.space2,
                  height: CyTokens.space2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CyPalette.of(context).textPrimary,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: CyPalette.of(context).borderSubtle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: CyTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    event.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    event.value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
