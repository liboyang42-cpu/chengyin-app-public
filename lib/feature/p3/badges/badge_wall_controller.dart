import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/badge_wall.dart';
import 'badge_wall_logic.dart';

/// 勋章墙失败分类:wall-v2 挂了(主体缺失)= 硬错误;
/// medal/wall 挂了 = 部分失败(身份卡还在,但不能把缺失的纪念章静默当成完整结果)。
enum BadgeWallFailure { loadFail, partialFail }

class BadgeWallPageData {
  const BadgeWallPageData({
    required this.badges,
    required this.legend,
    required this.unlockedCount,
    required this.lockedCount,
    required this.failure,
    required this.failureDetail,
  });

  final List<WallBadgeView> badges;
  final List<WallLegendEntry> legend;
  final int unlockedCount;
  final int lockedCount;

  /// null = 全部接通。
  final BadgeWallFailure? failure;

  /// 失败详情(后端原文 msg,展示用)。
  final String failureDetail;
}

/// 勋章墙:双端点并取。wall-v2 = 身份卡主体;medal/wall = 纪念章 + 成就徽章。
final badgeWallProvider =
    FutureProvider.autoDispose<BadgeWallPageData>((ref) async {
  final api = ref.watch(badgeWallApiProvider);

  BadgeWallV2? wallV2;
  MedalWall? wall;
  String? v2Error;
  String? wallError;
  try {
    wallV2 = await api.wallV2();
  } catch (e) {
    v2Error = e.toString().replaceFirst('Exception: ', '');
  }
  try {
    wall = await api.medalWall();
  } catch (e) {
    wallError = e.toString().replaceFirst('Exception: ', '');
  }

  // 身份卡是本页主体,且目录已不在前端 —— wall-v2 挂了就报错,
  // 不静默显示一面没有身份卡的墙(那会让用户以为自己一张身份卡都没有)。
  if (wallV2 == null) {
    return BadgeWallPageData(
      badges: const <WallBadgeView>[],
      legend: const <WallLegendEntry>[],
      unlockedCount: 0,
      lockedCount: 0,
      failure: BadgeWallFailure.loadFail,
      failureDetail: v2Error ?? '网络暂时失败',
    );
  }

  final badges = <WallBadgeView>[
    for (final item in wallV2.identity) identityBadgeView(item),
    if (wall != null)
      for (final medal in wall.medals) medalBadgeView(medal),
  ];
  final unlocked = badges.where((b) => !b.locked).length;
  return BadgeWallPageData(
    badges: badges,
    legend: buildLegend(badges),
    unlockedCount: unlocked,
    lockedCount: badges.length - unlocked,
    failure: wall == null ? BadgeWallFailure.partialFail : null,
    failureDetail: wallError ?? '',
  );
});
