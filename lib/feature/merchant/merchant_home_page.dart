import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/merchant_access_provider.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/merchant_api.dart';
import '../../l10n/strings.dart';
import '../../data/models/merchant_application.dart';
import '../auth/login_gate.dart';
import 'merchant_error_view.dart';
import 'merchant_game_node_page.dart';
import '../../data/models/merchant_dashboard.dart';

final merchantDashboardProvider = FutureProvider.autoDispose<MerchantDashboard>(
  (ref) {
    return ref.watch(merchantApiProvider).dashboard();
  },
);

final merchantTodoProvider = FutureProvider.autoDispose<MerchantTodo>((ref) {
  return ref.watch(merchantApiProvider).todoSummary();
});

/// 商家实时动态:`POST /api/merchant/events`(收入到账/核销等真实事件,已按时间倒序取前 10)。
/// ★ time 已是后端格式化好的 `MM-dd HH:mm`,不再解析——那串没有年份和时区,跨年就错。
final merchantEventsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
      return ref.watch(merchantApiProvider).merchantEvents();
    });

/// 商家工作台。对齐小程序 `pages/merchant/index`。
///
/// ★★ 整页的根是 `access/me`,不是 `dashboard`:
///   · 谁是店主、哪个岗位有什么权限 —— 决定这一页摆什么(见 `merchantAccessProvider`);
///   · 收入/待办/动态三个请求在后端是 **owner-only**,财务岗 `canReadFinance`
///     为真也照样 403。以前拿 dashboard 当根,岗位稍窄一点整页就成错误屏,
///     商家看到的是一句和自己无关的「加载失败」。
class MerchantHomePage extends ConsumerWidget {
  const MerchantHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MerchantAccess> access = ref.watch(merchantAccessProvider);
    return CupertinoPageScaffold(
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).merchantHomeTitle),
        // ★ 消息入口此前**只在「我的」页** —— 而合作邀约、官方通知
        //   都落在消息里,商家在工作台完全看不到。
        //   小程序的结算页就挂着「查看聊天与系统通知」。
        trailing: _UnreadBell(),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: access.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            // 身份**没读到**与身份**没有权限**是两回事:前者才给重试。
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              what: stringsOf(context).merchantHomeIdentity,
              onRetry: () => ref.invalidate(merchantAccessProvider),
            ),
            data: (MerchantAccess a) =>
                a.active ? _Workbench(access: a) : _ApplicationStateCard(a),
          ),
        ),
      ),
    );
  }
}

/// 未激活经营身份:审核中 / 已驳回 / 已停用 / 待启用 —— 页内说清状态与原因,
/// 并给出「查看申请进度」这条唯一的出路(申请页才是状态页)。
///
/// ★ 真源裁决(2026-09-17 #24):不再静默跳回会员中心。
class _ApplicationStateCard extends StatelessWidget {
  const _ApplicationStateCard(this.access);

  final MerchantAccess access;

