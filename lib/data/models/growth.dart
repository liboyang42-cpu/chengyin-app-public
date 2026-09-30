import 'package:chengyin_app/core/util/json_parse.dart';

/// 成长中心(对齐后端 MemberGrowthCenterVO / `/api/growth/center`)。
class GrowthCenter {
  GrowthCenter({
    required this.levelNo,
    required this.expValue,
    required this.points,
    required this.badges,
    required this.missions,
  });

  final int levelNo;
  final int expValue;
  final int points;
  final List<MedalBadge> badges;
  final List<GrowthMission> missions;

  factory GrowthCenter.fromJson(Map<String, dynamic> json) {
    final growth = json['growth'] as Map<String, dynamic>?;
    final rawBadges = (json['badges'] as List<dynamic>?) ?? <dynamic>[];
    final rawMissions = (json['missions'] as List<dynamic>?) ?? <dynamic>[];
    return GrowthCenter(
      levelNo: asInt(growth?['levelNo'], defaultValue: 1),
      expValue: asInt(growth?['expValue']),
      points: asInt(json['points']),
      badges: rawBadges
          .map((dynamic e) => MedalBadge.fromJson(e as Map<String, dynamic>))
          .toList(),
      missions: rawMissions
          .map((dynamic e) => GrowthMission.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 徽章(对齐 PlayerBadge:badgeCode / badgeName / iconUrl / obtainTime)。
class MedalBadge {
  MedalBadge({
    required this.badgeName,
    required this.iconUrl,
    this.badgeCode,
    this.obtainTime,
  });

  final String badgeName;
  final String iconUrl;
  final String? badgeCode;

  /// 获得时刻。后端 Date 序列化为不带时区的中国时间串("yyyy-MM-dd HH:mm:ss")。
  /// 拿不到(字段缺失)保持 null —— 「没拿到」与「没解锁过」是两回事,别转成空串。
  final String? obtainTime;

  factory MedalBadge.fromJson(Map<String, dynamic> json) => MedalBadge(
    badgeName: (json['badgeName'] ?? '') as String,
    iconUrl: (json['iconUrl'] ?? '') as String,
    badgeCode: json['badgeCode'] as String?,
    obtainTime: json['obtainTime'] as String?,
  );
}

/// 成长任务(对齐 GrowthMission)。
class GrowthMission {
  GrowthMission({
    required this.missionName,
    required this.missionDesc,
    required this.expReward,
  });

  final String missionName;
  final String missionDesc;
  final int expReward;

  factory GrowthMission.fromJson(Map<String, dynamic> json) => GrowthMission(
    missionName: (json['missionName'] ?? '') as String,
    missionDesc: (json['missionDesc'] ?? '') as String,
    expReward: asInt(json['expReward']),
  );
}

/// 成长排行榜(对齐 MemberLeaderboardVO / `/api/growth/leaderboard`)。
class GrowthLeaderboard {
  GrowthLeaderboard({
    required this.metric,
    required this.period,
    required this.list,
    required this.me,
  });

  /// point(积分) / exp(成长)。
  final String metric;
  /// total(总榜) / week(周榜)。
  final String period;
  final List<LeaderboardItem> list;

  /// 我的名次。rank 为 null = 没有可排名数据 —— 不是第 0 名。
  final LeaderboardItem me;

  factory GrowthLeaderboard.fromJson(Map<String, dynamic> json) {
    final rawList = (json['list'] as List<dynamic>?) ?? <dynamic>[];
    return GrowthLeaderboard(
      metric: (json['metric'] ?? 'point') as String,
      period: (json['period'] ?? 'total') as String,
      list: rawList
          .whereType<Map<String, dynamic>>()
          .map(LeaderboardItem.fromJson)
          .toList(),
      me: LeaderboardItem.fromJson(
        (json['me'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
    );
  }
}

/// 排行榜单行(对齐 LeaderboardItemVO)。列表行与「我的名次」共用。
class LeaderboardItem {
  LeaderboardItem({
    required this.rank,
    required this.memberId,
    required this.nickname,
    required this.avatar,
    required this.score,
    required this.rankPercentage,
  });

  /// null = 没有可排名数据(与 rank=0 含义不同,别合并)。
  final int? rank;
  final int memberId;
  final String nickname;
  final String avatar;
  final int score;

  /// 仅「我的名次」有值(如 TOP20%),列表项为 null。
  final String? rankPercentage;

  factory LeaderboardItem.fromJson(Map<String, dynamic> json) => LeaderboardItem(
    rank: json['rank'] == null ? null : asInt(json['rank']),
    memberId: asInt(json['memberId']),
    nickname: (json['nickname'] ?? '') as String,
    avatar: (json['avatar'] ?? '') as String,
    score: asInt(json['score']),
    rankPercentage: json['rankPercentage'] as String?,
  );
}

/// 我的成长进度(对齐 `/api/play/growth` 返回:level/totalCheckins/
/// totalMileage/streakDays)。
class PlayGrowth {
  const PlayGrowth({
    required this.level,
    required this.totalCheckins,
    required this.totalMileage,
    required this.streakDays,
  });

  final int level;
  final int totalCheckins;
  final double totalMileage;
  final int streakDays;

  factory PlayGrowth.fromJson(Map<String, dynamic> json) => PlayGrowth(
    level: asInt(json['level']),
    totalCheckins: asInt(json['totalCheckins']),
    totalMileage: asDouble(json['totalMileage']) ?? 0,
    streakDays: asInt(json['streakDays']),
  );
}

/// 我已通关的活动(对齐 `/api/play/my-completed` 单行)。
class CompletedActivity {
  const CompletedActivity({
    required this.activityId,
    required this.topicId,
    required this.name,
    required this.cover,
    required this.total,
    required this.doneCount,
  });

  final int activityId;
  final int topicId;
  final String name;
  final String cover;
  final int total;
  final int doneCount;

  factory CompletedActivity.fromJson(Map<String, dynamic> json) =>
      CompletedActivity(
        activityId: asInt(json['activityId']),
        topicId: asInt(json['topicId']),
        name: (json['name'] ?? '') as String,
        cover: (json['cover'] ?? '') as String,
        total: asInt(json['total']),
        doneCount: asInt(json['doneCount']),
      );
}
