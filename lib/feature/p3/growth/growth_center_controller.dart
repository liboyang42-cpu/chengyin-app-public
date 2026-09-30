import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/growth.dart';
import 'growth_board_logic.dart';
import 'growth_overview.dart';

/// 成长中心页面数据:概览 + 徽章列表(对齐小程序
/// subpackageP3/pages/growthcenter/index)。
///
/// 三个数据源任一个失败都不把整页打红:对应统计显示 '—'、徽章区显示
/// 说明条 —— 失败不伪装成零(与小程序同语义)。
class GrowthCenterPageData {
  const GrowthCenterPageData({
    required this.overview,
    required this.badges,
    required this.badgeLoadError,
  });

  final GrowthOverview overview;
  final List<CenterBadgeView> badges;

  /// 成长中心接口没接通 → 徽章区显示「暂不可用」,而不是「0 枚徽章」。
  final bool badgeLoadError;
}

class CenterBadgeView {
  const CenterBadgeView({
    required this.code,
    required this.name,
    required this.initial,
    required this.iconUrl,
    required this.unlockText,
  });

  final String code;
  final String name;
  final String initial;
  final String iconUrl;

  /// 获得时刻文案;拿不到为 null → 展开时整块不展示,不填占位符。
  final String? unlockText;
}

/// 我的排名摘要(容错:失败 → failure 而非整页 error)。
class MyRankBoard {
  const MyRankBoard({this.view, this.failure});
  final MyRankView? view;
  final BoardFailure? failure;
}

/// 概览:三源并取,单源失败降级不整页红。
final growthCenterPageProvider =
    FutureProvider.autoDispose<GrowthCenterPageData>((ref) async {
  final api = ref.watch(growthApiProvider);

  GrowthCenter? center;
  PlayGrowth? play;
  List<CompletedActivity>? completed;
  try {
    center = await api.center();
  } catch (_) {
    center = null;
  }
  try {
    play = await api.playGrowth();
  } catch (_) {
    play = null;
  }
  try {
    completed = await api.myCompleted();
  } catch (_) {
    completed = null;
  }

  final overview = buildGrowthOverview(
    center: center,
    play: play,
    completed: completed,
  );
  final badges = (center?.badges ?? const <MedalBadge>[])
      .map(
        (MedalBadge b) => CenterBadgeView(
          code: b.badgeCode ?? badgeDisplayName(b),
          name: badgeDisplayName(b),
          initial: nameInitial(badgeDisplayName(b)),
          iconUrl: b.iconUrl,
          unlockText: unlockMomentText(b.obtainTime),
        ),
      )
      .toList();

  return GrowthCenterPageData(
    overview: overview,
    badges: badges,
    badgeLoadError: center == null,
  );
});

/// 我的排名摘要:POST /api/growth/leaderboard,limit=1 只取 me。
final growthMyRankProvider = FutureProvider.autoDispose<MyRankBoard>((ref) async {
  final api = ref.watch(growthApiProvider);
  try {
    final board = await api.leaderboard(metric: 'point', period: 'total', limit: 1);
    return MyRankBoard(view: myRankView(board.me, board.metric));
  } catch (e) {
    return MyRankBoard(failure: classifyBoardFailure(e));
  }
});
