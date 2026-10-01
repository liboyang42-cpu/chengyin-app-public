import 'coop_invite_detail_strings.dart';
import 'coop_strings.dart';
import '../../l10n/strings.dart';
import '../auth/auth_controller.dart';
import '../../core/network/request_session_scope.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/api/coop_api.dart';
import '../../data/models/coop_candidate.dart';
import '../../data/models/coop_invite_row.dart';
import 'coop_guard.dart';
import '../../data/models/coop_pool.dart';
import '../../data/models/coop_perk_template.dart';
import '../../data/models/merchant_coop.dart';
import '../merchant/merchant_coop_page.dart'
    show merchantInvitesProvider, MerchantInviteTile;
import '../auth/auth_controller.dart' show isWechatConfigured;
import '../payment/wechat_payment.dart';

typedef CoopDepositPay =
    Future<WechatPayOutcome> Function(Map<String, String> params);

/// 保证金支付的公开系统边界。真实环境调微信 SDK，测试只替换这一层。
final coopDepositPayProvider = Provider<CoopDepositPay>(
  (ref) => const WechatPayment().pay,
);

/// 未配置 AppId / Universal Link 时在建单前 fail closed，避免留下无法支付的单。
final coopDepositPaymentConfiguredProvider = Provider<bool>(
  (ref) => isWechatConfigured,
);

final coopDepositPaymentGateProvider = Provider<WechatPaymentGate>(
  (ref) => wechatPaymentFlowGate,
);

final coopInviteListProvider = FutureProvider.autoDispose<CoopInviteList>((
  ref,
) async {
  final data = await ref.watch(coopApiProvider).inviteList();
  return CoopInviteList.fromJson(data);
});

/// 带队申请两路(`/api/coop/pool/received` / `/api/coop/pool/mine`)。
///
/// ★ 与 [coopInviteListProvider] 是**两套东西**,不能互相替代:
///   邀约是已经谈成的合作单,带队申请是俱乐部「我想接这个主题」的意向
///   (小程序 `pages/coop/list/index.wxml` 两个 tab 里各有一块申请区)。
///   少了它,商家看不到谁来申请带队,俱乐部也撤不回自己发出去的申请。
///
/// ⚠️ 用 `/pool/mine` 而不是复用 `/pool/list`:后者只列**还开放**的主题,
///   已拒绝/已撤回的申请会从发件箱里消失(小程序专门有测试钉这一点)。
final coopPoolAppliesProvider = FutureProvider.autoDispose
    .family<List<CoopPoolApply>, String>((Ref ref, String box) async {
      final CoopApi api = ref.watch(coopApiProvider);
      final List<Map<String, dynamic>> rows = box == 'received'
          ? await api.poolReceived()
          : await api.poolMine();
      return rows.map(CoopPoolApply.fromJson).toList();
    });

/// 收到的承接报名(商家报名承接我主题的节点,**跨主题聚合**)。
///
/// ★ 与 [coopPoolAppliesProvider] 是两条独立航班:那条是**俱乐部**申请带队
///   (`/api/coop/pool/received`),这条是**商家**报名承接(`/api/coop/candidates/received`)。
///   真源也是两路各自结算、各自报错 —— 一条挂了只压它自己那一块
///   (`pages/coop/list/index.js:319-366` 与 :237-316)。
final coopReceivedRegsProvider =
    FutureProvider.autoDispose<List<CoopReceivedRegistration>>((Ref ref) async {
      final List<Map<String, dynamic>> rows = await ref
          .watch(coopApiProvider)
          .receivedRegistrations();
      return rows.map(CoopReceivedRegistration.fromJson).toList();
    });

/// 我的合作邀请。对齐小程序 `pages/coop/list`(收到的 / 我发出的两档;
/// 合作池已有独立页面 [CoopPoolPage],这里不重复)。
class CoopListPage extends ConsumerStatefulWidget {
  const CoopListPage({super.key, this.initialTab = 'received'});

  final String initialTab;

  @override
  ConsumerState<CoopListPage> createState() => _CoopListPageState();
}

class _CoopListPageState extends ConsumerState<CoopListPage> {
  late String _tab = widget.initialTab == 'sent' ? 'sent' : 'received';

