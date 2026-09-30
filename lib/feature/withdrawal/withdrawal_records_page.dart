import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/withdrawal.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'withdrawal_gate.dart';
import 'withdrawal_page.dart';

/// 提现记录。对齐小程序 `subpackageMember/tixianjilu`。
class WithdrawalRecordsPage extends ConsumerWidget {
  const WithdrawalRecordsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('提现记录')),
      child: SafeArea(bottom: false, child: _body(context, ref)),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    // ★ 游客深链落地时给页内登录门,而不是静默停在 401 错误态
    //   (B1 模拟器报告 P1-3,修法同 roam #208)——
    //   先拦在这里,那个注定失败的 /api/withdrawal/list 根本不发。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return StatusView(
        key: const Key('withdrawal-records-login-gate'),
        message: '登录后查看提现记录',
        sub: '提现记录挂在账号里,登录完就能看到。',
        icon: CupertinoIcons.lock,
        large: true,
        retryLabel: '去登录',
        onRetry: () async {
          // 登录态一变,这个分支自然让位给列表。
          await requireLogin(context, ref);
        },
      );
    }
    final async = ref.watch(withdrawalRecordsProvider);
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      // ★ 错误归一(真跑报告 P1-1):异常原文一句都不上屏 ——
      //   这是资金页,直出 DioException 会挂着「fix the server code」
      //   和 mozilla 链接让用户去「修服务端」。401 与故障分开说,
      //   判据与措辞口径同 topic_pricing_page / club 侧前例;
      //   故障文案贴真源 scene-member-withdraw-history 的 cy-error。
      // ★ 刷新失败但记录还在 ⇒ 真源同分支:**列表保留**,只加一条
      //   非阻断横幅(「更多提现记录没加载出来/已加载的记录仍为你保留」),
      //   整屏错误只留给一条都没有的情况(同 #200 订单页纪律)。
      error: (Object e, _) {
        if (isUnauthorizedError(e)) {
          return StatusView(
            message: '登录状态已失效，请重新登录',
            sub: '提现记录都还在,重新登录后接着看。',
            icon: CupertinoIcons.lock,
            large: true,
            retryLabel: '去登录',
            onRetry: () async {
              if (!await requireLogin(context, ref)) return;
              ref.invalidate(withdrawalRecordsProvider);
            },
          );
        }
        final List<WithdrawalRecord>? kept = async.value;
        if (kept == null || kept.isEmpty) {
          return StatusView(
            message: '提现记录没加载出来',
            // ★ 后端中文原话优先,没有才落真源兜底文案
            //   (b1-sim-r10-withdrawal P1-1 增量,归一模式同 my_plays_page)。
            sub: withdrawalFailureSub(e),
            large: true,
            onRetry: () => ref.invalidate(withdrawalRecordsProvider),
          );
        }
        return Column(
          children: <Widget>[
            _WithdrawalRefreshError(
              onRetry: () => ref.invalidate(withdrawalRecordsProvider),
            ),
            Expanded(child: _recordsList(ref, kept)),
          ],
        );
      },
      data: (List<WithdrawalRecord> rows) {
        if (rows.isEmpty) {
          return const StatusView(
            message: '暂无提现记录',
            sub: '你还没有发起过提现，提现记录会显示在这里',
            large: true,
          );
        }
        return _recordsList(ref, rows);
      },
    );
  }

  Widget _recordsList(WidgetRef ref, List<WithdrawalRecord> rows) {
    return RefreshIndicator.adaptive(
      onRefresh: () async => ref.invalidate(withdrawalRecordsProvider),
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.pageX),
        children: <Widget>[_RecordsCard(rows: rows)],
      ),
    );
  }
}

/// 真源 `scene-member-withdraw-history` 玩家档列表容器 `.txjl`:
/// 整个列表是一张浅卡(bg-surface-subtle + radius-lg、内衬 space2),
/// 行 `.txjl_li` min-h btn-h+space5=68、行间隔 space1、玩家档无分隔线。
class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.rows});

  final List<WithdrawalRecord> rows;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space2),
      decoration: BoxDecoration(
        color: palette.bgSurfaceSubtle,
        borderRadius: BorderRadius.circular(CyTokens.radiusLg),
      ),
      child: Column(
        children: <Widget>[
          for (final WithdrawalRecord r in rows) ...<Widget>[
            CyCell(
              // 真源 `scene-member-withdraw-history` 行制:左列标题+时间,
              // 右列金额+状态档(两列各自纵向)。
              minHeight: CyTokens.btnH + CyTokens.space5,
              title: '提现到银行卡',
              subtitle: <String>[
                if ((r.createTime ?? '').isNotEmpty) r.createTime!,
                if ((r.bankName ?? '').isNotEmpty)
                  '${r.bankName} ${r.maskedAccount}',
              ].join(' · '),
              showChevron: false,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '¥${r.amount.toStringAsFixed(2)}',
                    style: CyType.headline.copyWith(color: palette.textPrimary),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    r.statusText,
                    style: CyType.caption1.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (r != rows.last) const SizedBox(height: CyTokens.space1),
          ],
        ],
      ),
    );
  }
}

/// 真源列表内 cy-error(非整屏):标题/副文案/「重试」逐字同
/// `scene-member-withdraw-history` 的刷新失败分支。
class _WithdrawalRefreshError extends StatelessWidget {
  const _WithdrawalRefreshError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.space2,
        0,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 18,
            color: palette.textSecondary,
          ),
          const SizedBox(width: CyTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '更多提现记录没加载出来',
                  style: CyType.headline.copyWith(color: palette.textPrimary),
                ),
                Text(
                  '已加载的记录仍为你保留',
                  style: CyType.caption1.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2),
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
