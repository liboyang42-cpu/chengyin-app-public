import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/growth_api.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/feature/p3/growth/growth_board_logic.dart';

void main() {
  group('★ 排行榜失败分类:业务失败 / HTTP 异常 / 断网 三种不同文案', () {
    test('业务错误(后端回了 msg)→ error,透传 msg', () {
      final f = classifyBoardFailure(GrowthException('请先登录'));
      expect(f.kind, BoardFailureKind.error);
      expect(f.message, '请先登录');
    });

    test('HTTP 非 200(有响应)→ notice,不说「请求失败」', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/api/growth/leaderboard'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/growth/leaderboard'),
          statusCode: 502,
        ),
      );
      final f = classifyBoardFailure(e);
      expect(f.kind, BoardFailureKind.notice);
      expect(f.message, '排行榜暂未开放，请稍后查看');
    });

    test('断网(无响应)→ error', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/api/growth/leaderboard'),
        error: 'Connection refused',
      );
      final f = classifyBoardFailure(e);
      expect(f.kind, BoardFailureKind.error);
    });

    test('未知异常 → error', () {
      final f = classifyBoardFailure(StateError('boom'));
      expect(f.kind, BoardFailureKind.error);
    });
  });

  group('★ 我的名次:rank=null 不是第 0 名', () {
    LeaderboardItem me({Object? rank}) => LeaderboardItem(
      rank: rank == null ? null : (rank as num).toInt(),
      memberId: 1,
      nickname: '阿兰',
      avatar: '',
      score: 12345,
      rankPercentage: 'TOP20%',
    );

    test('rank=null → view.rank 为 null,界面走「暂无排名」', () {
      final v = myRankView(me(rank: null), 'point');
      expect(v.rank, isNull, reason: '没有可排名数据 ≠ 第 0 名');
    });

    test('rank=0 → 显示真实的 0', () {
      final v = myRankView(me(rank: 0), 'point');
      expect(v.rank, 0);
    });

    test('昵称空 → 我;单位随 metric;分数千分位', () {
      final v = myRankView(
        LeaderboardItem(
          rank: 3,
          memberId: 1,
          nickname: '',
          avatar: '',
          score: 1234567,
          rankPercentage: null,
        ),
        'exp',
      );
      expect(v.name, '我');
      expect(v.unit, 'EXP');
      expect(v.scoreText, '1,234,567');
      expect(v.rankPercentage, isNull);
    });
  });

  group('GrowthLeaderboard 解析:me.rank null 与 0 不合并', () {
    test('me 缺失 rank 字段 → null', () {
      final board = GrowthLeaderboard.fromJson(<String, dynamic>{
        'metric': 'point',
        'period': 'total',
        'list': <dynamic>[],
        'me': <String, dynamic>{'score': 0},
      });
      expect(board.me.rank, isNull);
      expect(board.me.score, 0);
    });

    test('me.rank=0 → 0', () {
      final board = GrowthLeaderboard.fromJson(<String, dynamic>{
        'metric': 'point',
        'period': 'total',
        'list': <dynamic>[],
        'me': <String, dynamic>{'rank': 0, 'score': 5},
      });
      expect(board.me.rank, 0);
    });

    test('list 行解析 + 非 map 行跳过', () {
      final board = GrowthLeaderboard.fromJson(<String, dynamic>{
        'metric': 'point',
        'period': 'week',
        'list': <dynamic>[
          <String, dynamic>{'rank': 1, 'nickname': 'a', 'score': 10},
          'junk',
        ],
        'me': <String, dynamic>{},
      });
      expect(board.list.length, 1);
      expect(board.list.first.rank, 1);
    });
  });

  group('MedalBadge.obtainTime:没拿到 ≠ 空串', () {
    test('字段缺失 → null(展开时不编造「获得于」)', () {
      final b = MedalBadge.fromJson(
        <String, dynamic>{'badgeName': 'x', 'iconUrl': ''},
      );
      expect(b.obtainTime, isNull);
    });

    test('字段存在 → 原样保留', () {
      final b = MedalBadge.fromJson(<String, dynamic>{
        'badgeName': 'x',
        'iconUrl': '',
        'obtainTime': '2026-07-12 10:30:00',
      });
      expect(b.obtainTime, '2026-07-12 10:30:00');
    });
  });
}
