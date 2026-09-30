import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/role_provider.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/asset_record.dart';
import '../../data/models/funds_stages.dart';
import '../../core/theme/cy_tokens.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../withdrawal/withdrawal_contact_dialog.dart';

/// 积分流水列表(`/api/points/list`)。
final pointsListProvider = FutureProvider.autoDispose<List<PointsRecord>>((
  ref,
) {
  return ref.watch(assetApiProvider).pointsList();
});

/// 余额流水列表(`/api/balance/list`)。
final balanceListProvider = FutureProvider.autoDispose<List<BalanceRecord>>((
  ref,
) {
  return ref.watch(assetApiProvider).balanceList();
});

/// 余额三段(待结算 / 客诉期中 / 可提现,涉诉单列)。
///
/// ★ 与流水分开成两条取数:三段读不出来只让**这一段**说「取不到」,
///   不把整页流水一起打成错误态 —— 两件事坏起来互不相干。
final walletStagesProvider = FutureProvider.autoDispose<FundsStages?>((ref) {
  return ref.watch(assetApiProvider).walletStages();
});

/// 资产明细页:积分 / 余额两 Tab 流水。从「我的」成长卡点入。
class AssetsPage extends ConsumerWidget {
  const AssetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 游客深链 `/assets` 落地给页内登录门,不再被路由静默弹回 /feed
    //   (#276 P1-1,同 b1-sim-coupon P1-1 / roam #208 范式);路由侧已放行
    //   这一条。游客也短路掉注定 401 的流水请求。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('资产明细')),
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: StatusView(
              key: const Key('assets-login-gate'),
              message: '登录后查看资产明细',
              sub: '积分与余额流水记在账号里，登录完就能看到。',
              icon: Icons.lock_outline,
              large: true,
              retryLabel: '去登录',
              onRetry: () => requireLogin(context, ref),
            ),
          ),
        ),
      );
    }
    return const _AssetsLedger();
  }
}

class _AssetsLedger extends ConsumerStatefulWidget {
  const _AssetsLedger();

  @override
  ConsumerState<_AssetsLedger> createState() => _AssetsLedgerState();
}

class _AssetsLedgerState extends ConsumerState<_AssetsLedger> {
  int _selectedTab = 0;

