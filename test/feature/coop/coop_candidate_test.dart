import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_candidate.dart';

void main() {
  ClubApply a(int? status) =>
      ClubApply.fromJson(<String, dynamic>{'clubName': 'X', 'status': status});

  group('★ 只有待处理才给按钮', () {
    test('待处理(0 或缺省)可操作', () {
      expect(a(0).actionable, isTrue);
      expect(a(null).actionable, isTrue);
    });
    test('已转邀约 / 已婉拒 / 已撤回都不给按钮', () {
      for (final int s in <int>[1, 2, 3]) {
        expect(a(s).actionable, isFalse,
            reason: 'status=$s 摆按钮的话点下去后端必拒');
      }
    });
  });

  group('状态文案', () {
    test('四态齐,不留空白', () {
      expect(a(0).statusText, '待处理');
      expect(a(1).statusText, '已婉拒');
      expect(a(2).statusText, '已撤回');
      expect(a(3).statusText, '已转为邀约');
      expect(a(null).statusText, '待处理');
    });
  });

  group('名字兜底', () {
    test('空 / 全空格 / 缺失都兜底', () {
      String n(Object? v) =>
          ClubApply.fromJson(<String, dynamic>{'clubName': v}).clubName;
      expect(n(''), '未命名俱乐部');
      expect(n('   '), '未命名俱乐部');
      expect(n(null), '未命名俱乐部');
      expect(n(' 城瘾club '), '城瘾club');
    });
    test('候选报名两种命名都收', () {
      expect(CandidateRegistration.fromJson(<String, dynamic>{'name': 'A'}).name, 'A');
      expect(
          CandidateRegistration.fromJson(<String, dynamic>{'merchantName': 'B'}).name,
          'B');
      expect(CandidateRegistration.fromJson(<String, dynamic>{}).name, '未命名候选');
    });
  });

  group('整体解析', () {
    test('两块都空 → isEmpty', () {
      expect(CoopCandidates.fromJson(<String, dynamic>{}).isEmpty, isTrue);
    });
    test('任一块有内容就不空', () {
      final c = CoopCandidates.fromJson(<String, dynamic>{
        'clubApplies': <dynamic>[
          <String, dynamic>{'clubName': 'A'}
        ],
      });
      expect(c.isEmpty, isFalse);
      expect(c.clubApplies.length, 1);
    });
    test('字段不是数组时不炸', () {
      final c = CoopCandidates.fromJson(<String, dynamic>{
        'clubApplies': 'oops',
        'registrations': 42,
      });
      expect(c.isEmpty, isTrue);
    });
  });
}
