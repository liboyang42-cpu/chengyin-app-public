// 收益明细页 —— 对应小程序 subpackageA/pages/assetcenter/income-detail(壳)+
// subpackageA/components/scene-asset-income-detail(正文)。
//
// 从小程序那份实现里逐条搬过来的**判断**(每一条都是它踩过的坑):
//   · changeType 是**收支方向**,不是流水状态。库里根本没有状态字段 ——
//     渲染成「已到账 / 处理中」等于每条支出恒显示「处理中」,那两个词是编的。
//   · 缺金额显示中性的「—」,**不能吃到红色**。红在这页是「支出」语义,
//     而「没有数」不是支出;缺值渲成一根红横线,在资金页上读起来像负数。
//   · 方向不能只靠颜色承载(WCAG 1.4.1)——「+¥/−¥」和「收入/支出」
//     两处都要写出来,色盲用户才读得到。
//   · 俱乐部那一档不是换个筛选参数,是另一条链路(/api/coop/finance),
//     跳去合作财务页。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/balance_detail.dart';

final incomeDetailProvider = FutureProvider.autoDispose
    .family<List<BalanceDetail>, IncomeEventFilter>((
      Ref ref,
      IncomeEventFilter f,
    ) async {
      final r = await ref
          .watch(registrationApiProvider)
          .incomeDetail(filter: f, pageSize: 50);
      return r.rows;
    });

/// 金额展示。★ 符号看 changeType,不看金额里有没有负号 ——
/// 后端存的是绝对值,自己判负号会让所有支出都显示成收入。
/// 拿不到金额返回 null,由调用方渲成中性的「—」。
String? incomeAmountText(BalanceDetail d) {
  final String raw = (d.changeBalance ?? '').trim();
  if (raw.isEmpty) return null;
  final String abs = raw.startsWith('-') ? raw.substring(1) : raw;
  return (d.isIncome ? '+¥' : '−¥') + abs;
}

/// 方向文案。★ 和颜色**并存**,不是二选一。
String incomeDirectionText(BalanceDetail d) => d.isIncome ? '收入' : '支出';

/// 日期展示格式。真源 `formatDate`(scene-asset-income-detail/index.js:12-19):
/// 今天 / 昨天 / M月D日 —— 相对日,不带时分秒。流水页看的是「哪天」,
/// 秒级精度在资金记录上没有信息量,反而把行撑满。
/// 解析不了的日期不编不藏,原样透传。
String? incomeDateText(String? raw, {DateTime? now}) {
  final String s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final DateTime? d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (d == null) return s;
  final DateTime today = now ?? DateTime.now();
  final int dayDiff = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (dayDiff == 0) return '今天';
  if (dayDiff == 1) return '昨天';
  return '${d.month}月${d.day}日';
}

class IncomeDetailPage extends ConsumerStatefulWidget {
  const IncomeDetailPage({super.key});
  @override
  ConsumerState<IncomeDetailPage> createState() => _IncomeDetailPageState();
}

class _IncomeDetailPageState extends ConsumerState<IncomeDetailPage> {
  IncomeEventFilter _filter = IncomeEventFilter.all;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('收益明细')),
      backgroundColor: p.bgPage,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Chips(
                active: _filter,
                onPick: (IncomeEventFilter f) {
                  if (f == IncomeEventFilter.club) {
                    // 俱乐部分润是另一条链路,不在本接口里。
                    context.push('/coop-finance');
                    return;
                  }
                  setState(() => _filter = f);
                },
              ),
              Expanded(child: _List(_filter)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.active, required this.onPick});
  final IncomeEventFilter active;
  final ValueChanged<IncomeEventFilter> onPick;

  @override
  Widget build(BuildContext context) {
    // ★ 用 CyTabs 不用 ChoiceChip —— Material 默认外观(选中对勾/主题色填充)
    //   与城瘾黑白系不搭,门禁 no_material_segmented 拦着。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space2),
      child: CyTabs(
        // 小程序那页用的就是 chip 档(cy-tabs variant="chip")。
        variant: CyTabsVariant.chip,
        active: active.name,
        tabs: <CyTab>[
          for (final IncomeEventFilter f in IncomeEventFilter.values)
            CyTab(key: f.name, label: f.label),
        ],
        onChanged: (String k) => onPick(
          IncomeEventFilter.values.firstWhere(
            (IncomeEventFilter f) => f.name == k,
          ),
        ),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List(this.filter);
  final IncomeEventFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BalanceDetail>> v = ref.watch(
      incomeDetailProvider(filter),
    );
    return v.when(
      // 加载态对齐真源 components/cy/scene-asset-income-detail/index.wxml:
      // `cy-skeleton type="list" count="4"`,不是转圈。
      loading: () => const CySkeleton(type: CySkeletonType.list, count: 4),
      error: (Object e, StackTrace _) => StatusView(
        message: '收益明细没加载出来',
        sub: '网络可能不稳定,你的收益记录还在',
        large: true,
        onRetry: () => ref.invalidate(incomeDetailProvider(filter)),
      ),
      data: (List<BalanceDetail> rows) => rows.isEmpty
          ? StatusView(
              // ★ 空态分两句:全部为空 = 真没有;筛出来为空 = 换个筛选看看。
              //   混成一句会让用户以为自己一分没赚。
              // ★ 空态不给重试 —— 真源的重试只挂在 cy-error 上(空态是 cy-empty),
              //   给「重试」等于承诺一个按了也不会变的出口。
              message: filter == IncomeEventFilter.all
                  ? '暂无收益记录'
                  : '当前筛选暂无收益记录',
              sub: filter == IncomeEventFilter.all
                  ? '产生收益后,明细会显示在这里'
                  : '切换其他收益类型查看记录',
              large: true,
            )
          : RefreshIndicator.adaptive(
              onRefresh: () async =>
                  ref.invalidate(incomeDetailProvider(filter)),
              child: ListView.separated(
                padding: const EdgeInsets.all(CyTokens.space4),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: CyTokens.space3),
                itemBuilder: (BuildContext c, int i) => _Row(rows[i]),
              ),
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.d);
  final BalanceDetail d;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final String? amount = incomeAmountText(d);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  (d.changeReason ?? '').trim().isEmpty
                      ? '收益记录'
                      : d.changeReason!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // 列表行标题 = iOS Headline 17 Semibold(阶梯见 CyType)。
                  style: CyType.headline.copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  // 事由 · 时间(今天/昨天/M月D日) · 方向。时间拿不到给「—」,不编。
                  '${d.eventLabel} · ${incomeDateText(d.createTime) ?? '—'} · ${incomeDirectionText(d)}',
                  // 时间戳档 = Caption1 12。
                  style: CyType.caption1.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: CyTokens.space3),
          Text(
            amount ?? '—',
            key: Key('income-amount-${d.id}'),
            // 强调行的值 = Headline 17 Semibold。
            style: CyType.headline.copyWith(
              // ★ 真源用户裁决(scene-asset-income-detail/index.wxss):
              //   入账绿、出账红,走 status 语义 token。方向不只靠颜色 ——
              //   +/− 号与「收入/支出」文案都在。
              // ★ 缺金额走中性色 —— 红是「支出」,不是「没有数」。
              color: amount == null
                  ? p.textTertiary
                  : (d.isIncome ? p.statusSuccess : p.statusDanger),
            ),
          ),
        ],
      ),
    );
  }
}
