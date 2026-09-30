// 积分统计 + 邀请列表。
//
// ★ 两处「有输入没输出」的缺口:
//   · 积分页只有流水,没有「我排第几」;
//   · 设置里能「填写邀请人」,却看不到自己邀请了谁。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/points_statistics.dart';

PointsStatistics _s(Map<String, dynamic> j) => PointsStatistics.fromJson(j);

void main() {
  group('积分统计', () {
    test('字段原样带出', () {
      final PointsStatistics s = _s(<String, dynamic>{
        'weekPoints': '120.00',
        'rankPercentage': '87%',
        'totalUsers': 5300,
        'userRank': 689,
      });
      expect(s.weekPoints, '120.00');
      expect(s.rankPercentage, '87%',
          reason: '名次百分比后端给的是字符串 —— 转 double 再格式化会引入舍入差异');
      expect(s.hasRank, isTrue);
    });

    test('★ 「没有名次」和「第 0 名」是两回事', () {
      // 本周零积分未入榜时,后端可能不给 userRank。
      expect(_s(<String, dynamic>{'totalUsers': 5300}).userRank, isNull);
      expect(_s(<String, dynamic>{'totalUsers': 5300}).hasRank, isFalse);
    });

    test('★ 有 rank 没 total 时不算「有名次」—— 那句话是悬空的', () {
      final PointsStatistics s = _s(<String, dynamic>{'userRank': 12});
      expect(s.userRank, 12);
      expect(s.hasRank, isFalse,
          reason: '「第 12 名」没有分母,读者无法判断这是好还是坏');
    });

    test('★ weekPoints 缺席是 null 不是 0', () {
      // 「这周没赚到」和「统计没算出来」是两回事。
      expect(_s(<String, dynamic>{}).weekPoints, isNull);
      expect(_s(<String, dynamic>{'weekPoints': '0.00'}).weekPoints, '0.00');
    });
  });

  group('邀请列表', () {
    InvitedMember m(Map<String, dynamic> j) =>
        InvitedMember.fromJson(<String, dynamic>{'id': 1, ...j});

    test('没有昵称时兜底文案不进头像', () {
      final InvitedMember x = m(<String, dynamic>{});
      expect(x.displayName, '城瘾用户');
      expect(x.avatarName, isNull,
          reason: '兜底文案进头像会渲出一个「城」字当姓氏');
    });

    test('有昵称时两者一致', () {
      final InvitedMember x = m(<String, dynamic>{'nickname': '小李'});
      expect(x.displayName, '小李');
      expect(x.avatarName, '小李');
    });
  });
}
