import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/club.dart';
import 'club_controller.dart';

/// 俱乐部贡献榜。四个维度:综合 / 里程 / 配速 / 用时。
///
/// ★ 配速与用时**可能为 null**(零里程或零用时),显示成「—」。
///   写成 0 的话,那个没有有效计时的人会以「0.0 min/km」排在第一 ——
///   后端专门用 nullsLast 把他们沉底,前端不能在渲染时又把 null 变回 0。
class ClubLeaderboardPage extends ConsumerStatefulWidget {
  const ClubLeaderboardPage({super.key, required this.clubId});
  final int clubId;

  @override
  ConsumerState<ClubLeaderboardPage> createState() =>
      _ClubLeaderboardPageState();
}

class _ClubLeaderboardPageState extends ConsumerState<ClubLeaderboardPage> {
  ClubRankSort _sort = ClubRankSort.composite;

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(
      clubLeaderboardProvider((clubId: widget.clubId, sort: _sort)),
    );
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('贡献榜')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CyTabs(
                tabs: ClubRankSort.values
                    .map((ClubRankSort s) => CyTab(key: s.wire, label: s.label))
                    .toList(),
                active: _sort.wire,
                variant: CyTabsVariant.segmented,
                onChanged: (String key) => setState(() {
                  _sort = ClubRankSort.values.firstWhere((s) => s.wire == key);
                }),
              ),
              Expanded(
                child: rows.when(
                  loading: () => const CySkeleton(),
                  error: (Object e, StackTrace st) => StatusView(
                    message: '没能加载贡献榜',
                    sub: '检查网络后重试',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    onRetry: () => ref.invalidate(clubLeaderboardProvider),
                  ),
                  data: (List<ClubRankRow> list) {
                    if (list.isEmpty) {
                      return const StatusView(
                        message: '还没有人上榜',
                        sub: '完成一次团后就会出现在这里。',
                        icon: Icons.emoji_events_outlined,
                        large: true,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(CyTokens.space4),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: CyTokens.space2),
                      itemBuilder: (_, int i) =>
                          _RankTile(rank: i + 1, row: list[i], sort: _sort),
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

class _RankTile extends StatelessWidget {
  const _RankTile({required this.rank, required this.row, required this.sort});

  final int rank;
  final ClubRankRow row;
  final ClubRankSort sort;

  /// 当前维度下这一行显示的主数值。
  ///
  /// ★ 配速/用时的 null 显示「—」,**不是 0**。
  String get _value {
    switch (sort) {
      case ClubRankSort.mileage:
        return '${row.mileage} km';
      case ClubRankSort.pace:
        return row.pace == null ? '—' : '${row.pace} min/km';
      case ClubRankSort.duration:
        return row.completionDuration == null
            ? '—'
            : '${row.completionDuration} min';
      case ClubRankSort.composite:
        return '${row.score} 分';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: t.titleMedium?.copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: CyTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    (row.nickname?.isNotEmpty ?? false)
                        ? row.nickname!
                        : '成员 ${row.memberId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall,
                  ),
                  const SizedBox(height: CyTokens.space1),
                  Text(
                    '通关 ${row.clearCount} · 带团 ${row.hostedCount}',
                    style: t.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(_value, style: t.titleSmall),
          ],
        ),
      ),
    );
  }
}
