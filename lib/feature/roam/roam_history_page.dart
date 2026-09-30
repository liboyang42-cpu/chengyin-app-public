import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/roam_session.dart';

final roamHistoryProvider = FutureProvider.autoDispose<List<RoamSession>>((
  ref,
) {
  return ref.watch(roamSessionStoreProvider).readAll();
});

/// 漫游历史(对齐小程序 `subpackageRoam/history` + scene-roam-history):
/// 顶部汇总(行程/公里/点亮)+ 旅程卡列表,点卡进单次回看。
///
/// ★ 读失败与「没有记录」分家:读失败给重试(记录还在),
///   空列表给空态(真没走过)。两者不能合并。
class RoamHistoryPage extends ConsumerWidget {
  const RoamHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(roamHistoryProvider);
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('漫游历史'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 集邮册入口。⚠️ 小程序把它挂在**漫游地图页**上(半屏 scene),
            //   App 的地图页正被另一处改着,这里先挂在漫游历史 ——
            //   页面本体是同一个,入口位置与小程序不同,后续可挪。
            Semantics(
              button: true,
              label: '集邮册',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => GoRouter.of(context).push('/roam/stamp-album'),
                child: const Icon(CupertinoIcons.book),
              ),
            ),
            Semantics(
              button: true,
              label: '实时漫游',
              child: CupertinoButton(
                key: const Key('roam-live-entry'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: () => GoRouter.of(context).push('/roam'),
                child: const Icon(CupertinoIcons.compass),
              ),
            ),
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: async.when(
            loading: () => const Center(child: CupertinoActivityIndicator()),
            error: (Object e, _) => StatusView(
              icon: CupertinoIcons.exclamationmark_triangle,
              message: '漫游记录读不出来',
              // iOS 没有「存储权限」可检查 —— 下一步必须是指引得起的那件事。
              sub: '记录还在本机，点下方重试再读一次',
              onRetry: () => ref.invalidate(roamHistoryProvider),
            ),
            data: (List<RoamSession> sessions) {
              if (sessions.isEmpty) {
                return const StatusView(
                  icon: CupertinoIcons.book,
                  message: '还没有漫游记录',
                  sub: '去地图走一次漫游，这里会出现你的旅程卡',
                );
              }
              final entries = sessions.map(RoamHistoryEntry.new).toList()
                ..sort(
                  (RoamHistoryEntry a, RoamHistoryEntry b) =>
                      b.timestamp.compareTo(a.timestamp),
                );
              final summary = RoamHistorySummary.fromSessions(sessions);
              return RefreshIndicator.adaptive(
                onRefresh: () async => ref.invalidate(roamHistoryProvider),
                child: ListView(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  children: <Widget>[
                    _SummaryCard(summary: summary),
                    const SizedBox(height: CyTokens.space3),
                    ...entries.map(
                      (RoamHistoryEntry entry) => Padding(
                        padding: const EdgeInsets.only(bottom: CyTokens.space3),
                        child: _HistoryCard(
                          entry: entry,
                          onTap: () => context.push(
                            Uri(
                              path: '/roam/session',
                              queryParameters: <String, String>{
                                'ts': '${entry.timestamp}',
                              },
                            ).toString(),
                          ),
                        ),
                      ),
                    ),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final RoamHistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border.all(color: CyTokens.borderSubtle),
        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          _kv(context, '漫游', '${summary.trips}'),
          _kv(context, '里程', '${summary.kmText} km'),
          _kv(context, '点亮', '${summary.shops}'),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: CyTokens.typeSectionTitle,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: CyTokens.typeCaption,
              color: CyTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.onTap});

  final RoamHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final CyPalette palette = CyPalette.of(context);
    final RoamSession s = entry.session;
    return CupertinoButton(
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(CyTokens.space3),
        decoration: BoxDecoration(
          color: palette.bgSurface,
          border: Border.all(color: CyTokens.borderSubtle),
          borderRadius: BorderRadius.circular(CyTokens.radiusMd),
        ),
        child: Row(
          children: <Widget>[
            _Cover(cover: entry.cover),
            const SizedBox(width: CyTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.title,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: CyTokens.typeCardTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    entry.dateFull,
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: CyTokens.typeCaption,
                      color: CyTokens.textSecondary,
                    ),
                  ),
                  // ★ 三段(里程/用时/点亮)**只显示有值的** ——
                  //   原来缺席时兜成「0.0 km · 00:00 · 点亮 0 家」,
                  //   那是假的:「走了 0 公里」和「没记到里程」是两件事。
                  //   全缺时整行不显示。
                  if (s.statsLine != null) ...<Widget>[
                    const SizedBox(height: CyTokens.space1),
                    Text(
                      s.statsLine!,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: CyTokens.typeCaption,
                        color: CyTokens.textSecondary,
                      ),
                    ),
                  ],
                  if (entry.medals.isNotEmpty) ...<Widget>[
                    const SizedBox(height: CyTokens.space1_5),
                    Wrap(
                      spacing: CyTokens.space1_5,
                      children: entry.medals
                          .map(
                            (String m) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CyTokens.space2,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: CyTokens.bgSurfaceSubtle,
                                borderRadius: BorderRadius.circular(
                                  CyTokens.radiusSm,
                                ),
                              ),
                              child: Text(
                                m,
                                style: textTheme.bodySmall?.copyWith(
                                  fontSize: CyTokens.typeCaption,
                                  color: CyTokens.textPrimary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: CyTokens.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.cover});

  final String cover;

  @override
  Widget build(BuildContext context) {
    const double size = 72;
    return ClipRRect(
      borderRadius: BorderRadius.circular(CyTokens.radiusSm),
      child: SizedBox(
        width: size,
        height: size,
        child: cover.isEmpty
            ? Container(
                color: CyTokens.bgSurfaceSubtle,
                child: const Icon(
                  Icons.terrain,
                  size: 28,
                  color: CyTokens.textTertiary,
                ),
              )
            : Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: CyTokens.bgSurfaceSubtle,
                  child: const Icon(
                    Icons.terrain,
                    size: 28,
                    color: CyTokens.textTertiary,
                  ),
                ),
              ),
      ),
    );
  }
}
