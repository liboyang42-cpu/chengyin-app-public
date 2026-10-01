import 'coop_strings.dart';
import '../../l10n/strings.dart';
import '../auth/auth_controller.dart';
import '../../core/network/request_session_scope.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_candidate.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'coop_guard.dart';

final coopCandidatesProvider = FutureProvider.autoDispose
    .family<CoopCandidates, int>((ref, int topicId) {
      return ref.watch(coopApiProvider).candidates(topicId);
    });

/// 候选池(主题发布者视角)。对齐小程序 `pages/coop/candidates`。
class CoopCandidatesPage extends ConsumerWidget {
  const CoopCandidatesPage({super.key, required this.topicId});

  final int topicId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title = stringsOf(context).coopCandidates;
    final String needLogin = stringsOf(context).coopLoginCandidates;
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(coopCandidatesProvider(topicId));
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) {
              if (isCoopUnauthorized(e)) {
                return coopLoginStatus(
                  context,
                  ref,
                  message: needLogin,
                  refetch: () =>
                      ref.invalidate(coopCandidatesProvider(topicId)),
                );
              }
              final msg = coopErrorSub(e, context: context);
              // ★ 「仅主题发布者可查看候选池」是权限态 —— 重试多少次都不会变,不给重试。
              if (msg.contains('仅主题发布者')) {
                return StatusView(
                  message: stringsOf(context).coopOnlyPublisher,
                  sub: stringsOf(context).coopNotPublisher,
                  large: true,
                );
              }
              return StatusView(
                message: stringsOf(context).coopCandidatesLoadFailed,
                sub: msg,
                large: true,
                onRetry: () => ref.invalidate(coopCandidatesProvider(topicId)),
              );
            },
            data: (CoopCandidates c) {
              if (c.isEmpty) {
                return StatusView(
                  message: stringsOf(context).coopNoCandidates,
                  sub: stringsOf(context).coopNoCandidatesHint,
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async =>
                    ref.invalidate(coopCandidatesProvider(topicId)),
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  children: <Widget>[
                    if (c.clubApplies.isNotEmpty) ...<Widget>[
                      CySectionTitle(stringsOf(context).coopClubApplications),
                      const SizedBox(height: CyTokens.space2),
                      ...c.clubApplies.map(
                        (ClubApply a) => _ApplyTile(apply: a, topicId: topicId),
                      ),
                      const SizedBox(height: CyTokens.space4),
                    ],
                    if (c.registrations.isNotEmpty) ...<Widget>[
                      CySectionTitle(stringsOf(context).coopRegisteredCandidates),
                      const SizedBox(height: CyTokens.space2),
                      ...c.registrations.map(
                        (CandidateRegistration r) =>
                            _RegistrationTile(reg: r, topicId: topicId),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ★ 「确认候选」= 占住这个竞争位,不是成交(§3.6)——
///   后端不生成合作单,只把这个报名标记为选中;真正成交要靠发布者
///   接着去发一份带条款的合作邀约(接受后才生成合作单)。所以按下去之后
///   不是"完成",而是"进入下一步",提示语必须说清楚,不能只报「已确认」。
class _RegistrationTile extends ConsumerStatefulWidget {
  const _RegistrationTile({required this.reg, required this.topicId});
  final CandidateRegistration reg;
  final int topicId;

  @override
  ConsumerState<_RegistrationTile> createState() => _RegistrationTileState();
}

class _RegistrationTileState extends ConsumerState<_RegistrationTile> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  bool _busy = false;
  bool _confirmed = false;

  Future<void> _confirm() => RequestSessionScope.run(
    _requestScope,
    () => _confirmScoped(),
  );

  Future<void> _confirmScoped() async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopConfirmCandidateName(widget.reg.name),
      content: stringsOf(context).coopCandidateConfirmHint,
      confirmText: stringsOf(context).coopConfirmCandidate,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(coopApiProvider).confirmCandidate(widget.reg.id);
      ref.invalidate(coopCandidatesProvider(widget.topicId));
      if (!mounted) return;
      setState(() => _confirmed = true);
      await cyConfirm(
        context,
        title: stringsOf(context).coopCandidateSelected,
        content: stringsOf(context).coopCandidateSendTerms,
        confirmText: stringsOf(context).coopGotIt,
        showCancel: false,
      );
      if (!mounted) return;
      context.push('/coop/invite/${widget.topicId}');
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

  @override
  Widget build(BuildContext context) {
    return CyCell(
      title: widget.reg.name,
      trailing: _confirmed
          ? Text(stringsOf(context).coopConfirmed)
          : CyNativeButton(
              width: 120,
              label: stringsOf(context).coopConfirmCandidate,
              role: CyNativeButtonRole.secondary,
              loading: _busy,
              onPressed: _busy ? null : _confirm,
            ),
    );
  }
}

class _ApplyTile extends ConsumerStatefulWidget {
  const _ApplyTile({required this.apply, required this.topicId});
  final ClubApply apply;
  final int topicId;

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

  Future<void> _decline() => RequestSessionScope.run(
    _requestScope,
    () => _declineScoped(),
  );

  Future<void> _declineScoped() async {
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).coopDeclineApplicationName(widget.apply.clubName),
      content: stringsOf(context).coopDeclineReapply,
      confirmText: stringsOf(context).coopDecline,
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(coopApiProvider).declineApply(widget.apply.id);
      ref.invalidate(coopCandidatesProvider(widget.topicId));
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).coopDeclined);
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

  @override
  Widget build(BuildContext context) {
    final a = widget.apply;
    final textTheme = Theme.of(context).textTheme;
    return Container(
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
              CyAvatar(url: a.clubLogo, fallback: a.clubName.characters.first),
              const SizedBox(width: CyTokens.space2),
              Expanded(child: Text(a.clubName, style: textTheme.titleSmall)),
              CyTag(label: coopCandidateStatus(context, a.status)),
            ],
          ),
          // 留言为空时整行不渲染,不留一个空的引号框。
          if ((a.message ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space2),
              child: Text(
                a.message!.trim(),
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space2),
          // ★ 只有待处理才给按钮 —— 已转邀约/已婉拒/已撤回点下去后端必拒。
          if (a.actionable)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                label: stringsOf(context).coopDecline,
                role: CyNativeButtonRole.destructive,
                loading: _busy,
                onPressed: _busy ? null : _decline,
              ),
            )
          else
            Text(
              a.status == 3 ? stringsOf(context).coopContinueInvite : stringsOf(context).coopApplicationHandled,
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}
