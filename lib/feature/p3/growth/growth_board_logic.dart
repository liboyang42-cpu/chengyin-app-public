import 'package:dio/dio.dart';
import '../../../core/network/dio_client.dart';
import '../../../data/api/growth_api.dart';
import '../../../data/models/growth.dart';
import 'growth_overview.dart';

/// 排行榜失败分类(对齐小程序 growthcenter 两态的语义):
/// - [BoardFailureKind.error]:业务失败(code != 200 或网络断了),危险色;
/// - [BoardFailureKind.notice]:HTTP 层异常(后端未部署/502),中性说明色 ——
///   这种时候说「请求失败(404)」是误导,说「暂未开放」才诚实。
enum BoardFailureKind { error, notice }

class BoardFailure {
  const BoardFailure({required this.kind, required this.message});
  final BoardFailureKind kind;
  final String message;
}

/// 分类一次排行榜请求的失败。
/// - 业务错误(GrowthException,后端回了 msg)→ error;
/// - 401(游客/token 失效)→ notice,直说「登录状态已失效」——
///   后端对匿名请求一律 401(B1 模拟器报告 P1,curl 实证),
///   说「暂未开放」或放个按多少次都还是 401 的「重试」都是死路;
/// - 有响应的 HTTP 异常(非 200 状态)→ notice(暂未开放);
/// - 网络层断连(DioException 无响应)→ error;
/// - 其他未知异常 → error。
BoardFailure classifyBoardFailure(Object e) {
  if (e is GrowthException) {
    return BoardFailure(kind: BoardFailureKind.error, message: e.message);
  }
  if (e is DioException) {
    if (isUnauthorizedError(e)) {
      return const BoardFailure(
        kind: BoardFailureKind.notice,
        message: '登录状态已失效，请重新登录',
      );
    }
    if (e.response != null) {
      return const BoardFailure(
        kind: BoardFailureKind.notice,
        message: '排行榜暂未开放，请稍后查看',
      );
    }
    return const BoardFailure(
      kind: BoardFailureKind.error,
      message: '排行榜没有加载出来',
    );
  }
  return const BoardFailure(kind: BoardFailureKind.error, message: '排行榜没有加载出来');
}

/// 指标单位文案:point → 积分,exp → EXP。
String boardUnitText(String metric) => metric == 'exp' ? 'EXP' : '积分';

/// 「我的名次」视图(成长中心摘要与排行榜页共用)。
class MyRankView {
  const MyRankView({
    required this.rank,
    required this.name,
    required this.initial,
    required this.scoreText,
    required this.unit,
    required this.avatarUrl,
    required this.rankPercentage,
  });

  /// null = 没有可排名数据,界面显示「暂无排名」而不是「第 0 名」。
  final int? rank;
  final String name;
  final String initial;
  final String scoreText;
  final String unit;
  final String avatarUrl;
  final String? rankPercentage;
}

/// 由后端 LeaderboardItemVO(me)构建视图。nickname 空 → '我'。
MyRankView myRankView(LeaderboardItem me, String metric) {
  final name = me.nickname.isNotEmpty ? me.nickname : '我';
  return MyRankView(
    rank: me.rank,
    name: name,
    initial: nameInitial(name),
    scoreText: formatInteger(me.score) ?? '—',
    unit: boardUnitText(metric),
    avatarUrl: me.avatar,
    rankPercentage: me.rankPercentage,
  );
}

/// 排行榜单行视图(完整榜单用)。
class LeaderboardRowView {
  const LeaderboardRowView({
    required this.rank,
    required this.memberId,
    required this.name,
    required this.initial,
    required this.scoreText,
    required this.avatarUrl,
  });

  final int rank;
  final int memberId;
  final String name;
  final String initial;
  final String scoreText;
  final String avatarUrl;
}

LeaderboardRowView leaderboardRow(LeaderboardItem item) {
  final name = item.nickname.isNotEmpty ? item.nickname : '探索者';
  return LeaderboardRowView(
    rank: item.rank ?? 0,
    memberId: item.memberId,
    name: name,
    initial: nameInitial(name),
    scoreText: formatInteger(item.score) ?? '—',
    avatarUrl: item.avatar,
  );
}
