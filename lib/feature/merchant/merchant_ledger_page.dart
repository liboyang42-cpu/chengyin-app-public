import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import 'merchant_money.dart';
import 'merchant_error_view.dart';
import '../../data/models/merchant_ledger.dart';
import 'merchant_settlement_view.dart';

/// 台账筛选。取值与后端约定,前端只透传。
const List<(String, String)> kLedgerFilters = <(String, String)>[
  ('all', '全部'),
  ('pending', '待结算'),
  ('settled', '已结算'),
];

/// 按筛选取核销记录。★ family 参数就是筛选值 —— Riverpod 3 已移除 StateProvider,
/// 用 family + 页内 setState 比另造一个状态容器简单,也不引入新模式。
final merchantRedemptionsProvider = FutureProvider.autoDispose
    .family<MerchantRedemptionPage, String>((ref, String filter) {
      return ref.watch(merchantApiProvider).redemptions(filter: filter);
    });

/// 「退款售后」入口的能力位(小程序 `merchantAccess.canReadAftercare`)。
/// 读不到 = 没有这个入口,不挡台账本体 —— 能力位查不动不该顺带把账也锁上。
final merchantAftercareEntryProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final MerchantAccess access = await ref.watch(merchantApiProvider).access();
  return access.canReadAftercare;
});

/// 商家台账。对齐小程序 `pages/merchant/ledger`。
///
/// ★ 这一页只读。**前端一个金额都不算** —— 后端注释写死了:
///   「这份聚合必须在服务端算:前端只拿得到当前页 rows,对它求和分页后必错,
///   而且错得静默」。汇总条三个数全部用后端下发的值。
class MerchantLedgerPage extends ConsumerStatefulWidget {
  const MerchantLedgerPage({super.key, this.initialView = 'redemption'});

  final String initialView;

  @override
  ConsumerState<MerchantLedgerPage> createState() => _MerchantLedgerPageState();
}

class _MerchantLedgerPageState extends ConsumerState<MerchantLedgerPage> {
  String _filter = 'all';

  /// 'redemption' 核销记录 / 'settlement' 结算。
  /// ★ 小程序 pages/merchant/ledger 是双视图,App 此前只有前一半 ——
  ///   商家看得到核销、看不到钱去哪了。
  late String _view;

  @override
  void initState() {
    super.initState();
    // 未知 view 不能触发不存在的资金视图，收敛到冷路由默认值。
    _view = widget.initialView == 'settlement' ? 'settlement' : 'redemption';
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('台账')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CyTokens.pageX,
                  CyTokens.space2,
                  CyTokens.pageX,
                  0,
                ),
                child: CyTabs(
                  tabs: const <CyTab>[
                    CyTab(key: 'redemption', label: '核销记录'),
                    CyTab(key: 'settlement', label: '结算'),
                  ],
                  active: _view,
                  onChanged: (String k) => setState(() => _view = k),
                ),
              ),
              if (_view == 'settlement')
                const Expanded(child: MerchantSettlementView())
              else ...<Widget>[
                // 小程序 `pages/merchant/ledger` 的「退款售后」卡:只在有
                // merchant:aftercare:read 时出现,位置在筛选条上方。
                if (ref.watch(merchantAftercareEntryProvider).value == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CyTokens.pageX,
                      CyTokens.space2,
                      CyTokens.pageX,
                      0,
                    ),
                    child: CyCell(
                      key: const Key('merchant-aftercare-entry'),
                      title: '退款售后',
                      subtitle: '查询退款申请，追加商家意见与凭证',
                      minHeight: 64,
                      onTap: () => context.push('/merchant/aftercare'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CyTokens.pageX,
                    CyTokens.space2,
                    CyTokens.pageX,
                    0,
                  ),
                  // ★ 原来用的是 Material `ChoiceChip` —— 自带青绿选中底和一个对勾,
                  //   那是 Material 默认皮,不是城瘾设计系统的东西(基准图里一眼看出来
                  //   它和相邻页的分段栏完全不是一套)。改用 CyTabs chip 变体。
                  child: CyTabs(
                    variant: CyTabsVariant.chip,
                    tabs: kLedgerFilters
                        .map(
                          ((String, String) f) => CyTab(key: f.$1, label: f.$2),
                        )
                        .toList(),
                    active: filter,
                    onChanged: (String k) => setState(() => _filter = k),
                  ),
                ),
                Expanded(
                  child: ref
                      .watch(merchantRedemptionsProvider(filter))
                      .when(
                        loading: () =>
                            const Center(child: CupertinoActivityIndicator()),
                        error: (Object e, _) => merchantErrorView(
                          context,
                          e,
                          what: '结算',
                          onRetry: () => ref.invalidate(
                            merchantRedemptionsProvider(filter),
                          ),
                        ),
                        data: (MerchantRedemptionPage page) =>
                            RefreshIndicator.adaptive(
                              onRefresh: () async => ref.invalidate(
                                merchantRedemptionsProvider(filter),
                              ),
                              child: ListView(
                                padding: const EdgeInsets.all(CyTokens.pageX),
                                children: <Widget>[
                                  _SummaryBar(summary: page.summary),
                                  const SizedBox(height: CyTokens.space3),
                                  if (page.rows.isEmpty)
                                    const StatusView(
                                      message: '这个筛选下没有记录',
                                      sub: '换个筛选,或等有顾客到店核销后再来看',
                                    )
                                  else
                                    ...page.rows.map(
                                      (MerchantRedemption r) =>
                                          _RedemptionTile(row: r),
                                    ),
                                ],
                              ),
                            ),
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});
  final MerchantRedemptionSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget kv(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(value, style: textTheme.titleMedium),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本月',
            style: textTheme.bodySmall?.copyWith(
              color: CyPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Row(
            children: <Widget>[
              kv('核销', '${summary.count} 单'),
              // 两个金额都走 summaryMoney:后端没下发就显破折号,不冒充 ¥0.00。
              kv('待结算', summary.pendingDisplay),
              kv('已到账', summary.arrivedDisplay),
            ],
          ),
        ],
      ),
    );
  }
}

