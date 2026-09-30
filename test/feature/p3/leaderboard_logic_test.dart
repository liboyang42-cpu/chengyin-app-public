import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/feature/p3/growth/leaderboard_controller.dart';

void main() {
  GrowthLeaderboard board({List<LeaderboardItem> list = const <LeaderboardItem>[], LeaderboardItem? me}) =>
      GrowthLeaderboard(
        metric: 'point',
        period: 'total',
        list: list,
        me: me ?? LeaderboardItem(
          rank: null,
          memberId: 0,
          nickname: '',
          avatar: '',
          score: 0,
          rankPercentage: null,
        ),
      );

  LeaderboardItem row(int rank, {String nickname = 'a', int score = 10}) =>
      LeaderboardItem(
        rank: rank,
        memberId: rank,
        nickname: nickname,
        avatar: '',
        score: score,
        rankPercentage: null,
      );

  group('buildLeaderboardData', () {
    test('前 3 进领奖台,其余进列表', () {
      final d = buildLeaderboardData(board(list: <LeaderboardItem>[
        for (var i = 1; i <= 5; i++) row(i),
      ]));
      expect(d.top3[0]!.rank, 1);
      expect(d.top3[1]!.rank, 2);
      expect(d.top3[2]!.rank, 3);
      expect(d.rest.map((r) => r.rank), <int>[4, 5]);
    });

    test('不足 3 名 → 领奖台空位为 null,不崩', () {
      final d = buildLeaderboardData(board(list: <LeaderboardItem>[row(1)]));
      expect(d.top3[0]!.rank, 1);
      expect(d.top3[1], isNull);
      expect(d.top3[2], isNull);
      expect(d.rest, isEmpty);
    });

    test('★ me.rank=null → me 不展示(没有可排名数据 ≠ 第 0 名)', () {
      final d = buildLeaderboardData(board(list: <LeaderboardItem>[]));
      expect(d.me, isNull);
    });

    test('me.rank=0 → 展示真实第 0 名', () {
      final d = buildLeaderboardData(board(
        list: <LeaderboardItem>[],
        me: LeaderboardItem(
          rank: 0,
          memberId: 1,
          nickname: '阿兰',
          avatar: '',
          score: 5,
          rankPercentage: 'TOP100%',
        ),
      ));
      expect(d.me, isNotNull);
      expect(d.me!.rank, 0);
    });

    test('单位随 metric:exp → EXP', () {
      final d = buildLeaderboardData(
        GrowthLeaderboard(
          metric: 'exp',
          period: 'total',
          list: <LeaderboardItem>[],
          me: LeaderboardItem(
            rank: null,
            memberId: 0,
            nickname: '',
            avatar: '',
            score: 0,
            rankPercentage: null,
          ),
        ),
      );
      expect(d.unit, 'EXP');
    });
  });

  group('LeaderboardQuery', () {
    test('copyWith 只改指定维度,equality 按两个维度', () {
      const q = LeaderboardQuery(metric: 'point', period: 'total');
      expect(q.copyWith(period: 'week'),
          const LeaderboardQuery(metric: 'point', period: 'week'));
      expect(q, const LeaderboardQuery(metric: 'point', period: 'total'));
      expect(q == const LeaderboardQuery(metric: 'exp', period: 'total'),
          isFalse);
    });
  });
}
