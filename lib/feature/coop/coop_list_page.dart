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
    const String title = '我的合作';
    const String needLogin = '登录后查看我的合作';
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
        middle: const Text(title),
        trailing: Semantics(
          button: true,
          label: '常备权益',
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
                  tabs: const <CyTab>[
                    CyTab(key: 'received', label: '收到的'),
                    CyTab(key: 'sent', label: '我发出的'),
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
                          message: '协作邀请没加载出来',
                          sub: coopErrorSub(e),
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
                        message: received ? '还没有收到协作邀请' : '还没有发出协作邀请',
                        sub: received
                            ? '别的商家或俱乐部发来的协作邀请、对你主题的带队申请会显示在这里'
                            : '你向商家或俱乐部发出的协作邀请、带队申请会显示在这里',
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
                              message: received ? '带队申请没加载出来' : '我发出的申请没加载出来',
                              keyPrefix: 'coop-applies',
                              onRetry: () =>
                                  ref.invalidate(coopPoolAppliesProvider(_tab)),
                            )
                          else if (applies.isNotEmpty) ...<Widget>[
                            const Padding(
                              padding: EdgeInsets.only(
                                top: CyTokens.space3,
                                bottom: CyTokens.space2,
                              ),
                              child: CySectionTitle('带队申请'),
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
                                message: '承接报名没加载出来',
                                keyPrefix: 'coop-regs',
                                onRetry: () =>
                                    ref.invalidate(coopReceivedRegsProvider),
                              ),
                            if (regs.isNotEmpty) ...<Widget>[
                              const Padding(
                                padding: EdgeInsets.only(
                                  top: CyTokens.space3,
                                  bottom: CyTokens.space2,
                                ),
                                child: CySectionTitle('承接报名'),
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
                                message: '官方邀约没加载出来',
                                keyPrefix: 'coop-official',
                                onRetry: () =>
                                    ref.invalidate(merchantInvitesProvider),
                              ),
                            if (official.isNotEmpty) ...<Widget>[
                              const Padding(
                                padding: EdgeInsets.only(
                                  top: CyTokens.space3,
                                  bottom: CyTokens.space2,
                                ),
                                child: CySectionTitle('官方邀约'),
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
            child: const Text('重试'),
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
  bool _busy = false;

  Future<void> _run(Future<void> Function() body, String done) async {
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
        e.toString().replaceFirst('Exception: ', ''),
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
      title: '拒绝「${name.isEmpty ? '该俱乐部' : name}」的带队申请?',
      content: '对方会收到通知,之后仍可重新申请。',
      confirmText: '拒绝',
      cancelText: '再想想',
      danger: true,
    );
    if (!ok || !mounted) return;
    // ⚠️ 键是 applyId,且商家员工处理 owner 主题时要带上行上的 scope。
    await _run(
      () => ref.read(coopApiProvider).declineApply(a.applyId, scope: a.scope),
      '已拒绝的申请对方可以再发一次',
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
      title: '撤回「${a.titleText}」的带队申请?',
      content: '撤回后商家将不再看到这条申请,之后可以重新申请。',
      confirmText: '撤回',
    );
    if (!ok || !mounted) return;
    // ⚠️ 撤回的键是 **topicId**(后端按主题撤),不是 applyId。
    await _run(() => ref.read(coopApiProvider).withdraw(a.topicId), '已撤回');
  }

  @override
  Widget build(BuildContext context) {
    final CoopPoolApply a = widget.apply;
    final CyPalette p = CyPalette.of(context);
    final TextTheme t = Theme.of(context).textTheme;
    final String peer = a.peerText(received: widget.received);
    final String date = a.dateText;
    final String sub = a.subText(received: widget.received);

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
              CyTag(label: a.statusText),
              const Spacer(),
              if (peer.isNotEmpty)
                Text(peer, style: t.bodySmall?.copyWith(color: p.textTertiary)),
            ],
          ),
          const SizedBox(height: CyTokens.space1),
          Row(
            children: <Widget>[
              Expanded(child: Text(a.titleText, style: t.titleSmall)),
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
              a.termsText,
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
                      label: '拒绝',
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _decline,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-apply-reply-${a.applyId}'),
                      label: '回邀约',
                      onPressed: _busy || a.clubId == null
                          ? null
                          : () => context.push(_replyLocation),
                    ),
                  ),
                ] else
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-apply-withdraw-${a.applyId}'),
                      label: '撤回申请',
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
  bool _busy = false;

  /// 动作统一收口:成功报结果、失败透传后端原话,两种情况都回读列表 ——
  /// 结果未知时让人对着旧状态再点一次,是最容易点出重复操作的一种。
  /// ★ 回到 false 时忙态已经收掉,调用方可以接着开下一个弹层(不会一直转着)。
  Future<bool> _run(Future<void> Function() body, String done) async {
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
          e.toString().replaceFirst('Exception: ', ''),
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
      title: '婉拒「${reg.name}」的承接报名?',
      content: '对方会收到通知,可修改后重新报名。',
      confirmText: '婉拒',
      cancelText: '再想想',
      danger: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(coopApiProvider).rejectCandidate(reg.id),
      '已婉拒「${reg.name}」',
    );
  }

  /// ★ 占槽 ≠ 成交:后端不生成合作单,真正成单要靠接下来那张带条款的邀约。
  ///   所以成功后必须把人引到发邀约,不能只报一句「已确认」。
  Future<void> _confirm() async {
    final CoopReceivedRegistration reg = widget.reg;
    final bool ok = await cyConfirm(
      context,
      title: '确认「${reg.name}」占住这个候选位置?',
      content: '同地点其他待调配报名将自动落选。\n确认后需再向他发出带条款的合作邀约,他接受后才成合作单。',
      confirmText: '确认',
    );
    if (!ok || !mounted) return;
    final bool done = await _run(
      () => ref.read(coopApiProvider).confirmCandidate(reg.id),
      '已确认「${reg.name}」占住候选位置',
    );
    if (!done || !mounted || reg.memberId == null) return;
    final bool go = await cyConfirm(
      context,
      title: '已占位,接着发邀约',
      content: '现在给「${reg.name}」发一张带分账条款的邀约,他接受后才成合作单。',
      confirmText: '去发邀约',
      cancelText: '稍后',
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
                CyTag(label: reg.auditText),
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
                      label: '婉拒',
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _reject,
                    ),
                  ),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(
                    child: CyNativeButton(
                      key: Key('coop-reg-confirm-${reg.id}'),
                      label: '确认占槽',
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
      label: '查看 ${row.topicText.isEmpty ? '这条邀约' : row.topicText} 的协作详情',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (row.id <= 0) {
            // 编号没解析出来时**不要**跳:详情是拿编号去服务端问的,
            // 跳到一页只会说「打不开」比就地说明更绕。
            CyNativeNotice.show(context, '邀约标识无法确认，请刷新后重试', isError: true);
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
  bool _busy = false;

  Future<void> _payDeposit() async {
    if (_busy) return;
    if (!ref.read(coopDepositPaymentConfiguredProvider)) {
      CyNativeNotice.show(context, '微信支付尚未配置，请稍后再试', isError: true);
      return;
    }
    final WechatPaymentGate gate = ref.read(coopDepositPaymentGateProvider);
    if (!gate.tryAcquire()) {
      CyNativeNotice.show(context, '已有一笔支付正在处理中，请完成后再试', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final Map<String, String> params = await ref
          .read(coopApiProvider)
          .createDeposit(widget.row.id);
      if (!WechatPayment.hasCompleteAppParams(params)) {
        if (!mounted) return;
        CyNativeNotice.show(context, '支付参数不完整，请稍后重试', isError: true);
        return;
      }

      await ref.read(coopDepositPayProvider)(params);
      if (!mounted) return;

      final String paymentStatus = await ref
          .read(coopApiProvider)
          .depositStatus(widget.row.id);
      if (!mounted) return;
      switch (paymentStatus) {
        case 'success':
          CyNativeNotice.show(context, '保证金已到账');
        case 'pending':
          CyNativeNotice.show(context, '保证金支付处理中，请稍后刷新');
        case 'failed':
          CyNativeNotice.show(context, '保证金支付未完成，可稍后重试', isError: true);
        default:
          CyNativeNotice.show(context, '保证金状态待确认，请稍后刷新', isError: true);
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
      if (!mounted) return;
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      gate.release();
      if (mounted) setState(() => _busy = false);
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
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact() async {
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
        e.toString().replaceFirst('Exception: ', ''),
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
  Future<void> _handle(CoopHandleAction action) async {
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
        title: '${action.label}这条合作邀约?',
        confirmText: action.label,
        cancelText: '再想想',
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
      CyNativeNotice.show(context, '已${action.label}');
    } catch (e) {
      if (!mounted) return;
      // 后端的话原样透出 —— 「该邀请无法取消」这类判据由它说。
      CyNativeNotice.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
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
      CyNativeNotice.show(context, '该合作暂不可评价');
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
                Expanded(child: Text(r.typeText, style: textTheme.titleSmall)),
                CyTag(label: r.statusText),
              ],
            ),
            if ((r.partnerName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space1),
                child: Text(r.partnerName!, style: textTheme.bodyMedium),
              ),
            if (r.topicText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  r.topicText,
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
            if (r.termsText != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  r.termsText!,
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
                  '对方已拒绝，可再邀其他商家。',
                  style: textTheme.bodySmall?.copyWith(
                    color: CyPalette.of(context).textTertiary,
                  ),
                ),
              ),
            if (r.status == 0 && !r.decisionReady)
              Padding(
                padding: const EdgeInsets.only(top: CyTokens.space2),
                child: Text(
                  '邀请信息不完整,缺少邀请方、主题或合作条款,暂不能处理',
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
                      label: a.label,
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
                      label: '缴纳保证金',
                      loading: _busy,
                      onPressed: _busy ? null : _payDeposit,
                    ),
                  CyNativeButton(
                    label: '联系合作方',
                    role: CyNativeButtonRole.secondary,
                    loading: _busy,
                    onPressed: _busy ? null : _contact,
                  ),
                  // 供给申报是受邀方(接单一方)的动作:我收到的邀约 = 我是受邀方。
                  if (!widget.mine)
                    CyNativeButton(
                      label: '申报供给',
                      role: CyNativeButtonRole.secondary,
                      loading: _busy,
                      onPressed: _busy ? null : _openPerkPick,
                    ),
                  if (canReview)
                    CyNativeButton(
                      label: '评价',
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
                      label: '取消合作',
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
                    label: _busy ? '退款重试中…' : '重试保证金退款',
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
                    label: '再邀别人',
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
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<CoopPerkTemplate> _templates = const <CoopPerkTemplate>[];
  final Set<int> _checked = <int>{};

  @override
  void initState() {
    super.initState();
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
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final count = await ref
          .read(coopApiProvider)
          .attachPerks(
            inviteId: widget.inviteId,
            templateIds: _checked.toList(),
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '已申报 $count 项');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
        middle: const Text('申报本次供给'),
        leading: CupertinoButton(
          key: const Key('coop-perk-pick-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
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
              '勾选本次合作提供的礼品/券/折扣(来自你的常备权益)。到店玩家可领,成本按核销人头计入结算。',
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: CyTokens.space4),
                child: Text('还没有常备权益,去「常备权益」维护后再来'),
              )
            else
              ..._templates.map((CoopPerkTemplate t) {
                final selected = _checked.contains(t.id);
                final meta = t.unitCost != null
                    ? '成本 ¥${t.unitCost!.toStringAsFixed(2)}${t.quota != null ? ' · 配额 ${t.quota}' : ''}'
                    : (t.quota != null ? '配额 ${t.quota}' : '');
                return Semantics(
                  selected: selected,
                  button: true,
                  label: '${t.typeText} · ${t.name}',
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
                              Text('${t.typeText} · ${t.name}'),
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
                    : const Text('确认申报'),
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
  int _rating = 5;
  final _commentCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
      CyNativeNotice.show(context, '已评价');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
        middle: const Text('评价这次合作'),
        leading: CupertinoButton(
          key: const Key('coop-review-cancel'),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
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
                  label: '$star 星',
                  value: star == _rating ? '已选择' : '未选择',
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
              placeholder: '说说这次合作…（选填）',
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
                  : const Text('提交'),
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
    this.placeholder = '说明原因',
    this.confirmText,
  });

  final CoopHandleAction action;

  /// 输入框上方的一句说明。默认不显示 —— 各页的确认语不同
  /// (列表撤回:「对方还没处理,取消后这条邀约作废。」)
  final String? content;

  final String placeholder;

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
      title: Text('${widget.action.label}合作'),
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
              placeholder: widget.placeholder,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: CyTokens.space1),
            Text(widget.content ?? '对方会看到这段说明'),
          ],
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('再想想'),
        ),
        CupertinoDialogAction(
          key: const Key('coop-cancel-confirm'),
          isDestructiveAction: widget.action != CoopHandleAction.accept,
          // 空理由直接按不动 —— 提交了也是被后端拒,不如当场说清。
          onPressed: empty ? null : () => Navigator.of(context).pop(_c.text),
          child: Text(widget.confirmText ?? widget.action.label),
        ),
      ],
    );
  }
}