  @override
  Widget build(BuildContext context) {
    final String title = stringsOf(context).coopMyCooperation;
    final String needLogin = stringsOf(context).coopLoginMyCooperation;
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(coopInviteListProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        trailing: Semantics(
          button: true,
          label: stringsOf(context).coopTemplateTitle,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: () => context.push('/coop/perk-templates'),
            child: const Icon(CupertinoIcons.gift),
          ),
        ),
      ),
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
                  variant: CyTabsVariant.chip,
                  tabs: <CyTab>[
                    CyTab(key: 'received', label: stringsOf(context).coopReceived),
                    CyTab(key: 'sent', label: stringsOf(context).coopSent),
                  ],
                  active: _tab,
                  onChanged: (String k) => setState(() => _tab = k),
                ),
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CupertinoActivityIndicator()),
                  error: (Object e, _) => isCoopUnauthorized(e)
                      ? coopLoginStatus(
                          context,
                          ref,
                          message: needLogin,
                          refetch: () => ref.invalidate(coopInviteListProvider),
                        )
                      : StatusView(
                          message: stringsOf(context).coopInviteLoadFailed,
                          sub: coopErrorSub(e, context: context),
                          large: true,
                          onRetry: () => ref.invalidate(coopInviteListProvider),
                        ),
                  data: (CoopInviteList list) {
                    final bool received = _tab == 'received';
                    final rows = received ? list.received : list.sent;
                    final AsyncValue<List<CoopPoolApply>> appliesAsync = ref
                        .watch(coopPoolAppliesProvider(_tab));
                    final List<CoopPoolApply> applies =
                        appliesAsync.value ?? const <CoopPoolApply>[];
                    final bool appliesLoading = appliesAsync.isLoading;
                    final bool appliesFailed =
                        appliesAsync.hasError && applies.isEmpty;
                    // 报名只在「收到的」这一档有(真源同款:商家报名承接**我**的主题)。
                    final AsyncValue<List<CoopReceivedRegistration>> regsAsync =
                        received
                        ? ref.watch(coopReceivedRegsProvider)
                        : const AsyncValue<List<CoopReceivedRegistration>>.data(
                            <CoopReceivedRegistration>[],
                          );
                    final List<CoopReceivedRegistration> regs =
                        regsAsync.value ?? const <CoopReceivedRegistration>[];
                    final bool regsLoading = regsAsync.isLoading;
                    // ★ 不看 isEmpty:有旧快照时失败同样要出错误行。
                    final bool regsFailed = regsAsync.hasError;
                    // 官方邀约(平台→商家)只在「收到的」这一档;校验收尾页四个列表
                    // 全空才算空(真源 `index.wxml` 的空态条件同款)。
                    final AsyncValue<List<MerchantInvite>> officialAsync =
                        received
                        ? ref.watch(merchantInvitesProvider)
                        : const AsyncValue<List<MerchantInvite>>.data(
                            <MerchantInvite>[],
                          );
                    final List<MerchantInvite> official =
                        officialAsync.value ?? const <MerchantInvite>[];
                    final bool officialLoading = officialAsync.isLoading;
                    final bool officialFailed =
                        officialAsync.hasError && official.isEmpty;
                    if (rows.isEmpty &&
                        applies.isEmpty &&
                        !appliesLoading &&
                        !appliesFailed &&
                        regs.isEmpty &&
                        !regsLoading &&
                        !regsFailed &&
                        official.isEmpty &&
                        !officialLoading &&
                        !officialFailed) {
                      return StatusView(
                        message: received ? stringsOf(context).coopNoReceived : stringsOf(context).coopNoSent,
                        sub: received
                            ? stringsOf(context).coopReceivedHint
                            : stringsOf(context).coopSentHint,
                        large: true,
                      );
                    }
                    return RefreshIndicator.adaptive(
                      onRefresh: () async {
                        ref.invalidate(coopInviteListProvider);
                        ref.invalidate(coopPoolAppliesProvider(_tab));
                        ref.invalidate(coopReceivedRegsProvider);
                        ref.invalidate(merchantInvitesProvider);
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(CyTokens.pageX),
                        children: <Widget>[
                          for (final row in rows)
                            _TappableInviteTile(row: row, mine: !received),
                          if (appliesLoading && applies.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CupertinoActivityIndicator(),
                              ),
                            )
                          else if (appliesFailed)
                            _InlineLoadFailed(
                              message: received ? stringsOf(context).coopApplicationsLoadFailed : stringsOf(context).coopSentApplicationsLoadFailed,
                              keyPrefix: 'coop-applies',
                              onRetry: () =>
                                  ref.invalidate(coopPoolAppliesProvider(_tab)),
                            )
                          else if (applies.isNotEmpty) ...<Widget>[
                            Padding(
                              padding: EdgeInsets.only(
                                top: CyTokens.space3,
                                bottom: CyTokens.space2,
                              ),
                              child: CySectionTitle(stringsOf(context).coopApplications),
                            ),
                            for (final CoopPoolApply apply in applies)
                              _ApplyTile(
                                key: Key('coop-apply-${apply.applyId}'),
                                apply: apply,
                                received: received,
                                onChanged: () {
                                  ref.invalidate(coopPoolAppliesProvider(_tab));
                                  ref.invalidate(coopInviteListProvider);
                                },
                              ),
                          ],
                          if (received) ...<Widget>[
                            if (regsLoading && regs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CupertinoActivityIndicator(),
                                ),
                              ),
                            // ★ 有旧快照时刷新失败也要说话(真源 :345-351 同款)——
                            //   只留一排过期的报名,人会以为自己看到的是当前状态。
                            if (regsFailed)
                              _InlineLoadFailed(
                                message: stringsOf(context).coopRegistrationsLoadFailed,
                                keyPrefix: 'coop-regs',
                                onRetry: () =>
                                    ref.invalidate(coopReceivedRegsProvider),
                              ),
                            if (regs.isNotEmpty) ...<Widget>[
                              Padding(
                                padding: EdgeInsets.only(
                                  top: CyTokens.space3,
                                  bottom: CyTokens.space2,
                                ),
                                child: CySectionTitle(stringsOf(context).coopRegistrations),
                              ),
                              for (final CoopReceivedRegistration reg in regs)
                                _RegTile(
                                  key: Key('coop-reg-${reg.id}'),
                                  reg: reg,
                                  onChanged: () =>
                                      ref.invalidate(coopReceivedRegsProvider),
                                ),
                            ],
                            // 官方邀约(平台→商家):小程序 2026-09-15 把
                            // 「合作中心 · 邀约我的」整段收编进这一页(真源注释原话)。
                            if (officialLoading && official.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CupertinoActivityIndicator(),
                                ),
                              ),
                            if (officialFailed)
                              _InlineLoadFailed(
                                message: stringsOf(context).coopOfficialLoadFailed,
                                keyPrefix: 'coop-official',
                                onRetry: () =>
                                    ref.invalidate(merchantInvitesProvider),
                              ),
                            if (official.isNotEmpty) ...<Widget>[
                              Padding(
                                padding: EdgeInsets.only(
                                  top: CyTokens.space3,
                                  bottom: CyTokens.space2,
                                ),
                                child: CySectionTitle(stringsOf(context).coopOfficialInvites),
                              ),
                              for (final MerchantInvite invite in official)
                                MerchantInviteTile(
                                  key: Key('coop-official-${invite.id}'),
                                  invite: invite,
                                ),
                            ],
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 某一块(带队申请 / 承接报名)加载失败时的行内提示。
/// ★ 只让**这一块**落错误态:别的块好好的,不能因为一块挂了整页变白 ——
///   真源同款(两路各自结算、各自报错,`pages/coop/list/index.js:237-366`)。
class _InlineLoadFailed extends StatelessWidget {
  const _InlineLoadFailed({
    required this.message,
    required this.keyPrefix,
    required this.onRetry,
  });

  /// 「说人话、点名失败的是什么」——别写「加载失败」。
  final String message;

  /// 每块各自一套 Key,便于按块断言/点重试。
  final String keyPrefix;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CyTokens.space3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              key: Key('$keyPrefix-error'),
              message,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
          CupertinoButton(
            key: Key('$keyPrefix-retry'),
            padding: EdgeInsets.zero,
            minimumSize: const Size(88, 44),
            onPressed: onRetry,
            child: Text(stringsOf(context).retry),
          ),
        ],
      ),
    );
  }
}