class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({required this.row});
  final MerchantRedemption row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = <String?>[
      row.topicName,
      row.chapterName,
    ].where((String? s) => s != null && s.isNotEmpty).join(' · ');

    // ★ 整行可点进核销详情。台账上只有一个数,商家看到「—」或「¥0.00」
    //   时唯一的追问是"为什么" —— 详情页存在的意义就是回答它。
    //   recordKey 拆不出 type/id 时不给点击(而不是拿个默认 id 去查,
    //   那会得到「记录不可见」,看着像权限问题其实是解析错了)。
    final String? type = row.recordType;
    final String? id = row.recordId;

    final Widget card = Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space2),
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
                  title.isEmpty ? '核销记录' : title,
                  style: textTheme.titleSmall,
                ),
              ),
              Text(
                row.amountDisplay,
                style: textTheme.titleMedium?.copyWith(
                  color: switch (row.amountTone) {
                    AmountTone.positive => AppColors.success,
                    AmountTone.negative => AppColors.danger,
                    // 金额还不成立(「—」/「待定」)—— 压成次要色,别和真金额抢注意力
                    // 小程序 .fin-row__v--mute 用的是 **placeholder** 不是 disabled
                    // (merchant-finance.wxss:42)。disabled 在白底上 1.9:1,肉眼近乎消失。
                    AmountTone.mute => CyPalette.of(context).textPlaceholder,
                  },
                  // 金额成列时不等宽会左右跳动,小程序那边同样开了 tabular-nums
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                  fontWeight: row.amountTone == AmountTone.mute
                      ? FontWeight.w500
                      : FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  <String?>[
                    row.storeName,
                    row.customerDisplayName,
                    if ((row.verificationCodeTail ?? '').isNotEmpty)
                      '码尾 ${row.verificationCodeTail}',
                  ].where((String? s) => s != null && s.isNotEmpty).join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CyTag(label: row.stateText),
            ],
          ),
          // ★ 退款中必须显著标出 —— 不标的话商家会把已退的算进收入。
          if (row.refunding)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                '退款处理中',
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).statusWarning,
                ),
              ),
            ),
        ],
      ),
    );

    if (type == null || id == null) return card;
    void open() => GoRouter.of(context).push('/merchant/redemption/$type/$id');
    return Semantics(
      button: true,
      label: <String>[
        title.isEmpty ? '核销记录' : title,
        row.amountDisplay,
        row.stateText,
      ].join('，'),
      onTap: open,
      excludeSemantics: true,
      child: CupertinoButton(
        onPressed: open,
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: card,
        ),
      ),
    );
  }
}
