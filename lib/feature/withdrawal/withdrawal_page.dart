import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../core/role_provider.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/profile_detail.dart';
import '../../data/models/withdrawal.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'withdrawal_contact_dialog.dart';

/// 可提现余额。★ 单独取一次而不是复用别处的缓存 ——
/// 这是资金输入,拿到的必须是**此刻**的余额。
final withdrawableBalanceProvider = FutureProvider.autoDispose<double?>((
  ref,
) async {
  final ProfileDetail me = await ref
      .watch(registrationApiProvider)
      .userDetail();
  return me.balance;
});

/// 未到账金额分段(`POST /api/wallet/stages`)。★ 与余额同口径:单独取一次,
/// 拿不到就如实说「暂时取不到」,不拿 0 冒充。
final fundsStagesProvider = FutureProvider.autoDispose<MemberFundsStages>((
  ref,
) {
  return ref.watch(withdrawalApiProvider).stages();
});

/// 提现记录。
final withdrawalRecordsProvider =
    FutureProvider.autoDispose<List<WithdrawalRecord>>((ref) {
      return ref.watch(withdrawalApiProvider).list();
    });

/// 提现。★ 2026-09-17 按 R10(收款模型过渡期)改造:
/// 不再有银行卡表单与提现风险确认,这一页**不发起任何提现请求**;
/// 「提现」的落点统一是客服微信号弹窗(见 [showWithdrawalContactDialog]),
/// 由双方线下结算。真源见交接文档 R10。
class WithdrawalPage extends ConsumerWidget {
  const WithdrawalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 游客深链落地时给页内登录门,而不是静默撞 401 停在
    //   「提现资格暂时无法确认」(B1 模拟器报告 P1-3,修法同 roam #208)——
    //   这一挡在前,注定失败的 /api/role/info 根本不发;
    //   也刻意不自动弹登录 sheet,冷启动深链直接盖一层弹窗同样像「链接坏了」。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('提现')),
        child: SafeArea(
          child: StatusView(
            key: const Key('withdrawal-login-gate'),
            message: '登录后办理提现',
            sub: '余额与提现记录都挂在账号里,登录完就能看。',
            icon: CupertinoIcons.lock,
            large: true,
            retryLabel: '去登录',
            onRetry: () async {
              // 登录态一变,这个分支自然让位给提现正文。
              await requireLogin(context, ref);
            },
          ),
        ),
      );
    }
    final roleAsync = ref.watch(roleInfoProvider);
    final bool? withdrawable = roleAsync.asData?.value.can('withdrawable');
    if (withdrawable != true) {
      // 登录态被后端以 401 拒绝 = token 失效,不是故障:给人话 + 就地重登,
      // 「重试」在这里是一条永远好不了的死路(判据 [isUnauthorizedError])。
      final bool authExpired =
          roleAsync.hasError && isUnauthorizedError(roleAsync.error!);
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('提现')),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(CyTokens.pageX),
              child: roleAsync.isLoading
                  ? const CupertinoActivityIndicator()
                  : authExpired
                  ? StatusView(
                      message: '登录状态已失效，请重新登录',
                      sub: '重新登录后就能继续办理提现。',
                      large: true,
                      retryLabel: '去登录',
                      onRetry: () async {
                        if (!await requireLogin(context, ref)) return;
                        ref.invalidate(roleInfoProvider);
                      },
                    )
                  : StatusView(
                      // 同页其余状态档一样走共用件 StatusView(排版/重试药丸/
                      // 被困出口都在共用层,这里不再自绘裸文字+裸按钮)。
                      message: roleAsync.hasError ? '提现资格暂时无法确认' : '当前身份不支持提现',
                      large: true,
                      onRetry: roleAsync.hasError
                          ? () => ref.invalidate(roleInfoProvider)
                          : null,
                    ),
            ),
          ),
        ),
      );
    }
    final balanceAsync = ref.watch(withdrawableBalanceProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('提现')),
      child: SafeArea(
        // 真源页面是 flex 列,`.tx-bottom { margin-top: auto }` ——
        // 内容不足一屏时说明与 CTA 贴底,多出来时上方照常滚。
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(CyTokens.pageX),
                children: <Widget>[
                  _RecordsEntry(
                    onPressed: () => context.push('/withdrawal-records'),
                  ),
                  const SizedBox(height: CyTokens.space2),
                  _BalanceRow(
                    async: balanceAsync,
                    onRetry: () => ref.invalidate(withdrawableBalanceProvider),
                  ),
                  const SizedBox(height: CyTokens.space3),
                  // 真源 `subpackageMember/tixian/tixian.wxml:21` —— 还没到可提现的钱如实分段。
                  // 这一页顶部已有「可提现余额」,所以同屏不再重复一个可提现数
                  // (真源这里就是 `show-withdrawable="{{false}}"`)。
                  _FundsStagesBlock(
                    async: ref.watch(fundsStagesProvider),
                    onRetry: () => ref.invalidate(fundsStagesProvider),
                  ),
                  const SizedBox(height: CyTokens.space3),
                  // 真源 `.txcon_ly` 「提现方式」行:左字段名、右取值,单行。
                  _GrayRow(label: '提现方式', value: '联系平台客服,由客服协助线下处理'),
                ],
              ),
            ),
            // 真源 `.tx-bottom` 顶部 space5 呼吸后才是说明与 CTA。
            const SizedBox(height: CyTokens.space5),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CyTokens.pageX,
                0,
                CyTokens.pageX,
                CyTokens.pageX,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '提现说明',
                    style: CyType.headline.copyWith(
                      color: CyPalette.of(context).textPrimary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    '提现已改为客服协助线下处理,请添加平台客服微信核对。',
                    style: CyType.caption1.copyWith(
                      color: CyPalette.of(context).textSecondary,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space3),
                  SizedBox(
                    width: double.infinity,
                    child: CyNativeButton(
                      key: const Key('withdrawal-contact-button'),
                      onPressed: () => showWithdrawalContactDialog(context),
                      label: '联系客服提现',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页内灰底块行(真源 `.txyr` / `.txcon_ly`:input-bg-empty 底 + radius-md,
/// 单行 min-h = btn-h+space2 = 52pt,左右两端排)。
class _GrayRow extends StatelessWidget {
  const _GrayRow({required this.label, this.value, this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      constraints: const BoxConstraints(
        minHeight: CyTokens.btnH + CyTokens.space2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.inputBgEmpty,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: CyType.body.copyWith(color: palette.textPrimary),
            ),
          ),
          if (value case final note?)
            Flexible(
              child: Text(
                note,
                textAlign: TextAlign.right,
                style: CyType.body.copyWith(color: palette.textSecondary),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 「提现记录」入口(真源 `.tx-history-entry`:次级动作灰块、body w600、
/// 右箭头,min-h btn-h=44pt 触达)。
class _RecordsEntry extends StatelessWidget {
  const _RecordsEntry({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.actionSecondaryBg,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: CupertinoButton(
        key: const Key('withdrawal-records-entry'),
        onPressed: onPressed,
        minimumSize: const Size.fromHeight(CyTokens.btnH),
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.space4),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '提现记录',
                style: CyType.headline.copyWith(color: palette.textPrimary),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 余额(真源 `.txyr`:与「提现方式」同一行制,左「可提现余额」右金额)。
class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.async, required this.onRetry});

  final AsyncValue<double?> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // ★ **先判错误,再判加载**。
    //   Riverpod 的 `AsyncLoading` 可以同时带着上一次的错误
    //   (刷新时就是这个形态,实测 hasError=true 而 isLoading 也是 true),
    //   而 `.when()` 遇到它一律走 loading 分支 —— 于是行里写「加载中…」、
    //   别处同时写「余额没取到」,**同一屏两句话互相矛盾**,
    //   用户会一直等一个不会来的数字。
    //   持有错误却说还在加载,任何情况下都不对,所以这里不用 .when 的分派。
    if (async.hasError) {
      return _GrayRow(
        label: '可提现余额',
        trailing: _BalanceUnknown(palette: palette, onRetry: onRetry),
      );
    }
    return async.maybeWhen(
      data: (double? v) => _GrayRow(
        label: '可提现余额',
        // ★ 拿不到就说拿不到。这里绝不能显示 ¥0.00 ——
        //   那是在替用户陈述他的资产,而我们其实不知道。
        trailing: Text(
          v == null ? '余额没取到' : '¥${v.toStringAsFixed(2)}',
          style: v == null
              ? CyType.body.copyWith(color: palette.textSecondary)
              : CyType.headline.copyWith(color: palette.textPrimary),
        ),
      ),
      orElse: () => _GrayRow(
        label: '可提现余额',
        trailing: const Padding(
          padding: EdgeInsets.only(left: CyTokens.space2),
          child: CupertinoActivityIndicator(),
        ),
      ),
    );
  }
}

class _BalanceUnknown extends StatelessWidget {
  const _BalanceUnknown({required this.palette, required this.onRetry});

  final CyPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          '余额没取到',
          style: CyType.body.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(width: CyTokens.space2),
        // 真源 `.txyr_right`:重试是灰底药丸,命中区 44pt。
        CupertinoButton(
          key: const Key('balance-retry'),
          onPressed: onRetry,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
          borderRadius: BorderRadius.circular(CyTokens.radiusPill),
          color: palette.actionSecondaryBg,
          child: Text(
            '重试',
            style: CyType.headline.copyWith(color: palette.textPrimary),
            semanticsLabel: '重新加载可提现余额',
          ),
        ),
      ],
    );
  }
}

/// 余额三段(待结算 / 客诉期中 / 客诉处理中)。
///
/// ★ 三态都要有:加载中不摆假数字、取不到就说「未到账金额暂时取不到」+ 重试,
///   拿到就按服务端给的档如实列(0 元的档不占一行)。
/// 真源 `components/cy/funds-stages`:整块是次级动作灰底(radius-md、
/// pad 12×16、行距 space2),行左 label 右金额(label 档 12/11,C4 取色)。
class _FundsStagesBlock extends StatelessWidget {
  const _FundsStagesBlock({required this.async, required this.onRetry});

  final AsyncValue<MemberFundsStages> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    // 先判错误再判加载(与余额行同一口径):刷新时 AsyncLoading 可能带着上一次的错误。
    if (async.hasError) {
      // 真源错误档 `.fs fs-row`:同一行两端排,左说明右「重试」。
      return Semantics(
        liveRegion: true,
        child: _GrayBlock(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '未到账金额暂时取不到',
                    style: CyType.caption1.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                // 真源 `.fs-retry`:label 档(12) w600 标题色文字重试,
                // 命中区 44pt。
                CupertinoButton(
                  key: const Key('funds-stages-retry'),
                  onPressed: onRetry,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CyTokens.space2,
                  ),
                  child: Text(
                    '重试',
                    semanticsLabel: '重新加载未到账金额',
                    style: CyType.caption1.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return async.maybeWhen(
      data: (MemberFundsStages stages) => _rows(context, palette, stages),
      orElse: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: CyTokens.space2),
        child: Center(child: CupertinoActivityIndicator()),
      ),
    );
  }

  Widget _rows(
    BuildContext context,
    CyPalette palette,
    MemberFundsStages stages,
  ) {
    final List<Widget> rows = <Widget>[
      if (stages.pendingText.isNotEmpty)
        _row(context, palette, '待结算（活动未结束）', stages.pendingText),
      for (final ComplaintPeriodStage item in stages.complaintPeriod)
        _row(context, palette, item.label, item.amount.toStringAsFixed(2)),
      if (stages.disputedText.isNotEmpty)
        _row(context, palette, '客诉处理中', stages.disputedText),
    ];
    if (rows.isEmpty && stages.amountsKnown) return const SizedBox.shrink();
    return _GrayBlock(
      children: <Widget>[
        ...rows,
        if (!stages.amountsKnown)
          Text(
            '部分未到账金额暂时算不出，以结算到账为准',
            style: CyType.caption2.copyWith(color: palette.textSecondary),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    CyPalette palette,
    String label,
    String amount,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: CyType.caption1.copyWith(color: palette.textSecondary),
          ),
        ),
        const SizedBox(width: CyTokens.space2),
        Text(
          '¥$amount',
          style: CyType.caption1.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 真源 `.fs` 灰底块:次级动作底 + radius-md,pad space3×space4,行距 space2。
class _GrayBlock extends StatelessWidget {
  const _GrayBlock({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.space4,
        vertical: CyTokens.space3,
      ),
      decoration: BoxDecoration(
        color: CyPalette.of(context).actionSecondaryBg,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final Widget child in children) ...<Widget>[
            child,
            if (child != children.last) const SizedBox(height: CyTokens.space2),
          ],
        ],
      ),
    );
  }
}