  @override
  Widget build(BuildContext context) {
    final MerchantApplication? application = access.application;
    if (application == null) {
      // NONE(没有申请行)或后端没给结论 —— 不替商家编一个状态。
      return StatusView(
        message: stringsOf(context).merchantHomeNotMerchant,
        sub: stringsOf(context).merchantHomeApplyHint,
        large: true,
        onRetry: () => context.push('/merchant/apply'),
        retryLabel: stringsOf(context).merchantHomeApply,
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final palette = CyPalette.of(context);
    return ListView(
      padding: const EdgeInsets.all(CyTokens.pageX),
      children: <Widget>[
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _StateBadge(
                    text: _applicationStatusLabel(context, application),
                    foreground: application.isDangerBadge
                        ? palette.statusDanger
                        : palette.textSecondary,
                  ),
                  const Spacer(),
                  if (access.merchantName != null)
                    Text(
                      access.merchantName!,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: CyTokens.space2),
              Text(_applicationStatusText(context, application), style: textTheme.bodyMedium),
              const SizedBox(height: CyTokens.space2),
              CupertinoButton(
                key: const Key('merchant-application-progress-entry'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => context.push('/merchant/apply'),
                child: Row(
                  children: <Widget>[
                    Text(stringsOf(context).merchantHomeProgress),
                    const SizedBox(width: CyTokens.space1),
                    const Icon(CupertinoIcons.chevron_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _applicationStatusLabel(BuildContext context, MerchantApplication a) {
  if (a.isDisabled) return stringsOf(context).merchantHomeDisabled;
  if (a.status == 1 && a.accountStatus == 1) return stringsOf(context).merchantHomeActive;
  if (a.isRejected) return stringsOf(context).merchantHomeRejected;
  if (a.status == 1) return stringsOf(context).merchantHomeAwaitingActivation;
  if (a.status == 0) return stringsOf(context).merchantHomeUnderReview;
  return stringsOf(context).merchantHomeUnknownStatus;
}

String _applicationStatusText(BuildContext context, MerchantApplication a) {
  if (a.isDisabled) {
    final reason = a.disableReason.trim();
    return reason.isEmpty ? stringsOf(context).merchantHomeDisabledNoReason : stringsOf(context).merchantHomeDisabledReason(reason);
  }
  if (a.status == 1 && a.accountStatus == 1) return stringsOf(context).merchantHomeActiveExplanation;
  if (a.isRejected) {
    final reason = a.rejectReason.trim();
    return reason.isEmpty ? stringsOf(context).merchantHomeRejectedNoReason : stringsOf(context).merchantHomeRejectedReason(reason);
  }
  if (a.status == 1) return stringsOf(context).merchantHomeActivationExplanation;
  if (a.status == 0) return stringsOf(context).merchantHomeReviewExplanation;
  return stringsOf(context).merchantHomeUnknownExplanation;
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.text, required this.foreground});

  final String text;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: foreground.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
    ),
    // 与入驻申请状态页 `_StatusPill` 同一枚签:Caption1(12)。
    // 以前取 `typeMicro`(=10),在 HIG 11pt 下限之下(A1/T1)。
    child: Text(
      text,
      style: CyType.caption1.copyWith(
        color: foreground,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// 已激活的经营身份 —— 工作台本体。每个入口按 `access/me` 的岗位权限显隐。
class _Workbench extends ConsumerWidget {
  const _Workbench({required this.access});

  final MerchantAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ★ 待办/动态只在店主身份下才**被 watch** —— autoDispose provider
    //   不被看见就不会发请求,这正是真源的行为(非店主连岗位有 canVerify
    //   也没有 chips 与铃铛,因为数据根本没请求)。
    final MerchantTodo? todo = access.isOwner
        ? ref.watch(merchantTodoProvider).asData?.value
        : null;
    final List<Map<String, dynamic>>? events = access.isOwner
        ? ref.watch(merchantEventsProvider).asData?.value
        : null;
    return RefreshIndicator.adaptive(
      onRefresh: () async {
        ref.invalidate(merchantAccessProvider);
        // 下拉一次 = 整页重来 —— 此前只刷 dashboard/business/todo,
        // 项目区与动态刷不动,商家得杀进程才看到新承接。
        ref.invalidate(businessStatusProvider);
        ref.invalidate(merchantDashboardProvider);
        if (access.isOwner) {
          ref.invalidate(merchantTodoProvider);
          ref.invalidate(merchantEventsProvider);
        }
        ref.invalidate(merchantJoinedProjectsProvider);
        ref.invalidate(merchantHostedProjectsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(CyTokens.pageX),
        children: <Widget>[
          // 收入大数字:**店主本人 ∧ FINANCE_READ** 两个条件同时成立才给看。
          // 只判权限位会把财务岗的 403 引来 —— dashboard 在后端是 owner-only。
          if (access.canReadFinance && access.isOwner) ...<Widget>[
            const _RevenueCard(),
            const SizedBox(height: CyTokens.space3),
          ],
          if (access.isOwner) ...<Widget>[
            const _TodoBlock(),
            const SizedBox(height: CyTokens.space3),
          ],
          // 项目区整块按 `project:manage` 收放(真源 `wx:if="{{merchantAccess.canManageProjects}}"`)。
          if (access.canManageProjects) ...<Widget>[
            MerchantGameEntriesSection(todo: todo, events: events),
            const SizedBox(height: CyTokens.space3),
          ],
          if (events != null && events.isNotEmpty) ...<Widget>[
            const _EventsBlock(),
            const SizedBox(height: CyTokens.space3),
          ],
          _Actions(access: access),
        ],
      ),
    );
  }
}

class _RevenueCard extends ConsumerWidget {
  const _RevenueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final palette = CyPalette.of(context);
    final AsyncValue<MerchantDashboard> dash = ref.watch(
      merchantDashboardProvider,
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            stringsOf(context).merchantHomeRevenue,
            style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: CyTokens.space1),
          ...dash.when(
            // ★ 这一块坏了只是**这一块**坏了 —— 不上整页错误屏,
            //   也不把没取到冒充成 ¥0.00。
            loading: () => <Widget>[
              Text(
                stringsOf(context).merchantHomeRevenueLoading,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            error: (Object e, _) => <Widget>[
              Text(
                stringsOf(context).merchantHomeRevenueUnavailable,
                style: textTheme.headlineSmall?.copyWith(
                  color: palette.textTertiary,
                ),
              ),
              const SizedBox(height: CyTokens.space2),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      stringsOf(context).merchantHomeRevenueError,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  CupertinoButton(
                    key: const Key('merchant-revenue-reload'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => ref.invalidate(merchantDashboardProvider),
                    child: Text(stringsOf(context).merchantHomeReloadSection),
                  ),
                ],
              ),
            ],
            data: (MerchantDashboard d) => <Widget>[
              // ★ 走 revenueDisplay:后端没下发该字段时显破折号,不冒充 ¥0.00。
              Text(d.revenueDisplay, style: textTheme.headlineSmall),
              if (d.revenue7d.isNotEmpty) ...<Widget>[
                const SizedBox(height: CyTokens.space3),
                _Sparkline(points: d.revenue7d),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 近 7 日收入迷你柱图。
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.points});
  final List<RevenuePoint> points;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxValue = points
        .map((RevenuePoint p) => p.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((RevenuePoint p) {
          // 全为 0 时给一个最小可见高度,避免整排空白让人以为没渲染。
          final ratio = maxValue <= 0 ? 0.0 : p.value / maxValue;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Container(
                    height: 4 + ratio * 44,
                    decoration: BoxDecoration(
                      color: ratio > 0
                          ? CyPalette.of(context).textPrimary
                          : CyPalette.of(context).bgSurfaceStrong,
                      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    p.date,
                    style: textTheme.labelSmall?.copyWith(
                      color: CyPalette.of(context).textTertiary,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TodoBlock extends ConsumerWidget {
  const _TodoBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantTodoProvider);
    final textTheme = Theme.of(context).textTheme;
    return async.when(
      loading: () => _Card(child: Text(stringsOf(context).merchantHomeTodoLoading)),
      error: (Object e, _) => _Card(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                stringsOf(context).merchantHomeTodoError,
                style: textTheme.bodyMedium?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
            CupertinoButton(
              onPressed: () => ref.invalidate(merchantTodoProvider),
              padding: EdgeInsets.zero,
              child: Text(stringsOf(context).retry),
            ),
          ],
        ),
      ),
      data: (MerchantTodo t) {
        // ★ 待办为 0 的项不显示 —— 「待核销 0」是噪音,不是信息。
        //   全部为 0 时说一句「暂时没有待办」,而不是排一列 0。
        final rows = <(String, int, String)>[
          (stringsOf(context).merchantHomePendingVerify, t.pendingVerify, '/merchant/scan'),
          (stringsOf(context).merchantHomePendingScan, t.pendingScanConfirm, '/merchant/scan'),
          (stringsOf(context).merchantHomePendingOrders, t.pendingOrders, '/orders'),
          (stringsOf(context).merchantHomeRefunds, t.refundCount, '/merchant/aftercare'),
        ].where(((String, int, String) r) => r.$2 > 0).toList();

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CySectionTitle(stringsOf(context).merchantHomeTodo),
              const SizedBox(height: CyTokens.space2),
              if (rows.isEmpty)
                Text(
                  stringsOf(context).merchantHomeNoTodo,
                  style: textTheme.bodyMedium?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                )
              else
                ...rows.map(
                  ((String, int, String) r) => CyCell(
                    title: r.$1,
                    subtitle: stringsOf(context).itemCount(r.$2),
                    onTap: () => context.push(r.$3),
                  ),
                ),
              if (t.verifiedCount > 0) ...<Widget>[
                const SizedBox(height: CyTokens.space2),
                Text(
                  stringsOf(context).merchantHomeVerifiedCount(t.verifiedCount),
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 实时动态:收入到账/核销等真实事件。对齐小程序工作台的"动态"区。
/// ★ 空列表就说明当前没有动态,不是加载失败——不显示这个卡片即可,不用空态占位。
class _EventsBlock extends ConsumerWidget {
  const _EventsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantEventsProvider);
    final textTheme = Theme.of(context).textTheme;
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (Object e, _) => const SizedBox.shrink(),
      data: (List<Map<String, dynamic>> events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CySectionTitle(stringsOf(context).merchantHomeEvents),
              const SizedBox(height: CyTokens.space2),
              ...events.map((Map<String, dynamic> e) {
                final String content = (e['content'] as String?) ?? '';
                final String time = (e['time'] as String?) ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: CyTokens.space1_5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(content, style: textTheme.bodyMedium),
                      ),
                      const SizedBox(width: CyTokens.space2),
                      Text(
                        time,
                        style: textTheme.bodySmall?.copyWith(
                          color: CyPalette.of(context).textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// 当前营业状态。★ 此前 App **只写不读** —— 两个按钮恒定长一个样,
/// 「开始营业」永远高亮,商家看不出自己现在是营业还是打烊。
final businessStatusProvider =
    FutureProvider.autoDispose<({bool open, String text})>((ref) {
      return ref.watch(merchantApiProvider).businessStatus();
    });

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.access});

  /// 岗位权限 —— 动作区每一项的显隐判据都来自 `access/me`,不是全局 role。
  final MerchantAccess access;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Future<void> _setStatus(bool open) async {
    setState(() => _busy = true);
    try {
      final msg = await ref
          .read(merchantApiProvider)
          .updateBusinessStatus(open: open);
      if (!mounted) return;
      // 原样转述后端的话(「已营业」/「已打烊」),不自己另编一句。
      CyNativeNotice.show(context, msg);
      ref.invalidate(merchantDashboardProvider);
      // 写完读回 —— 以服务端为准,不本地翻转
      ref.invalidate(businessStatusProvider);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Builder(
            builder: (BuildContext context) {
              final AsyncValue<({bool open, String text})> st = ref.watch(
                businessStatusProvider,
              );
              final bool? open = st.asData?.value.open;
              // ★ 状态一律显示,只有**改**的权力按 `canWriteProfile` 收放
              //   (真源 index.wxml:47/50:同一个徽标的可点分支与纯展示分支)。
              final bool editable = widget.access.canWriteProfile;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CySectionTitle(stringsOf(context).merchantHomeBusinessStatus),
                      const Spacer(),
                      // ★ 状态文案用后端原话(「营业中」/「已打烊」),不另编一套。
                      //   还没读回来时不写死一个默认值 —— 那等于替商家宣称一个
                      //   我们并不知道的状态。
                      Text(
                        st.asData?.value.text ?? stringsOf(context).merchantHomeStatusLoading,
                        style: TextStyle(
                          color: CyPalette.of(context).textSecondary,
                          fontSize: CyTokens.typeCaption,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CyTokens.space2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        // ★ 当前状态那一侧用实心高亮 —— 原来「开始营业」恒为实心,
                        //   营业中的商家看上去像还没开门。
                        // ★ 当前态用**实心+主色**,不用 disabled ——
                        //   禁用态是浅灰的,渲出来比旁边可点的那颗还弱,
                        //   主次正好反了(实拍基准图看出来的)。
                        //   点当前态是空操作,靠 onPressed:null 之外的方式表达"就是它"。
                        child: CyNativeButton(
                          label: open == false ? stringsOf(context).merchantHomeClosed : stringsOf(context).merchantHomeClose,
                          onPressed: !editable || (open != false && _busy)
                              ? null
                              : open == false
                              ? () {}
                              : () => _setStatus(false),
                          role: open == false
                              ? CyNativeButtonRole.primary
                              : CyNativeButtonRole.secondary,
                        ),
                      ),
                      const SizedBox(width: CyTokens.space2),
                      Expanded(
                        child: CyNativeButton(
                          label: open == true ? stringsOf(context).merchantHomeOpen : stringsOf(context).merchantHomeStart,
                          onPressed: !editable || (open != true && _busy)
                              ? null
                              : open == true
                              ? () {}
                              : () => _setStatus(true),
                          role: open == true
                              ? CyNativeButtonRole.primary
                              : CyNativeButtonRole.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: CyTokens.space3),
          // ★ 每一项各自申报它需要哪项岗位权限 —— 判据抄真源的 `wx:if`。
          //   没有真源依据的(App 独有入口)一律**不加闸**:
          //   凭猜测收掉的入口,员工就再也找不到它了。
          ..._actions(),
        ],
      ),
    );
  }

  /// 动作项之间插一条间距。★ 先筛后排 —— 逐项写 `if` 时,
  /// 被筛掉的那一项会把它的间距也留下,尾部/中间就多出一截空白。
  List<Widget> _actions() {
    final MerchantAccess a = widget.access;
    final entries = <Widget>[
      if (a.canVerify)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeScan,
          onPressed: () => context.push('/merchant/scan'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'qrcode.viewfinder',
            fallback: CupertinoIcons.qrcode_viewfinder,
          ),
        ),
      if (a.canReadFinance)
        SizedBox(
          width: double.infinity,
          child: CupertinoButton.tinted(
            key: const Key('merchant-finance-entry'),
            minimumSize: const Size.fromHeight(CyTokens.btnH),
            onPressed: () {
              context.push('/merchant/ledger?view=settlement');
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // R10 过渡期:此入口是只读账本/结算视图,不发起提现、无卡号表单。
                // creditcard 会被读成「能往银行卡打钱」,用账簿语义的 doc.text。
                const Icon(CupertinoIcons.doc_text),
                const SizedBox(width: CyTokens.space2),
                Text(stringsOf(context).merchantHomeFinance),
              ],
            ),
          ),
        ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeCooperation,
        onPressed: () => context.push('/merchant/coop'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'person.2',
          fallback: CupertinoIcons.person_2,
        ),
      ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeAssignments,
        onPressed: () => context.push('/merchant/chapters'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'list.bullet.clipboard',
          fallback: CupertinoIcons.list_bullet,
        ),
      ),
      if (a.canWriteProfile)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeDecor,
          onPressed: () => context.push('/merchant/decor'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'storefront',
            fallback: CupertinoIcons.building_2_fill,
          ),
        ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeCharacter,
        onPressed: () => context.push('/merchant/npc'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'person.crop.circle.badge.questionmark',
          fallback: CupertinoIcons.person_crop_circle,
        ),
      ),
      if (a.canReadAftercare)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeAftercare,
          onPressed: () => context.push('/merchant/aftercare'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'arrow.uturn.backward.circle',
            fallback: CupertinoIcons.arrow_uturn_left_circle,
          ),
        ),
      if (a.canReadCrm)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeCustomers,
          onPressed: () => context.push('/merchant/customers'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'person.2',
            fallback: CupertinoIcons.person_2,
          ),
        ),
      if (a.canManageCoop)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeCoopProfile,
          onPressed: () => context.push('/merchant/coop-profile'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'person.text.rectangle',
            fallback: CupertinoIcons.person_crop_circle,
          ),
        ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomePartners,
        onPressed: () => context.push('/merchant/relations'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'person.3',
          fallback: CupertinoIcons.person_3,
        ),
      ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeCityNodes,
        onPressed: () => context.push('/merchant/city-nodes'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'mappin.and.ellipse',
          fallback: CupertinoIcons.location,
        ),
      ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeProjects,
        onPressed: () => context.push('/project/home'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'rectangle.grid.2x2',
          fallback: CupertinoIcons.square_grid_2x2,
        ),
      ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeRegistrations,
        onPressed: () => context.push('/merchant/registrations'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'checklist',
          fallback: CupertinoIcons.check_mark_circled,
        ),
      ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeMarketing,
        onPressed: () => context.push('/merchant/marketing'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'megaphone',
          fallback: CupertinoIcons.speaker_2,
        ),
      ),
      if (a.canWriteProfile)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeStoreProfile,
          onPressed: () => context.push('/merchant/edit'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'storefront',
            fallback: CupertinoIcons.building_2_fill,
          ),
        ),
      if (a.canReadOrders)
        _wideSecondaryAction(
          label: stringsOf(context).merchantHomeOrders,
          onPressed: () => context.push('/merchant/orders'),
          icon: const CyNativeButtonIcon(
            sfSymbol: 'bag',
            fallback: CupertinoIcons.bag,
          ),
        ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeServices,
        onPressed: () => context.push('/merchant/subscription'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'star',
          fallback: CupertinoIcons.star,
        ),
      ),
      _wideSecondaryAction(
        label: stringsOf(context).merchantHomeClubs,
        onPressed: () => context.push('/merchant/clubs'),
        icon: const CyNativeButtonIcon(
          sfSymbol: 'person.3',
          fallback: CupertinoIcons.person_3,
        ),
      ),
    ];
    return <Widget>[
      for (var i = 0; i < entries.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: CyTokens.space2),
        entries[i],
      ],
    ];
  }

  Widget _wideSecondaryAction({
    required String label,
    required VoidCallback onPressed,
    required CyNativeButtonIcon icon,
  }) => SizedBox(
    width: double.infinity,
    child: CyNativeButton(
      label: label,
      onPressed: onPressed,
      role: CyNativeButtonRole.secondary,
      icon: icon,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: CyPalette.of(context).bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: CyPalette.of(context).borderSubtle),
      ),
      child: child,
    );
  }
}

/// 消息入口 + 未读角标。
///
/// ⚠️ 未读数拿不到时**只显示图标不显示角标** —— 显示「0」会让人
///   以为「确实没有新消息」,而实际是没查到。两者对用户是两回事。
class _UnreadBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int? unread = ref.watch(merchantUnreadProvider).value;
    return CupertinoButton(
      key: const Key('merchant-im-entry'),
      padding: const EdgeInsets.all(CyTokens.space2),
      // 会话过期后这一下直跳 /im 会被 router 静默兜回首页,先过登录门。
      onPressed: () async {
        if (!await requireLogin(context, ref) || !context.mounted) return;
        context.push('/im');
      },
      child: Semantics(
        button: true,
        label: stringsOf(context).merchantHomeMessages,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            const Icon(CupertinoIcons.chat_bubble_2),
            if (unread != null && unread > 0)
              Positioned(
                right: -4,
                top: -4,
                // 角标走共用件 `CyBadge`(P4),不再手写 —— 手写版拿的是
                // `CyTokens.statusDanger`(暗端编译期常量)配 `Colors.white`,
                // 而这一页是**恒浅**的商家页:浅端红是压深的 #D0323B,白字在
                // danger 底上对比度 3.91 不达 AA(深字 5.06)。同一个坑在
                // CyBadge 上踩过,判据见 test/theme/badge_fg_test.dart。
                child: CyBadge(count: unread, semanticsLabel: stringsOf(context).merchantHomeUnreadCount(unread)),
              ),
          ],
        ),
      ),
    );
  }
}

/// 未读总数。★ 失败**吞掉返回 null** —— 未读数是个附加信息,
/// 取不到不该让工作台报错。
final merchantUnreadProvider = FutureProvider.autoDispose<int?>((
  Ref ref,
) async {
  try {
    return await ref.watch(imApiProvider).unreadTotal();
  } catch (_) {
    return null;
  }
});
