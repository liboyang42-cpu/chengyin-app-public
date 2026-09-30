import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club_settlement.dart';
import '../withdrawal/withdrawal_contact_dialog.dart';
import 'club_access_gate.dart';
import 'club_controller.dart';

/// G2 俱乐部分润。真源 `pages/club/settlement/index`。
///
/// ★ 金额一律服务端算好下发,前端**不做任何金额运算**,也绝不用假数字填充。
///   缺字段 / 类型不对由 [ClubSettlementSummary] 整块拒收 → 走 error 态。
///
/// ★★ 提现按 **R10**(收款模型定稿 2026-09-15,用户 09-16 拍板)走:
///   入口只弹客服微信号 + 「返回」「复制」,不进银行卡表单、不做风险确认、
///   **不在这页发任何请求**。`POST /api/club/settlement/withdraw` 后端仍在,
///   App 侧故意不封装(见 `club_crm_api.dart` 同一处注释)—— 提现只有
///   一条动钱的路径,这里再开一条就是两套账。
///   ★ 弹窗**不在这页自己实现**:调 `showWithdrawalContactDialog`
///   (App 侧唯一出口、唯一微信号来源),文案与号都只有一处。
class ClubSettlementPage extends ConsumerWidget {
  const ClubSettlementPage({super.key, required this.clubId});

