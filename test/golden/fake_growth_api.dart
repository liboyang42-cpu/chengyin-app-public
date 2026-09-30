// 成长域 golden 测试共用的假 GrowthApi。Riverpod override 注入,不打网络。

import 'package:chengyin_app/data/api/growth_api.dart';
import 'package:chengyin_app/data/models/growth.dart';

class FakeGrowthApi implements GrowthApi {
  FakeGrowthApi({
    this.centerData,
    this.boardOverride,
    this.boardError,
    this.centerError,
    this.playError,
    this.completedError,
  });

  final GrowthCenter? centerData;

  /// 直接给 leaderboard 返回体(走真实 GrowthLeaderboard.fromJson 解析)。
  final Map<String, dynamic>? boardOverride;
  final Object? boardError;
  final Object? centerError;
  final Object? playError;
  final Object? completedError;

  @override
  Future<GrowthCenter> center() async {
    if (centerError != null) throw centerError!;
    return centerData ??
        GrowthCenter(
          levelNo: 7,
          expValue: 12345,
          points: 8800,
          badges: <MedalBadge>[
            MedalBadge(
              badgeName: '开始在场',
              iconUrl: '',
              badgeCode: 'FIRST_STEP',
              obtainTime: '2026-07-12 10:30:00',
            ),
            MedalBadge(
              badgeName: '完成一程',
              iconUrl: '',
              badgeCode: 'TOPIC_CLEAR',
            ),
          ],
          missions: <GrowthMission>[],
        );
  }

  @override
  Future<GrowthLeaderboard> leaderboard({
    required String metric,
    required String period,
    int limit = 50,
  }) async {
    if (boardError != null) throw boardError!;
    return GrowthLeaderboard.fromJson(
      boardOverride ??
          <String, dynamic>{
            'metric': 'point',
            'period': 'total',
            'list': <dynamic>[],
            'me': <String, dynamic>{
              'rank': 42,
              'memberId': 1,
              'nickname': '阿兰',
              'avatar': '',
              'score': 1234567,
              'rankPercentage': 'TOP20%',
            },
          },
    );
  }

  @override
  Future<PlayGrowth> playGrowth() async {
    if (playError != null) throw playError!;
    return const PlayGrowth(
      level: 7,
      totalCheckins: 88,
      totalMileage: 123.4,
      streakDays: 3,
    );
  }

  @override
  Future<List<CompletedActivity>> myCompleted() async {
    if (completedError != null) throw completedError!;
    return <CompletedActivity>[
      CompletedActivity(
        activityId: 1,
        topicId: 5,
        name: '城墙线',
        cover: '',
        total: 6,
        doneCount: 6,
      ),
      CompletedActivity(
        activityId: 2,
        topicId: 5,
        name: '城墙线(第2期)',
        cover: '',
        total: 6,
        doneCount: 6,
      ),
    ];
  }
}
