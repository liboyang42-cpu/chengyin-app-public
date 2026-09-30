import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/growth.dart';
import 'growth_board_logic.dart';

/// 完整排行榜页面数据(对齐小程序
/// subpackageP3/pages/growthcenter/leaderboard)。
class LeaderboardPageData {
  const LeaderboardPageData({
    required this.board,
    required this.top3,
    required this.rest,
    required this.me,
    required this.unit,
  });

  final GrowthLeaderboard board;
  final List<LeaderboardRowView?> top3;
  final List<LeaderboardRowView> rest;
  final MyRankView? me;
  final String unit;
}

/// 构建榜单视图:前三名 + 其余名次 + 我的名次。
/// me.rank 为 null → me 不展示(没有可排名数据),不是第 0 名。
LeaderboardPageData buildLeaderboardData(GrowthLeaderboard board) {
  final rows = board.list.map(leaderboardRow).toList();
  final top3 = <LeaderboardRowView?>[
    rows.isNotEmpty ? rows[0] : null,
    rows.length > 1 ? rows[1] : null,
    rows.length > 2 ? rows[2] : null,
  ];
  final me =
      board.me.rank == null ? null : myRankView(board.me, board.metric);
  return LeaderboardPageData(
    board: board,
    top3: top3,
    rest: rows.length > 3 ? rows.sublist(3) : <LeaderboardRowView>[],
    me: me,
    unit: boardUnitText(board.metric),
  );
}

/// 榜单查询参数。
class LeaderboardQuery {
  const LeaderboardQuery({required this.metric, required this.period});

  final String metric;
  final String period;

  LeaderboardQuery copyWith({String? metric, String? period}) =>
      LeaderboardQuery(
        metric: metric ?? this.metric,
        period: period ?? this.period,
      );

  @override
  bool operator ==(Object other) =>
      other is LeaderboardQuery &&
      other.metric == metric &&
      other.period == period;

  @override
  int get hashCode => Object.hash(metric, period);
}

/// 榜单拉取(带参数,参数变化自动重拉)。
final leaderboardProvider =
    FutureProvider.autoDispose
        .family<LeaderboardResult, LeaderboardQuery>((ref, query) async {
  final api = ref.watch(growthApiProvider);
  try {
    final board = await api.leaderboard(
      metric: query.metric,
      period: query.period,
      limit: 50,
    );
    return LeaderboardResult(data: buildLeaderboardData(board));
  } catch (e) {
    return LeaderboardResult(failure: classifyBoardFailure(e));
  }
});

class LeaderboardResult {
  const LeaderboardResult({this.data, this.failure});
  final LeaderboardPageData? data;
  final BoardFailure? failure;
}
