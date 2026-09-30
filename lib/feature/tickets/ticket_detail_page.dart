import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'explore_completion_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../data/models/activity.dart';
import '../../core/widgets/cy_widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';

/// 票卡详情:`POST /api/registration/info`。③ 探索票带 entitlements。
final ticketDetailProvider = FutureProvider.autoDispose
    .family<RegistrationDetail, int>((ref, id) {
      return ref.watch(activityApiProvider).ticketInfo(id);
    });

/// 票卡详情页:票面信息 + 履约记录(逐章权益)+ 出示核销码入口。
///
/// ⚠️ 完成度必须按 entitlements 逐章算,**不能用 verificationStatus** ——
/// 它对 ③ 只表示「被核销过至少一次」(后端 ApiRegistrationController:429-431)。
class TicketDetailPage extends ConsumerWidget {
  const TicketDetailPage({super.key, required this.registrationId});
  final int registrationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 游客深链落地时给登录门,而不是被静默弹回首页(B1 报告 #231 P1)。
    //   游客态**不订阅** provider:详情接口必然 401,不必发这个注定失败的请求。
    final bool guest = !ref.watch(authControllerProvider).isLoggedIn;
    final AsyncValue<RegistrationDetail>? detail = guest
        ? null
        : ref.watch(ticketDetailProvider(registrationId));
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('票券详情'),
              Expanded(
                child: detail == null
                    ? StatusView(
                        key: const Key('ticket-detail-login-gate'),
                        message: '登录后查看票券详情',
                        sub: '票在账号里，登录完就能看到这一页。',
                        icon: CupertinoIcons.lock,
                        large: true,
                        retryLabel: '去登录',
                        onRetry: () async {
                          if (!await requireLogin(context, ref)) return;
                        },
                      )
                    : RefreshIndicator.adaptive(
                        onRefresh: () async => ref.invalidate(
                          ticketDetailProvider(registrationId),
                        ),
                        child: detail.when(
                          loading: () =>
                              const CySkeleton(type: CySkeletonType.detail),
                          error: (Object err, StackTrace st) => StatusView(
                            message: '票券详情加载失败',
                            icon: CupertinoIcons.exclamationmark_triangle,
                            scrollable: true,
                            onRetry: () => ref.invalidate(
                              ticketDetailProvider(registrationId),
                            ),
                          ),
                          data: (RegistrationDetail d) => _Body(detail: d),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.detail});
  final RegistrationDetail detail;

  /// 能不能出码:与后端 issueDynCode 的闸同口径 ——
  /// 已支付(registrationStatus==2)且还有待核销章节。
  /// 非 ③ 的票没有 entitlements,只看支付态。
  bool get _canIssue {
    if (detail.registrationStatus != 2) return false;
    if (detail.entitlements.isEmpty) return detail.verificationStatus != 1;
    return detail.pendingCount > 0;
  }

  /// 不能出码时,按钮上该说的话。
  ///
  /// ★ [_canIssue] 为假有**三种成因**(未支付 / 已取消 / 核销完),原先一律显示
  ///   「该票已核销完」—— 对前两种既是假话(票压根没用过),又堵死了用户的下一步:
  ///   待支付的人看到「已核销完」只会以为票废了。按成因分流。
  ///   registrationStatus 取值同小程序票夹 wxs:1待支付 / 2已报名 / 3已取消。
  String get _disabledLabel {
    if (detail.registrationStatus == 1) return '支付完成后可出示';
    if (detail.registrationStatus == 3) return '该票已取消';
    if (detail.registrationStatus != 2) return '该票暂不可用';
    return '该票已全部核销';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(CyTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  detail.title ?? '未命名活动',
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: CyTokens.typeCardTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CyTokens.space3),
                if (detail.registrationNo != null)
                  _KeyValue(label: '票号', value: detail.registrationNo!),
                if (detail.participateDate != null &&
                    detail.participateDate!.isNotEmpty)
                  _KeyValue(label: '参与日期', value: detail.participateDate!),
                if (detail.realName != null && detail.realName!.isNotEmpty)
                  _KeyValue(label: '联系人', value: detail.realName!),
                // 手机号后端已脱敏(RegistrationDetailDisplay.enrich),原样展示。
                if (detail.phone != null && detail.phone!.isNotEmpty)
                  _KeyValue(label: '手机号', value: detail.phone!),
              ],
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space4),
        if (detail.entitlements.isNotEmpty) ...<Widget>[
          // 版式对齐小程序 scene-member-order-detail 的「权益明细」:
          // **一张卡包住全部**,每条是一行(名称左 / 状态右),行间 1px 下边框,
          // 最后一行不画线。不是每条一张 Card —— 那样在多章节时视觉过重。
          Card(
            child: Padding(
              padding: EdgeInsets.all(CyTokens.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(
                        '权益明细',
                        style: textTheme.titleSmall?.copyWith(
                          fontSize: CyTokens.typeBody,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: CyTokens.space2),
                      Text(
                        '还剩 ${detail.pendingCount} 章待核销',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: CyTokens.typeCaption,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: CyTokens.space2_5),
                  ...List<Widget>.generate(detail.entitlements.length, (int i) {
                    return _EntitlementRow(
                      entitlement: detail.entitlements[i],
                      last: i == detail.entitlements.length - 1,
                    );
                  }),
                ],
              ),
            ),
          ),
          SizedBox(height: CyTokens.space4),
        ],
        if (_canIssue)
          CyNativeButton(
            label: '出示核销码',
            borderRadius: CyTokens.radiusLg,
            onPressed: () => context.push('/ticket/${detail.id}/pass'),
            // 同一个 CTA 的两个态共用一个回退字形(iOS 13–25 走 fallback,
            // 两态长得不一样 = 同一个动作两个图标)。
            icon: const CyNativeButtonIcon(
              sfSymbol: 'qrcode',
              fallback: CupertinoIcons.qrcode,
            ),
          )
        else
          CyNativeButton(
            label: _disabledLabel,
            onPressed: null,
            icon: const CyNativeButtonIcon(
              sfSymbol: 'qrcode',
              fallback: CupertinoIcons.qrcode,
            ),
          ),
        // ★★ 探店日完局面(图鉴 / 通关奖励 / 回访)。
        //   **只对已支付的 ③ 探索票拉**。判据抄小程序 loadCompletion,
        //   它的注释原话:「①② 与未支付单拉了也只有空壳,而订单详情是
        //   每次 onShow 都会走的路径 —— 无条件拉 = 每笔订单白查五张表」。
        //   ⇒ 不是"反正后端会拒、拒了收起来就行":那样每开一张普通票
        //     都白打一次必然失败的请求。
        //   ③ 的判据用 entitlements 非空(同本页 _canIssue 的口径:
        //   「非 ③ 的票没有 entitlements」)。
        if (detail.registrationStatus == 2 && detail.entitlements.isNotEmpty)
          ExploreCompletionSection(registrationId: detail.id),
      ],
    );
  }
}

/// 权益明细的一行。对齐小程序 .ent-row:
/// 名称占满(flex:1)+ 右侧状态文字;行间 1px 下边框,最后一行不画。
///
/// ⚠️ 状态用**统一的次要色**,不按状态变色 —— 小程序 .ent-status 就是
/// text-secondary。区分靠 statusLabel 文案本身,再上色就是同一信息说两遍
/// (与票夹删掉彩底状态胶囊是同一条设计判断)。
class _EntitlementRow extends StatelessWidget {
  const _EntitlementRow({required this.entitlement, required this.last});
  final Entitlement entitlement;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: EdgeInsets.only(
        top: CyTokens.space2,
        bottom: last ? 0 : CyTokens.space2,
      ),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: palette.borderSubtle, width: 1),
              ),
            ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: CyTokens.space2),
              child: Text(
                entitlement.chapterName ?? '章节 ${entitlement.chapterId ?? '-'}',
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: CyTokens.typeLabel,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          Text(
            entitlement.label,
            style: textTheme.bodySmall?.copyWith(
              fontSize: CyTokens.typeCaption,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: CyTokens.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
