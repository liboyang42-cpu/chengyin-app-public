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
    const String title = '合作池';
    const String needLogin = '登录后查看合作池';
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
      navigationBar: const CupertinoNavigationBar(middle: Text(title)),
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
                message: '合作池没能加载出来',
                sub: coopErrorSub(e),
                large: true,
                onRetry: () => ref.invalidate(coopPoolProvider),
              ),
        data: (CoopPool pool) {
          // ★ 没有俱乐部 ≠ 没有可承接的主题。只显示空列表会让人以为
          //   「暂时没有可承接的主题」,其实是他还没有俱乐部。
          if (!pool.hasClub) {
            return StatusView(
              message: '先创建一个俱乐部',
              sub: '承接主题需要以俱乐部身份申请',
              large: true,
              onRetry: () => context.push('/clubs'),
              retryLabel: '去俱乐部',
            );
          }
          if (pool.rows.isEmpty) {
            return const StatusView(
              message: '暂时没有可承接的主题',
              sub: '商家开放新的承接机会时会出现在这里',
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
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
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
        e.toString().replaceFirst('Exception: ', ''),
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
              Expanded(child: Text(it.name, style: textTheme.titleMedium)),
              CyTag(label: it.stateText),
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
                '发起方 ${it.merchantNick}',
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
                label: '申请承接',
                loading: _busy,
                onPressed: _busy
                    ? null
                    : () => _run(() => api.apply(it.topicId), '申请已提交'),
              ),
            )
          // ⚠️ 撤回键是 **topicId**(后端按主题撤,不按申请 id):
          //    见 CoopApi.withdraw 的注释 —— 发错键不报错,只是永远撤不掉。
          else if (it.canWithdraw)
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                label: '撤回申请',
                role: CyNativeButtonRole.secondary,
                loading: _busy,
                onPressed: _busy
                    ? null
                    : () => _run(() => api.withdraw(it.topicId), '已撤回'),
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

  static String _waitingHint(String state) {
    switch (state) {
      case 'invited':
        return '去「邀约」里确认条款即可开始合作';
      case 'converted':
        return '已通过,邀约已生成,去「邀约」里确认';
      case 'cooped':
        return '合作进行中';
      case 'taken':
        return '这个主题已被其他俱乐部承接';
      default:
        return '等待对方处理';
    }
  }
}
