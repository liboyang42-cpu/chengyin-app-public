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
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/coop_pool.dart';
import '../../core/widgets/cy_native_notice.dart';
import 'coop_guard.dart';

final coopPoolProvider = FutureProvider.autoDispose<CoopPool>((ref) {
  return ref.watch(coopApiProvider).pool();
});

/// 合作池(俱乐部视角)。对齐小程序 `pages/coop/list` 的合作池那一档。
class CoopPoolPage extends ConsumerWidget {
  const CoopPoolPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title = stringsOf(context).coopPool;
    final String needLogin = stringsOf(context).coopLoginPool;
    final Widget? gate = coopLoginGate(
      context,
      ref,
      navTitle: title,
      message: needLogin,
    );
    if (gate != null) return gate;
    final async = ref.watch(coopPoolProvider);
    return CupertinoPageScaffold(
      // 显式给浅色底:根 CupertinoTheme 恒暗、Material `Theme` 换不动它,
      // 不传的话这里就是黑底配浅色盘的黑字(见 coop_guard.dart)。
      backgroundColor: CyPalette.of(context).bgPage,
      navigationBar: CupertinoNavigationBar(middle: Text(title)),
      child: async.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (Object e, _) => isCoopUnauthorized(e)
            ? coopLoginView(
                context,
                ref,
                navTitle: title,
                message: needLogin,
                refetch: () => ref.invalidate(coopPoolProvider),
              )
            : StatusView(
                message: stringsOf(context).coopPoolLoadFailed,
                sub: coopErrorSub(e, context: context),
                large: true,
                onRetry: () => ref.invalidate(coopPoolProvider),
              ),
        data: (CoopPool pool) {
          // ★ 没有俱乐部 ≠ 没有可承接的主题。只显示空列表会让人以为
          //   「暂时没有可承接的主题」,其实是他还没有俱乐部。
          if (!pool.hasClub) {
            return StatusView(
              message: stringsOf(context).coopCreateClub,
              sub: stringsOf(context).coopApplyAsClub,
              large: true,
              onRetry: () => context.push('/clubs'),
              retryLabel: stringsOf(context).coopGoToClubs,
            );
          }
          if (pool.rows.isEmpty) {
            return StatusView(
              message: stringsOf(context).coopNoThemes,
              sub: stringsOf(context).coopNoThemesHint,
              large: true,
            );
          }
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref.invalidate(coopPoolProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(CyTokens.pageX),
              itemCount: pool.rows.length,
              itemBuilder: (_, int i) => _PoolTile(item: pool.rows[i]),
            ),
          );
        },
      ),
    );
  }
}

class _PoolTile extends ConsumerStatefulWidget {
  const _PoolTile({required this.item});
  final CoopPoolItem item;

  @override
  ConsumerState<_PoolTile> createState() => _PoolTileState();
}

class _PoolTileState extends ConsumerState<_PoolTile> {
  @override
  void initState() {
    super.initState();
    _requestScope = ref.read(authControllerProvider.notifier).requestScope(
      ref.read(authControllerProvider).user?.id ?? 0,
    );
  }

  late final RequestSessionScope _requestScope;

  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) => RequestSessionScope.run(
    _requestScope,
    () => _runScoped(action, done),
  );

  Future<void> _runScoped(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(coopPoolProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, done);
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
    final it = widget.item;
    final textTheme = Theme.of(context).textTheme;
    final api = ref.read(coopApiProvider);

    return Container(
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
              Expanded(child: Text(coopPoolName(context, it), style: textTheme.titleMedium)),
              CyTag(label: coopPoolStatus(context, it.state)),
            ],
          ),
          if ((it.subtitle ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: CyTokens.space1),
              child: Text(
                it.subtitle!,
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textSecondary,
                ),
              ),
            ),
          if ((it.merchantNick ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                stringsOf(context).coopInitiatorName(it.merchantNick!),
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textTertiary,
                ),
              ),
            ),
          const SizedBox(height: CyTokens.space3),
          // ★ 只有 open / declined / withdrawn 三态给「申请承接」。
          //   converted(已通过)、invited(该去接受邀约)都不给 ——
          //   给了会诱导用户重复申请,而后端会拒。
          if (it.canApply)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                label: stringsOf(context).coopApply,
                loading: _busy,
                onPressed: _busy
                    ? null
                    : () => _run(() => api.apply(it.topicId), stringsOf(context).coopApplied),
              ),
            )
          // ⚠️ 撤回键是 **topicId**(后端按主题撤,不按申请 id):
          //    见 CoopApi.withdraw 的注释 —— 发错键不报错,只是永远撤不掉。
          else if (it.canWithdraw)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                label: stringsOf(context).coopWithdrawApplication,
                role: CyNativeButtonRole.secondary,
                loading: _busy,
                onPressed: _busy
                    ? null
                    : () => _run(() => api.withdraw(it.topicId), stringsOf(context).coopWithdrawn),
              ),
            )
          else
            // 其余态没有可做的动作 —— 说清现在该等什么,而不是摆一个灰按钮。
            Text(
              _waitingHint(it.state),
              style: textTheme.bodySmall?.copyWith(
                color: CyPalette.of(context).textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  String _waitingHint(String state) {
    switch (state) {
      case 'invited':
        return stringsOf(context).coopPoolConfirmTerms;
      case 'converted':
        return stringsOf(context).coopPoolApprovedInvite;
      case 'cooped':
        return stringsOf(context).coopInProgress;
      case 'taken':
        return stringsOf(context).coopAssignedElsewhere;
      default:
        return stringsOf(context).coopWaitingPartner;
    }
  }
}