/// 一张带队申请卡。动作按**我收到 / 我发出**分岔,且只在「待确认」时出现:
///   · 我收到的 → 「拒绝」(婉拒,对方可再申请)· 「回邀约」(回一张带条款的正式邀约);
///   · 我发出的 → 「撤回」。
/// 小程序 `pages/coop/list/index.wxml:91-97 / 187` 就是这两组。
class _ApplyTile extends ConsumerStatefulWidget {
  const _ApplyTile({
    super.key,
    required this.apply,
    required this.received,
    required this.onChanged,
  });

  final CoopPoolApply apply;
  final bool received;
  final VoidCallback onChanged;

  @override
  ConsumerState<_ApplyTile> createState() => _ApplyTileState();
}

class _ApplyTileState extends ConsumerState<_ApplyTile> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  bool _busy = false;

  Future<void> _run(Future<void> Function() body, String done) => RequestSessionScope.run(
    _requestScope,
    () => _runScoped(body, done),
  );

  Future<void> _runScoped(Future<void> Function() body, String done) async {
    setState(() => _busy = true);
    try {
      await body();
      widget.onChanged();
      if (!mounted) return;
      CyNativeNotice.show(context, done);
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        coopErrorSub(e, context: context),
        isError: true,
      );
      // 结果未知就回读一次:不让人对着旧状态再点一次。
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final CoopPoolApply a = widget.apply;
    final String name = (a.clubName ?? '').trim();
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopRejectApplicationName(name.isEmpty ? stringsOf(context).coopClubFallback : name),
      content: stringsOf(context).coopRejectNotifyHint,
      confirmText: stringsOf(context).coopReject,
      cancelText: stringsOf(context).coopThinkAgain,
      danger: true,
    );
    if (!ok || !mounted) return;
    // ⚠️ 键是 applyId,且商家员工处理 owner 主题时要带上行上的 scope。
    await _run(
      () => ref.read(coopApiProvider).declineApply(a.applyId, scope: a.scope),
      stringsOf(context).coopRejectedCanReapply,
    );
  }

  /// 「回邀约」的目标:主题 + 俱乐部 + 申请溯源 + 行上的归属标记,
  /// 四个都得带上 —— 少一个,发出去的邀约要么溯源不上、要么被判无权处理,
  /// 而两种失败都只说"失败"。
  String get _replyLocation {
    final CoopPoolApply a = widget.apply;
    final String scope = (a.scope ?? '').trim();
    return '/coop/invite/${a.topicId}'
        '?type=1'
        '&toId=${a.clubId}'
        '&toName=${Uri.encodeComponent(a.clubName ?? '')}'
        '&originApplyId=${a.applyId}'
        '${scope.isEmpty ? '' : '&scope=$scope'}';
  }

  Future<void> _withdraw() async {
    final CoopPoolApply a = widget.apply;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopWithdrawApplicationName(coopApplyTitle(context, a)),
      content: stringsOf(context).coopWithdrawHint,
      confirmText: stringsOf(context).coopWithdraw,
    );
    if (!ok || !mounted) return;
    // ⚠️ 撤回的键是 **topicId**(后端按主题撤),不是 applyId。
    await _run(() => ref.read(coopApiProvider).withdraw(a.topicId), stringsOf(context).coopWithdrawn);
  }

  @override
  Widget build(BuildContext context) {
    final CoopPoolApply a = widget.apply;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String peer = coopApplyPeer(context, a, received: widget.received);
    final String date = a.dateText;
    final String sub = coopApplySub(context, a, received: widget.received);

    return Container(
      margin: const EdgeInsets.only(bottom: CyTokens.space3),
      padding: const EdgeInsets.all(CyTokens.space3),
      decoration: BoxDecoration(
        color: p.bgSurface,
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CyTag(label: coopApplicationStatus(context, a.status)),
              const Spacer(),
              if (peer.isNotEmpty)
                Text(peer, style: t.bodySmall?.copyWith(color: p.textTertiary)),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Row(
            children: <Widget>[
              Expanded(child: Text(coopApplyTitle(context, a), style: t.titleSmall)),
              if (date.isNotEmpty)
                Text(date, style: t.bodySmall?.copyWith(color: p.textTertiary)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              sub,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: CyTokens.space1),
            child: Text(
              coopApplyTerms(context, a),
              style: t.bodySmall?.copyWith(color: p.textTertiary),
            ),
          ),
          if (a.isPending) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Row(
              children: <Widget>[
                if (widget.received) ...<Widget>[
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-apply-decline-${a.applyId}'),
                      label: stringsOf(context).coopReject,
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _decline,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-apply-reply-${a.applyId}'),
                      label: stringsOf(context).coopBackToInvite,
                      onPressed: _busy || a.clubId == null
                          ? null
                          : () => context.push(_replyLocation),
                    ),
                  ),
                ] else
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-apply-withdraw-${a.applyId}'),
                      label: stringsOf(context).coopWithdrawApplication,
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _withdraw,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 一张承接报名卡(商家报名承接我主题的节点)。
///
/// 两个动作与真源一一对应(都是 `registrationId` 为键):
///   · 「婉拒」→ `/api/coop/candidates/reject`(报名只表意向,对方可修改后重新报名);
///   · 「确认占槽」→ `/api/coop/candidates/confirm`,**只占位不成单**(§3.6)——
///     按下去之后还要发一张带条款的邀约,所以成功不是结束,而是把人引到下一步。
/// ⚠️ 两条都只在**待调配**(auditStatus 0)时出现:已中标/已落选再摆按钮,点下去后端必拒。
/// 真源 `pages/coop/list/index.js:668-700`(婉拒)/ :614-665(确认占槽),
/// 卡片字段与按钮条件见 `index.wxml:100-121`。
class _RegTile extends ConsumerStatefulWidget {
  const _RegTile({super.key, required this.reg, required this.onChanged});

  final CoopReceivedRegistration reg;
  final VoidCallback onChanged;

  @override
  ConsumerState<_RegTile> createState() => _RegTileState();
}

class _RegTileState extends ConsumerState<_RegTile> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  bool _busy = false;

  /// 动作统一收口:成功报结果、失败透传后端原话,两种情况都回读列表 ——
  /// 结果未知时让人对着旧状态再点一次,是最容易点出重复操作的一种。
  /// ★ 回到 false 时忙态已经收掉,调用方可以接着开下一个弹层(不会一直转着)。
  Future<bool> _run(Future<void> Function() body, String done) => RequestSessionScope.run(
    _requestScope,
    () => _runScoped(body, done),
  );

  Future<bool> _runScoped(Future<void> Function() body, String done) async {
    setState(() => _busy = true);
    try {
      await body();
      widget.onChanged();
      if (!mounted) return true;
      CyNativeNotice.show(context, done);
      return true;
    } catch (e) {
      if (mounted) {
        CyNativeNotice.show(
          context,
          coopErrorSub(e, context: context),
          isError: true,
        );
      }
      widget.onChanged();
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final CoopReceivedRegistration reg = widget.reg;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopDeclineRegistrationName(reg.name),
      content: stringsOf(context).coopRejectRegistrationHint,
      confirmText: stringsOf(context).coopDecline,
      cancelText: stringsOf(context).coopThinkAgain,
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(coopApiProvider).rejectCandidate(reg.id),
      stringsOf(context).coopDeclinedName(reg.name),
    );
  }

  /// ★ 占槽 ≠ 成交:后端不生成合作单,真正成单要靠接下来那张带条款的邀约。
  ///   所以成功后必须把人引到发邀约,不能只报一句「已确认」。
  Future<void> _confirm() async {
    final CoopReceivedRegistration reg = widget.reg;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopConfirmPlaceName(reg.name),
      content: stringsOf(context).coopConfirmCandidateTerms,
      confirmText: stringsOf(context).coopConfirm,
    );
    if (!ok || !mounted) return;
    final bool done = await _run(
      () => ref.read(coopApiProvider).confirmCandidate(reg.id),
      stringsOf(context).coopConfirmedPlaceName(reg.name),
    );
    if (!done || !mounted || reg.memberId == null) return;
    final bool go = await cyConfirm(
      context,
      title: stringsOf(context).coopSendInviteNext,
      content: stringsOf(context).coopSendTermsInvitation(reg.name),
      confirmText: stringsOf(context).coopSendInvite,
      cancelText: stringsOf(context).coopLater,
    );
    if (!go || !mounted) return;
    context.push(
      '/coop/invite/${reg.topicId}?type=0'
      '&toId=${reg.memberId}'
      '&toName=${Uri.encodeComponent(reg.name)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final CoopReceivedRegistration reg = widget.reg;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String place = reg.placeText;

    return Opacity(
      // 已落选整行压暗(真源 `decorateReg` 的 dim)。
      opacity: reg.dim ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: CyTokens.space3),
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: p.bgSurface,
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          border: Border.all(color: p.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CyTag(label: coopAuditStatus(context, reg.auditStatus)),
                const Spacer(),
                Flexible(
                  child: Text(
                    reg.topicTitle,
                    style: t.bodySmall?.copyWith(color: p.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CyTokens.space2),
            Row(
              children: <Widget>[
                CyAvatar(
                  url: reg.merchantLogo,
                  fallback: reg.name.characters.first,
                ),
                const SizedBox(width: CyTokens.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(reg.name, style: t.titleSmall),
                      Text(
                        reg.meta,
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (place.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  place,
                  style: t.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ),
            // ★ 只有待调配才给按钮(真源 `wx:if="{{item.audit===0}}"`)。
            if (reg.actionable) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Row(
                children: <Widget>[
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-reg-reject-${reg.id}'),
                      label: stringsOf(context).coopDecline,
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _reject,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-reg-confirm-${reg.id}'),
                      label: stringsOf(context).coopConfirmPlace,
                      loading: _busy,
                      onPressed: _busy ? null : _confirm,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 可整卡点开的邀约行 —— 点进协作详情(小程序 `pages/coop/list/index.wxml` 两侧的
/// 整张卡都是 `bindtap="goInviteDetail"`)。
///
/// ⚠️ 点击层包在 [_InviteTile] **外面**是有意的:[_InviteTile] 是纯展示件,
///   把路由动作放进它里面,一次改动就要把它整棵子树再缩进两级。
///   卡里那些动作按钮各自吃掉自己的点击,不受这里影响。
class _TappableInviteTile extends StatelessWidget {
  const _TappableInviteTile({required this.row, required this.mine});

  final CoopInviteRow row;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: stringsOf(context).coopViewDetailName(row.topicText.isEmpty ? stringsOf(context).coopThisInvitation : row.topicText),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (row.id <= 0) {
            // 编号没解析出来时**不要**跳:详情是拿编号去服务端问的,
            // 跳到一页只会说「打不开」比就地说明更绕。
            CyNativeNotice.show(context, stringsOf(context).coopInvalidInviteId, isError: true);
            return;
          }
          context.push(
            '/coop/invite-detail?inviteId=${row.id}'
            '&box=${mine ? 'sent' : 'received'}',
          );
        },
        child: _InviteTile(row: row, mine: mine),
      ),
    );
  }
}

class _InviteTile extends ConsumerStatefulWidget {
  const _InviteTile({required this.row, required this.mine});
  final CoopInviteRow row;

  /// true = 我发出的一侧(sent),false = 我收到的一侧(received)。
  final bool mine;

  @override
  ConsumerState<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends ConsumerState<_InviteTile> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  bool _busy = false;

  Future<void> _payDeposit() => RequestSessionScope.run(_requestScope, _payDepositScoped);

  Future<void> _payDepositScoped() async {
    if (_busy || !_requestScope.isCurrent()) return;
    if (!ref.read(coopDepositPaymentConfiguredProvider)) {
      CyNativeNotice.show(context, stringsOf(context).coopPaymentUnconfigured, isError: true);
      return;
    }
    final WechatPaymentGate gate = ref.read(coopDepositPaymentGateProvider);
    if (!gate.tryAcquire()) {
      CyNativeNotice.show(context, stringsOf(context).coopPaymentBusy, isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final Map<String, String> params = await ref
          .read(coopApiProvider)
          .createDeposit(widget.row.id);
      if (!WechatPayment.hasCompleteAppParams(params)) {
        if (!mounted || !_requestScope.isCurrent()) return;
        CyNativeNotice.show(context, stringsOf(context).coopPaymentIncomplete, isError: true);
        return;
      }

      await ref.read(coopDepositPayProvider)(params);
      if (!mounted || !_requestScope.isCurrent()) return;

      final String paymentStatus = await ref
          .read(coopApiProvider)
          .depositStatus(widget.row.id);
      if (!mounted || !_requestScope.isCurrent()) return;
      switch (paymentStatus) {
        case 'success':
          CyNativeNotice.show(context, stringsOf(context).coopDepositReceived);
        case 'pending':
          CyNativeNotice.show(context, stringsOf(context).coopDepositPending);
        case 'failed':
          CyNativeNotice.show(context, stringsOf(context).coopDepositFailed, isError: true);
        default:
          CyNativeNotice.show(context, stringsOf(context).coopDepositUnknown, isError: true);
      }

      // 微信回执不是入账真源。四种 SDK 结果全部先回读
      // deposit/status，再刷新列表中的 depositOwed 真值。
      ref.invalidate(coopInviteListProvider);
      try {
        await ref.read(coopInviteListProvider.future);
      } catch (_) {
        // 刷新失败由列表的 error state 接管，不篡改支付回执。
      }
    } catch (e) {
      if (!mounted || !_requestScope.isCurrent()) return;
      CyNativeNotice.show(
        context,
        coopErrorSub(e, context: context),
        isError: true,
      );
    } finally {
      gate.release();
      if (mounted && _requestScope.isCurrent()) setState(() => _busy = false);
    }
  }

  /// 重试保证金退款 —— 涉资链路状态未知时的兜底入口(真源
  /// `pages/coop/list/index.wxml:74/205`:独立于已接受卡的动作区渲染,
  /// 判据 `depositRefundPending && !legacyReadonly`)。
  /// 回执/失败文案全部由 [CoopApi.retryDepositRefund] 按真源三分支给,
  /// 这里只透传;成功后照真源 `that.load()` 重拉列表刷新退款真值。
  Future<void> _retryDepositRefund() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String receipt = await ref
          .read(coopApiProvider)
          .retryDepositRefund(widget.row.id);
      if (!mounted) return;
      CyNativeNotice.show(context, receipt);
      ref.invalidate(coopInviteListProvider);
      try {
        await ref.read(coopInviteListProvider.future);
      } catch (_) {
        // 刷新失败由列表的 error state 接管,不篡改退款回执。
      }
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        coopErrorSub(e, context: context),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact() => RequestSessionScope.run(
    _requestScope,
    () => _contactScoped(),
  );

  Future<void> _contactScoped() async {
    setState(() => _busy = true);
    try {
      final conversationId = await ref
          .read(coopApiProvider)
          .contact(widget.row.id);
      if (!mounted) return;
      context.push('/im/chat/$conversationId');
    } catch (e) {
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        coopErrorSub(e, context: context),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 接受 / 拒绝 / 取消 —— `POST /api/coop/handle`。
  ///
  /// ★★ 后端 `ApiCoopController.handle` 写死:
  ///   「接受/拒绝须**受邀方**本人;取消须**发起方**本人」。
  ///   ⇒ 1/2 与 3 是**两个角色**的动作,不是同一件事的两份实现。
  ///   前端的 allowed() 只是礼貌,算错只会多显示一个按钮,不会越权。
  ///
  /// ★ 只有「取消一个**已接受**的合作」要填理由(后端拒空)。
  ///   对所有取消都强制填,会让「撤回一个还没人理的邀请」变得很重。
  Future<void> _handle(CoopHandleAction action) => RequestSessionScope.run(
    _requestScope,
    () => _handleScoped(action),
  );

  Future<void> _handleScoped(CoopHandleAction action) async {
    String? reason;
    if (CoopHandleAction.needsReason(action, widget.row.status)) {
      reason = await showCupertinoDialog<String>(
        context: context,
        builder: (BuildContext c) => CoopReasonDialog(action: action),
      );
      // 取消对话框返回 null;空理由后端会拒,这里提前挡住。
      if (reason == null || reason.trim().isEmpty) return;
    } else {
      // 纯文本确认走 cyConfirm(门禁 no_plain_alert_dialog 拦着裸 AlertDialog)。
      final bool ok = await cyConfirm(
        context,
        title: stringsOf(context).coopActionInvite(coopActionLabel(context, action)),
        confirmText: coopActionLabel(context, action),
        cancelText: stringsOf(context).coopThinkAgain,
        danger: action != CoopHandleAction.accept,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(coopApiProvider)
          .handleInvite(
            inviteId: widget.row.id,
            action: action,
            reason: reason,
          );
      ref.invalidate(coopInviteListProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).coopActionDone(coopActionLabel(context, action)));
    } catch (e) {
      if (!mounted) return;
      // 后端的话原样透出 —— 「该邀请无法取消」这类判据由它说。
      CyNativeNotice.show(
        context,
        coopErrorSub(e, context: context),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPerkPick() async {
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.18,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              CoopPerkPickSheet(
                inviteId: widget.row.id,
                scrollController: scrollController,
              ),
    );
  }

  Future<void> _review() async {
    // 收到的一侧:被评人是发起方(fromId,恒为会员)。
    // 我发出的一侧:被评人是受邀方,只有 merchant 有 memberId 语义,club 没有——
    //   和小程序一致,俱乐部邀约不给评价入口。
    final int? toId = widget.mine
        ? (widget.row.toType == 'merchant' ? widget.row.toId : null)
        : widget.row.fromId;
    final int? topicId = widget.row.topicId;
    if (toId == null || topicId == null) {
      CyNativeNotice.show(context, stringsOf(context).coopReviewUnavailable);
      return;
    }
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.26,
      scrollableBuilder:
          (BuildContext context, ScrollController scrollController) =>
              CoopReviewSheet(
                topicId: topicId,
                toId: toId,
                scrollController: scrollController,
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final textTheme = Theme.of(context).textTheme;
    final dim = r.status == 4 || r.status == 5;
    // 评价只在「合作已接受」且不是历史只读节点时给出;两侧口径与小程序一致。
    final canReview = r.status == 1 && !r.legacyReadonly;

    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: CyTokens.space3),
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
                Expanded(child: Text(coopDetailInviteType(context, r), style: textTheme.titleSmall)),
                CyTag(label: coopInvitationStatus(context, r.status)),
              ],
            ),
            if ((r.partnerName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space1),
                child: Text(r.partnerName!, style: textTheme.bodyMedium),
              ),
            if (coopDetailTopic(context, r).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  coopDetailTopic(context, r),
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
            if (r.partnerContact.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  r.partnerContact,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textSecondary,
                  ),
                ),
              ),
            if (coopDetailTerms(context, r) != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  coopDetailTerms(context, r)!,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ),
            if ((r.message ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(r.message!.trim(), style: textTheme.bodySmall),
              ),
            // 发出卡 status 2 = 被对方拒绝:真源 wxml:190 先给这一句事实,
            // 下面唯一的动作就是「再邀别人」。收到的侧不显示 —— 那句在那
            // 是「我拒绝的」,角色反了就不成立。
            if (r.status == 2 && widget.mine)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  stringsOf(context).coopPeerRejected,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ),
            if (r.status == 0 && !r.decisionReady)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  stringsOf(context).coopInviteIncomplete,
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).statusWarning,
                  ),
                ),
              ),
            // 待确认:受邀方给接受/拒绝,发起方给取消。
            // ⚠️ decisionReady 为 false 时上面已经说了「信息不完整暂不能处理」——
            //   那时不给按钮,否则点下去必撞后端校验。
            if (r.status == 0 && r.decisionReady) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: <Widget>[
                  for (final CoopHandleAction a
                      in CoopHandleAction.availableFor(
                        inviteStatus: r.status,
                        isFrom: widget.mine,
                        isTo: !widget.mine,
                      ))
                    CyNativeButton(
                      key: Key('coop-action-${a.name}-${r.id}'),
                      label: coopActionLabel(context, a),
                      role: a == CoopHandleAction.accept
                          ? CyNativeButtonRole.primary
                          : (a == CoopHandleAction.reject
                                ? CyNativeButtonRole.destructive
                                : CyNativeButtonRole.secondary),
                      onPressed: _busy ? null : () => _handle(a),
                    ),
                ],
              ),
            ],
            if (r.status == 1 && !r.legacyReadonly) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: <Widget>[
                  if (r.depositOwed)
                    CyNativeButton(
                      key: Key('coop-deposit-${r.id}'),
                      label: stringsOf(context).coopPayDeposit,
                      loading: _busy,
                      onPressed: _busy ? null : _payDeposit,
                    ),
                  CyNativeButton(
                    label: stringsOf(context).coopContactPartner,
                    role: CyNativeButtonRole.secondary,
                    loading: _busy,
                    onPressed: _busy ? null : _contact,
                  ),
                  // 供给申报是受邀方(接单一方)的动作:我收到的邀约 = 我是受邀方。
                  if (!widget.mine)
                    CyNativeButton(
                      label: stringsOf(context).coopDeclareSupply,
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _openPerkPick,
                    ),
                  if (canReview)
                    CyNativeButton(
                      label: stringsOf(context).coopReview,
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _review,
                    ),
                  // 已接受的合作,双方都能取消,但要填理由(后端拒空)。
                  if (CoopHandleAction.cancel.allowed(
                    inviteStatus: r.status,
                    isFrom: widget.mine,
                    isTo: !widget.mine,
                  ))
                    CyNativeButton(
                      key: Key('coop-action-cancel-${r.id}'),
                      label: stringsOf(context).coopCancelCooperation,
                      role: CyNativeButtonRole.destructive,
                      loading: _busy,
                      onPressed: _busy
                          ? null
                          : () => _handle(CoopHandleAction.cancel),
                    ),
                ],
              ),
            ],
            // 保证金退款重试:独立动作区,不挂在「已接受」块下 ——
            // 真源 wxml:74/205 两边同款 wx:if,只认
            // depositRefundPending && !legacyReadonly(退款挂着时
            // status 可能已不是 1)。(真源还排除 identityError,App 的
            // CoopInviteRow 没解析该字段 —— 已记偏差。)
            if (r.depositRefundPending && !r.legacyReadonly) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: <Widget>[
                  CyNativeButton(
                    key: Key('coop-retry-refund-${r.id}'),
                    label: _busy ? stringsOf(context).coopRefundRetryBusy : stringsOf(context).coopRetryDepositRefund,
                    role: CyNativeButtonRole.secondary,
                    loading: _busy,
                    onPressed: _busy ? null : _retryDepositRefund,
                  ),
                ],
              ),
            ],
            // 「再邀别人」—— 真源 pages/coop/list/index.js:617-621 /
            // wxml:195-197:发出的邀约被拒(status 2)且带着主题、非 legacy
            // 只读卡,唯一去处是找商家挑人(coop/nearby),topicId 一路带着 ——
            // 候选池页已下线,这条链是断点清单里的「孤岛链」入口端。
            // ★ 只给发出的一侧:收到侧的 status 2 是「我拒了别人」,
            //   主题不是我的,再邀等于替别人招承接方。
            if (widget.mine &&
                r.status == 2 &&
                (r.topicId ?? 0) > 0 &&
                !r.legacyReadonly) ...<Widget>[
              const SizedBox(height: CyTokens.space3),
              Wrap(
                spacing: CyTokens.space2,
                runSpacing: CyTokens.space2,
                children: <Widget>[
                  CyNativeButton(
                    key: Key('coop-reinvite-${r.id}'),
                    label: stringsOf(context).coopInviteOthers,
                    role: CyNativeButtonRole.secondary,
                    onPressed: () =>
                        context.push('/coop/nearby?topicId=${r.topicId}'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 供给申报浮层。★ 列表卡上的「申报供给」与协作详情页的同一行**共用这一份实现**
/// (见 `coop_invite_detail_page.dart` 顶部)—— 涉资口径不许有第二份。
class CoopPerkPickSheet extends ConsumerStatefulWidget {
  const CoopPerkPickSheet({
    super.key,
    required this.inviteId,
    required this.scrollController,
  });
  final int inviteId;
  final ScrollController scrollController;

  @override
  ConsumerState<CoopPerkPickSheet> createState() => _PerkPickSheetState();
}

class _PerkPickSheetState extends ConsumerState<CoopPerkPickSheet> {
  late final RequestSessionScope _requestScope;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<CoopPerkTemplate> _templates = const <CoopPerkTemplate>[];
  final Set<int> _checked = <int>{};

  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(coopApiProvider);
      final tplRows = await api.perkTemplates();
      final attached = await api.perksOfInvite(widget.inviteId);
      final templates = tplRows
          .map(CoopPerkTemplate.fromJson)
          .where((t) => t.usable)
          .toList();
      // 预勾选:按名称匹配该邀约已申报的供给(与小程序同判据 —— 后端只给了申报快照,
      // 没有回传模板 id)。
      final attachedNames = attached
          .map((p) => p['name'] as String?)
          .whereType<String>()
          .toSet();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _checked
          ..clear()
          ..addAll(
            templates
                .where((t) => attachedNames.contains(t.name))
                .map((t) => t.id),
          );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = coopErrorSub(e, context: context);
        _loading = false;
      });
    }
  }

  Future<void> _submit() => RequestSessionScope.run(
    _requestScope,
    () => _submitScoped(),
  );

  Future<void> _submitScoped() async {
    setState(() => _saving = true);
    try {
      final count = await ref
          .read(coopApiProvider)
          .attachPerks(
            inviteId: widget.inviteId,
            templateIds: _checked.toList(),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).coopDeclaredCount(count));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = coopErrorSub(e, context: context);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).coopDeclareCurrentSupply),
        leading: CupertinoButton(
          key: const Key('coop-perk-pick-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).cancel),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(CyTokens.pageX),
          children: <Widget>[
            const SizedBox(height: CyTokens.space1),
            Text(
              stringsOf(context).coopSupplyPurpose,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: CyTokens.space3),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                child: Center(child: CupertinoActivityIndicator()),
              )
            else if (_templates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: CyTokens.space4),
                child: Text(stringsOf(context).coopSupplyEmpty),
              )
            else
              ..._templates.map((CoopPerkTemplate t) {
                final selected = _checked.contains(t.id);
                final meta = <String>[
                  if (t.unitCost != null) stringsOf(context).coopTemplateCost(t.unitCost!.toStringAsFixed(2)),
                  if (t.quota != null) stringsOf(context).coopSupplyQuota(t.quota!),
                ].join(' · ');
                return Semantics(
                  selected: selected,
                  button: true,
                  label: '${coopPerkType(context, t.perkType)} · ${t.name}',
                  child: CupertinoButton(
                    key: Key('coop-perk-pick-${t.id}'),
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(
                      vertical: CyTokens.space2,
                    ),
                    alignment: Alignment.centerLeft,
                    foregroundColor: palette.textPrimary,
                    onPressed: () => setState(
                      () =>
                          selected ? _checked.remove(t.id) : _checked.add(t.id),
                    ),
                    child: Row(
                      children: <Widget>[
                        ExcludeSemantics(
                          child: CupertinoCheckbox(
                            value: selected,
                            onChanged: (bool? value) => setState(
                              () => value == true
                                  ? _checked.add(t.id)
                                  : _checked.remove(t.id),
                            ),
                          ),
                        ),
                        const SizedBox(width: CyTokens.space2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('${coopPerkType(context, t.perkType)} · ${t.name}'),
                              if (meta.isNotEmpty)
                                Text(
                                  meta,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: palette.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  _error!,
                  style: TextStyle(color: CyPalette.of(context).statusDanger),
                ),
              ),
            const SizedBox(height: CyTokens.space3),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                key: const Key('coop-perk-submit'),
                minimumSize: const Size.fromHeight(44),
                onPressed: (_loading || _saving) ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CupertinoActivityIndicator(),
                      )
                    : Text(stringsOf(context).coopConfirmSupply),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 合作互评浮层。列表卡与协作详情页共用(同上)。
class CoopReviewSheet extends ConsumerStatefulWidget {
  const CoopReviewSheet({
    super.key,
    required this.topicId,
    required this.toId,
    required this.scrollController,
  });
  final int topicId;
  final int toId;
  final ScrollController scrollController;

  @override
  ConsumerState<CoopReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<CoopReviewSheet> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  int _rating = 5;
  final _commentCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() => RequestSessionScope.run(
    _requestScope,
    () => _submitScoped(),
  );

  Future<void> _submitScoped() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(coopApiProvider)
          .saveReview(
            topicId: widget.topicId,
            toId: widget.toId,
            rating: _rating,
            content: _commentCtrl.text.trim().isEmpty
                ? null
                : _commentCtrl.text.trim(),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).coopReviewed);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = coopErrorSub(e, context: context);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyPalette.of(context);
    return CupertinoPageScaffold(
      backgroundColor: palette.bgPage,
      navigationBar: CupertinoNavigationBar(
        middle: Text(stringsOf(context).coopReviewTitle),
        leading: CupertinoButton(
          key: const Key('coop-review-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).cancel),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(CyTokens.pageX),
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(5, (int i) {
                final star = i + 1;
                void select() => setState(() => _rating = star);
                return Semantics(
                  button: true,
                  label: stringsOf(context).coopStarCount(star),
                  value: star == _rating ? stringsOf(context).coopSelected : stringsOf(context).coopNotSelected,
                  selected: star == _rating,
                  onTap: select,
                  child: ExcludeSemantics(
                    child: CupertinoButton(
                      key: Key('coop-review-star-$star'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: select,
                      child: Icon(
                        star <= _rating
                            ? CupertinoIcons.star_fill
                            : CupertinoIcons.star,
                        color: CupertinoColors.systemYellow,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: CyTokens.space3),
            CupertinoTextField(
              key: const Key('coop-review-comment'),
              controller: _commentCtrl,
              maxLines: 3,
              placeholder: stringsOf(context).coopReviewPlaceholder,
              textInputAction: TextInputAction.done,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.bgSurface,
                border: Border.all(color: palette.borderSubtle),
                borderRadius: BorderRadius.circular(CyTokens.radiusMd),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  _error!,
                  style: TextStyle(color: CyPalette.of(context).statusDanger),
                ),
              ),
            const SizedBox(height: CyTokens.space4),
            CupertinoButton.filled(
              key: const Key('coop-review-submit'),
              minimumSize: const Size.fromHeight(44),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CupertinoActivityIndicator(),
                    )
                  : Text(stringsOf(context).coopSubmit),
            ),
          ],
        ),
      ),
    );
  }
}

/// 取消一个已接受的合作时填理由。★ 后端拒空,所以这里也不放空的过去。
class CoopReasonDialog extends StatefulWidget {
  const CoopReasonDialog({
    super.key,
    required this.action,
    this.content,
    this.placeholder,
    this.confirmText,
  });

  final CoopHandleAction action;

  /// 输入框上方的一句说明。默认不显示 —— 各页的确认语不同
  /// (列表撤回:「对方还没处理,取消后这条邀约作废。」)
  final String? content;

  final String? placeholder;

  /// 确认键文案。默认用动作名(「取消」)。
  final String? confirmText;

  @override
  State<CoopReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<CoopReasonDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool empty = _c.text.trim().isEmpty;
    return CupertinoAlertDialog(
      title: Text(stringsOf(context).coopActionCollaboration(coopActionLabel(context, widget.action))),
      content: Padding(
        padding: const EdgeInsets.only(top: CyTokens.space2),
        child: Column(
          children: <Widget>[
            CupertinoTextField(
              controller: _c,
              key: const Key('coop-cancel-reason'),
              autofocus: true,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              placeholder: widget.placeholder ?? stringsOf(context).coopReasonPlaceholder,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: CyTokens.space1),
            Text(widget.content ?? stringsOf(context).coopReasonVisible),
          ],
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(stringsOf(context).coopThinkAgain),
        ),
        CupertinoDialogAction(
          key: const Key('coop-cancel-confirm'),
          isDestructiveAction: widget.action != CoopHandleAction.accept,
          // 空理由直接按不动 —— 提交了也是被后端拒,不如当场说清。
          onPressed: empty ? null : () => Navigator.of(context).pop(_c.text),
          child: Text(widget.confirmText ?? coopActionLabel(context, widget.action)),
        ),
      ],
    );
  }
}
