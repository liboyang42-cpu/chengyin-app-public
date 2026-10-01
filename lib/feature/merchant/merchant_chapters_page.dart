import '../../l10n/strings.dart';
import 'merchant_directory_strings.dart';
import '../../core/theme/cy_palette.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../core/widgets/cy_confirm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/chapter_application.dart';
import 'merchant_error_view.dart';

final myChapterApplicationsProvider =
    FutureProvider.autoDispose<List<ChapterApplication>>((ref) {
      return ref.watch(merchantApiProvider).myChapterApplications();
    });

/// 我的章节承接。对齐小程序 `pages/topic/merchantinfo` 的申请部分。
class MerchantChaptersPage extends ConsumerWidget {
  const MerchantChaptersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myChapterApplicationsProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(middle: Text(stringsOf(context).merchantDirectoryMyHosting)),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => merchantErrorView(
              context,
              e,
              onRetry: () => ref.invalidate(myChapterApplicationsProvider),
            ),
            data: (List<ChapterApplication> rows) {
              if (rows.isEmpty) {
                return StatusView(
                  message: stringsOf(context).merchantDirectoryNoApplications,
                  sub: stringsOf(context).merchantDirectoryNoApplicationsHint,
                  large: true,
                );
              }
              return RefreshIndicator.adaptive(
                onRefresh: () async =>
                    ref.invalidate(myChapterApplicationsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.all(CyTokens.pageX),
                  itemCount: rows.length,
                  itemBuilder: (_, int i) => _ApplicationTile(app: rows[i]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ApplicationTile extends ConsumerStatefulWidget {
  const _ApplicationTile({required this.app});
  final ChapterApplication app;

  @override
  ConsumerState<_ApplicationTile> createState() => _ApplicationTileState();
}

class _ApplicationTileState extends ConsumerState<_ApplicationTile> {
  bool _busy = false;

  Future<void> _withdraw() async {
    final a = widget.app;
    final bool ok = await cyConfirm(
      context,
      title: stringsOf(context).merchantDirectoryWithdrawTitle(merchantDirectoryChapterTitle(context, a)),
      content: stringsOf(context).merchantDirectoryWithdrawHint,
      confirmText: stringsOf(context).merchantDirectoryWithdraw,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(merchantApiProvider).withdrawChapterApplication(a.id);
      ref.invalidate(myChapterApplicationsProvider);
      if (!mounted) return;
      CyNativeNotice.show(context, stringsOf(context).merchantDirectoryWithdrawn);
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
    final a = widget.app;
    final textTheme = Theme.of(context).textTheme;

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
          // ★ 有 topicId 才做成可点的 —— 没有它就没有可去的地方,
          //   摆一个点了没反应的标题比不可点更糟。
          if (a.topicId != null && a.topicId! > 0)
            Semantics(
              key: Key('chapter-app-open-${a.id}'),
              button: true,
              label: merchantDirectoryChapterTitle(context, a),
              onTap: () => context.push('/merchant/recruit/${a.topicId}'),
              excludeSemantics: true,
              child: CupertinoButton(
                onPressed: () => context.push('/merchant/recruit/${a.topicId}'),
                minimumSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          merchantDirectoryChapterTitle(context, a),
                          style: textTheme.titleMedium,
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_forward,
                        size: 16,
                        color: CyPalette.of(context).textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Text(merchantDirectoryChapterTitle(context, a), style: textTheme.titleMedium),
          const SizedBox(height: CyTokens.space1),
          // ★ 被拒时 statusText 自带原因;主办方邀请与自己申请通过分开说。
          Text(
            merchantDirectoryChapterStatus(context, a),
            style: textTheme.bodySmall?.copyWith(
              color: a.isRejected
                  ? CyPalette.of(context).statusWarning
                  : CyPalette.of(context).textSecondary,
            ),
          ),
          // 邀请来的点位免审,说清楚 —— 商家不用再等一轮。
          if (a.isApproved && !a.nodeNeedsAudit)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                stringsOf(context).merchantDirectoryNoFurtherReview,
                style: textTheme.bodySmall?.copyWith(
                  color: CyPalette.of(context).textTertiary,
                ),
              ),
            ),
          // ★ 只有能撤的才摆按钮 —— 邀请来的、已定的都不摆。
          if (a.canWithdraw) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            SizedBox(
              width: double.infinity,
              child: CyNativeButton(
                onPressed: _busy ? null : _withdraw,
                label: stringsOf(context).merchantDirectoryWithdrawApplication,
                role: CyNativeButtonRole.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