  /// 回退档(`CupertinoSlidingSegmentedControl`)只给选中项加粗、**不翻转前景色**
  /// —— 白色滑块上不压成 `actionPrimaryFg` 就是白字压白底,选中项直接消失
  /// (票夹 #307 同款裁决)。段内不加纵向内边距,高度交给控件自己。
  Widget _segmentLabel(String label, {required bool selected}) {
    final CyPalette palette = CyPalette.of(context);
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: selected ? palette.actionPrimaryFg : palette.textPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // owner-guard:流水是账号私产,静默换号后旧列表不许留在屏上。
    ref.listen(authControllerProvider, (AuthState? prev, AuthState next) {
      if ((prev?.user?.id ?? -1) != (next.user?.id ?? -2)) {
        ref.invalidate(pointsListProvider);
        ref.invalidate(balanceListProvider);
        ref.invalidate(roleInfoProvider);
      }
    });

    final CyPalette palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('资产明细')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space4,
                    vertical: CyTokens.space2,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<int>(
                      groupValue: _selectedTab,
                      // 回退档取语义色,不用控件自带的系统默认底/滑块
                      // (票夹 #307 实证:白色滑块上不压前景色,选中项白压白直接消失)。
                      backgroundColor: palette.bgSurfaceSubtle,
                      thumbColor: palette.actionPrimaryBg,
                      children: <int, Widget>{
                        0: _segmentLabel('积分', selected: _selectedTab == 0),
                        1: _segmentLabel('余额', selected: _selectedTab == 1),
                      },
                      onValueChanged: (int? next) {
                        if (next == null || next == _selectedTab) return;
                        setState(() => _selectedTab = next);
                      },
                    ),
                  ),
                ),
              ),
              // ★ 两个入口放正文不放导航栏:否则标题被顶偏,
              //   读起来像三个 tab 而不是标题+动作。
              const _MoreEntries(),
              Expanded(
                child: IndexedStack(
                  index: _selectedTab,
                  children: const <Widget>[_PointsTab(), _BalanceTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PointsTab extends ConsumerWidget {
  const _PointsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(pointsListProvider);
    return records.when(
      loading: () => const CySkeleton(type: CySkeletonType.list, count: 4),
      error: (Object err, StackTrace st) => StatusView(
        message: '积分流水加载失败',
        sub: '网络可能不稳定，数据还在',
        icon: CupertinoIcons.exclamationmark_triangle,
        scrollable: true,
        onRetry: () => ref.invalidate(pointsListProvider),
      ),
      data: (List<PointsRecord> list) {
        if (list.isEmpty) {
          // 空态≠失败:不给「重试」(那是错误态的动作),只说怎么才会有。
          return const StatusView(
            message: '还没有积分流水',
            sub: '产生积分后，流水会显示在这里',
            icon: Icons.toll_outlined,
            scrollable: true,
          );
        }
        return _RecordListCard(
          onRefresh: () async => ref.invalidate(pointsListProvider),
          tiles: list
              .map(
                (r) => _RecordTile(
                  reason: r.changeReason,
                  time: r.createTime,
                  amountText: _signed(r.changePoints.toDouble(), r.isIncome),
                  afterText: '余 ${r.afterPoints}',
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _BalanceTab extends ConsumerWidget {
  const _BalanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(balanceListProvider);
    return Column(
      children: <Widget>[
        const _FundsStagesBlock(),
        Expanded(
          child: records.when(
            loading: () =>
                const CySkeleton(type: CySkeletonType.list, count: 4),
            error: (Object err, StackTrace st) => StatusView(
              message: '余额流水加载失败',
              sub: '网络可能不稳定，数据还在',
              icon: CupertinoIcons.exclamationmark_triangle,
              scrollable: true,
              onRetry: () => ref.invalidate(balanceListProvider),
            ),
            data: (List<BalanceRecord> list) {
              if (list.isEmpty) {
                // 空态≠失败:不给「重试」(那是错误态的动作),只说怎么才会有。
                return const StatusView(
                  message: '还没有余额流水',
                  sub: '产生余额变动后，流水会显示在这里',
                  icon: Icons.account_balance_wallet_outlined,
                  scrollable: true,
                );
              }
              return _RecordListCard(
                onRefresh: () async => ref.invalidate(balanceListProvider),
                tiles: list
                    .map(
                      (r) => _RecordTile(
                        reason: r.changeReason,
                        time: r.createTime,
                        amountText: _signed(r.changeBalance, r.isIncome),
                        afterText: '余 ${_money(r.afterBalance)}',
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 余额三段(`POST /api/wallet/stages`)。对齐小程序
/// `components/cy/funds-stages`:待结算(活动未结束)→ 客诉期中(X月X日可提现)
/// → 客诉处理中(涉诉单列)→ 可提现;后端说费率算不出时如实加一句提示。
///
/// ★ 口径是「如实」:金额 ≤ 0 的那几段不画(小程序 `wx:if` 同一判据),
///   但**读不到**(字段缺失 / 坏回执)是另一回事 —— 只说这一块「取不到」,
///   绝不画成 ¥0.00。
class _FundsStagesBlock extends ConsumerWidget {
  const _FundsStagesBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<FundsStages?> stages = ref.watch(walletStagesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space4,
        CyTokens.space4,
        0,
      ),
      child: stages.when(
        loading: () => const CySkeleton(type: CySkeletonType.card, count: 1),
        error: (Object err, StackTrace st) => _unavailable(context, ref),
        data: (FundsStages? value) => value == null
            ? _unavailable(context, ref)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (value.pending.isNotEmpty)
                    _row(context, '待结算（活动未结束）', value.pending),
                  for (final FundsStageComplaint item in value.complaintPeriod)
                    _row(context, item.label, item.amountText),
                  if (value.disputed.isNotEmpty)
                    _row(context, '客诉处理中', value.disputed),
                  _row(context, '可提现', value.withdrawable, strong: true),
                  if (!value.amountsKnown) ...<Widget>[
                    const SizedBox(height: CyTokens.space2),
                    Text(
                      '部分未到账金额暂时算不出，以结算到账为准',
                      key: const Key('assets-stages-unknown-note'),
                      style: TextStyle(
                        fontSize: CyTokens.typeCaption,
                        color: CyPalette.of(context).textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String amount, {
    bool strong = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ),
          const SizedBox(width: CyTokens.space2),
          Text(
            '¥$amount',
            key: Key('assets-stages-$label'),
            style: TextStyle(
              fontSize: CyTokens.typeLabel,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: CyPalette.of(context).textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// 取不到:整块只报一句,给「重试」—— 与小程序 `.fs` 的错误态同一处置。
  Widget _unavailable(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '未到账金额暂时取不到',
              key: const Key('assets-stages-unavailable'),
              style: TextStyle(
                fontSize: CyTokens.typeLabel,
                color: CyPalette.of(context).textSecondary,
              ),
            ),
          ),
          CupertinoButton(
            key: const Key('assets-stages-retry'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: () => ref.invalidate(walletStagesProvider),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

/// 流水分组卡:与上方入口卡同一套 inset grouped 语法(同圆角、同内缩
/// 分隔线、同底色),整页只剩一种列表观感。
/// `clipBehavior` 顺带把行按压高亮的直角裁成圆角。
class _RecordListCard extends StatelessWidget {
  const _RecordListCard({required this.onRefresh, required this.tiles});

  final Future<void> Function() onRefresh;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final List<Widget> rows = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) rows.add(_RecordSeparator(palette: p));
      rows.add(tiles[i]);
    }
    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.space4),
        children: <Widget>[
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.bgSurface,
              borderRadius: BorderRadius.circular(CyTokens.radiusMd),
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

/// 去掉无意义小数尾(整数显示整数,有小数最多两位)。
String _money(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}

/// 带符号金额:收入前缀 +,支出按原值(后端已带负号则不重复)。
String _signed(double v, bool isIncome) {
  final s = _money(v.abs());
  return isIncome ? '+$s' : '-$s';
}

/// 单条流水:原因 + 时间(左),变动值 + 变动后(右)。
class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.reason,
    required this.time,
    required this.amountText,
    required this.afterText,
  });

  final String reason;
  final String time;
  final String amountText;
  final String afterText;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return CyCell(
      // 行本体交给共用件 CyCell(系统 CupertinoListTile):行标题走 iOS
      // Body 17 阶梯、副标题 Caption1,不再自绘 Material bodyMedium(14)。
      title: reason.isEmpty ? '—' : reason,
      subtitle: time,
      showChevron: false,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            amountText,
            // ★ 黑白系:金额不上色(收入/支出靠 +/− 号与「余 X」表达)。
            //   ⚠️ 这是**列表项**不是 hero 卡,用 card-title(16)不是 display(28)——
            //   28pt 会把右列撑开、挤压左侧的原因文案。
            //   小程序金额档是 font-subtitle(32rpx→16)/700。
            //   tabular 防数字换位抖动。
            style: TextStyle(
              fontSize: CyTokens.typeCardTitle,
              height: 1.15,
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            afterText,
            style: TextStyle(
              fontSize: CyTokens.typeCaption,
              color: p.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 流水行分隔线:iOS 列表惯例左端对齐正文起点(行内 CyCell 的
/// `space3` 横垫),右缘通到边。
class _RecordSeparator extends StatelessWidget {
  const _RecordSeparator({required this.palette});

  final CyPalette palette;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: CyTokens.space3,
      color: palette.borderSubtle,
    );
  }
}

class _MoreEntries extends ConsumerWidget {
  const _MoreEntries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool canWithdraw =
        ref.watch(roleInfoProvider).asData?.value.can('withdrawable') == true;
    final CyPalette p = CyPalette.of(context);
    // 4 个入口合并为一张 inset grouped 分组卡(iOS 设置/钱包观感):
    // 行与行用组内分隔线,不再每行自成一卡(那是 web 卡片风)。
    // 入口数量/顺序/目标不变(§7.1-2);「提现记录」仍不随 withdrawable 隐藏。
    final List<Widget> rows = <Widget>[
      _Entry(
        key: const Key('assets-income-entry'),
        icon: CupertinoIcons.chart_bar_alt_fill,
        label: '收益明细',
        onTap: () => context.push('/income'),
      ),
      _Entry(
        key: const Key('assets-invite-entry'),
        icon: CupertinoIcons.person_2_fill,
        label: '邀请记录',
        onTap: () => context.push('/invites'),
      ),
      if (canWithdraw)
        _Entry(
          key: const Key('assets-withdrawal-entry'),
          icon: CupertinoIcons.money_dollar_circle_fill,
          label: '提现',
          // ★ R10(收款模型过渡期):提现不再进银行卡表单,
          //   点一下就是客服微信号弹窗 —— 这里**不发任何提现请求**。
          onTap: () => showWithdrawalContactDialog(context),
        ),
      _Entry(
        key: const Key('assets-withdrawal-records-entry'),
        icon: CupertinoIcons.doc_text_fill,
        label: '提现记录',
        // 真源 earnings 卡的第三个动作(scene-asset-earnings
        // openWithdrawHistory),不随 withdrawable 隐藏 ——
        // 历史里「提现失败,金额已退回」这类资金关键状态,
        // 资格变了也要查得到(B1 真跑报告 P1-2:此前全仓零入口)。
        onTap: () => context.push('/withdrawal-records'),
      ),
    ];
    final List<Widget> children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        // 组内分隔线左端对齐标题文字(space3 垫 + 16 图标 + space3 距)。
        children.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: CyTokens.space3 * 2 + 16,
            color: p.borderSubtle,
          ),
        );
      }
      children.add(rows[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.space4,
        CyTokens.space3,
        CyTokens.space4,
        0,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    // 行本体收口共用件 CyCell(系统 CupertinoListTile):44pt 行高下限、
    // 按压高亮、disclosure 箭头语义色全部走系统,不再自绘。
    return CyCell(
      title: label,
      leading: Icon(icon, size: 16, color: p.textSecondary),
      onTap: onTap,
    );
  }
}