  final int clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget child;
    if (clubId <= 0) {
      child = StatusView(
        message: '结算数据暂不可用',
        sub: '缺少俱乐部 ID',
        icon: CupertinoIcons.exclamationmark_circle,
        large: true,
        onRetry: () => _goBack(context),
        retryLabel: '返回',
      );
    } else {
      final gate = evaluateClubAccess(
        ref.watch(clubAccessProvider(clubId)),
        clubId: clubId,
        permission: kClubFinanceRead,
      );
      final summary = ref.watch(clubSettlementSummaryProvider(clubId));
      child = switch (gate.decision) {
        ClubAccessDecision.deny => StatusView(
          message: '分润数据不可见',
          sub: gate.reason.isEmpty ? '仅主理人与管理员可查看分润' : gate.reason,
          icon: CupertinoIcons.lock,
          large: true,
          onRetry: () => _goBack(context),
          retryLabel: '返回',
        ),
        ClubAccessDecision.checking => const CySkeleton(),
        _ => summary.when(
          loading: () => const CySkeleton(),
          error: (Object error, StackTrace _) =>
              _errorView(context, ref, error),
          data: (ClubSettlementSummary value) => _body(context, value),
        ),
      };
    }
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('俱乐部分润')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('俱乐部分润'),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  static void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/clubs');
  }

  /// 网络没连上与业务失败在小程序是两个互斥终态(network-error / error),
  /// 标题不一样 —— 「网络连接失败」会让人去查 WiFi,而问题可能在服务端。
  Widget _errorView(BuildContext context, WidgetRef ref, Object error) {
    final failure = classifyClubCrmFailure(error);
    if (failure.auth) {
      return StatusView(
        message: '分润数据不可见',
        sub: friendlyOrBackendMessage(error, fallback: '当前岗位没有分润查看权限，请联系主理人'),
        icon: CupertinoIcons.lock,
        large: true,
        onRetry: () => _goBack(context),
        retryLabel: '返回',
      );
    }
    return StatusView(
      message: failure.network ? '网络连接失败' : '结算数据暂不可用',
      sub: failure.network
          ? '网络没有连上'
          : friendlyOrBackendMessage(error, fallback: '结算数据没能加载，请稍后重试'),
      icon: CupertinoIcons.cloud,
      large: true,
      onRetry: () => ref.invalidate(clubSettlementSummaryProvider(clubId)),
      retryLabel: '重新加载',
    );
  }

  Widget _body(BuildContext context, ClubSettlementSummary summary) {
    final CyPalette palette = CyPalette.of(context);
    if (summary.topics.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
        children: <Widget>[
          _settledCard(palette, summary),
          if (summary.pendingAdjustment != null) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            _adjustmentCard(palette, summary.pendingAdjustment!),
          ],
          const SizedBox(height: CyTokens.space4),
          _withdrawButton(context),
          const SizedBox(height: CyTokens.space6),
          const StatusView(
            message: '还没有主题结算记录',
            sub: '有主题开始结算后会在这里显示',
            icon: CupertinoIcons.doc_text,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(
        left: CyTokens.pageX,
        right: CyTokens.pageX,
        bottom: CyTokens.space6,
      ),
      children: <Widget>[
        _settledCard(palette, summary),
        if (summary.pendingAdjustment != null) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          _adjustmentCard(palette, summary.pendingAdjustment!),
        ],
        const SizedBox(height: CyTokens.space4),
        _withdrawButton(context),
        const SizedBox(height: CyTokens.space5),
        const CySectionTitle('各主题结算'),
        CupertinoListSection.insetGrouped(
          margin: const EdgeInsets.symmetric(vertical: CyTokens.space2),
          children: <Widget>[
            for (final ClubSettlementTopic topic in summary.topics)
              CupertinoListTile(
                key: Key('club-settlement-topic-${topic.id}'),
                // E-02:source=finance 的 recordId 承载 **topicId**(明细页按
                // CoopFinanceRow.topicId 找记录)—— 传结算行 id 会永远落
                // 「这条结算记录不存在或已不可见」。与真源
                // pages/club/settlement/index.js#goTopicSettlement、
                // coop_finance_page 同口径。
                onTap: () => context.push(
                  '/coop/settlement-detail?source=finance&recordId=${topic.topicId}',
                ),
                title: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(topic.name, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      // 已结算但金额待核验时后端不下发金额,显示「待核验」不留空。
                      topic.amountUnverified ? '待核验' : topic.amountText ?? '',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('原始应结 ${topic.originalAmountText}'),
                    Text('已执行调整 ${topic.executedAdjustmentText}'),
                    Text('核算净额 ${topic.netAmountText}'),
                    Text(topic.arrivedText),
                    Text(topic.paidText),
                  ],
                ),
                additionalInfo: Text(
                  topic.isVoid
                      ? '已作废'
                      : topic.status == 'pending'
                      ? '待入账'
                      : topic.amountUnverified
                      ? '待核验'
                      : '已入账',
                  style: TextStyle(
                    color: topic.status == 'settled' && !topic.amountUnverified
                        ? CyTokens.statusSuccess
                        : palette.textTertiary,
                  ),
                ),
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: palette.textTertiary,
                ),
              ),
          ],
        ),
        Text(
          // 本 PR 的作废态说明 + main 侧 iOS 27 字级(原分支用裸 TextStyle(fontSize:12))。
          '已入账以账户打款记录为准；核算净额包含已执行调整，后续调整不代表已到账。'
          '作废记录保留历史金额，不再打款。',
          style: CyType.caption1.copyWith(color: palette.textTertiary),
        ),
      ],
    );
  }

  Widget _settledCard(CyPalette palette, ClubSettlementSummary summary) {
    return Container(
      margin: const EdgeInsets.only(top: CyTokens.space4),
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('已入账分润', style: TextStyle(color: palette.textSecondary)),
          const SizedBox(height: CyTokens.space1),
          Text(
            // 后端判「金额待核验」时不下发合计金额,这里显示状态话术,绝不显示 0 或留空。
            summary.amountUnverified
                ? '金额待核验'
                : summary.settledAmountText ?? '',
            style: CyType.largeTitle.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (summary.unverifiedSettledCount > 0) ...<Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              '${summary.unverifiedSettledCount} 笔已结算记录缺少入账证据，合计待核验',
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _adjustmentCard(
    CyPalette palette,
    ClubSettlementAdjustment adjustment,
  ) {
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${adjustment.amountText} 调整待处理',
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            adjustment.note,
            style: CyType.footnote.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space3),
          Container(height: 1, color: palette.cardBorder),
          const SizedBox(height: CyTokens.space3),
          Row(
            children: <Widget>[
              Text('已执行调整', style: TextStyle(color: palette.textSecondary)),
              const Spacer(),
              Text(
                adjustment.executedText,
                style: TextStyle(color: palette.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _withdrawButton(BuildContext context) {
    return CyNativeButton(
      key: const Key('club-settlement-withdraw'),
      label: '联系平台客服提现',
      width: double.infinity,
      // ★ R10:不发请求、不进银行卡表单 —— 只把客服号交到用户手上。
      onPressed: () => showWithdrawalContactDialog(context),
    );
  }
}
