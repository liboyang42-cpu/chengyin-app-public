// 创作者申请的四态。
//
// 后端归一成四个字符串(CreatorCenterServiceImpl:40-49、120-123):
//   not_applied / pending / approved / rejected
//
// ★ 最容易犯的错是把 `not_applied` 和 `rejected` 渲成同一屏("都不是创作者")——
//   但对用户完全不同:前者该看到「去申请」,后者该看到「为什么被拒、能不能再申请」。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/creator_center.dart';

CreatorCenter _c(Map<String, dynamic> j) => CreatorCenter.fromJson(j);

void main() {
  group('状态解析', () {
    test('四个取值各自映射', () {
      expect(CreatorApplyStatus.parse('not_applied'),
          CreatorApplyStatus.notApplied);
      expect(CreatorApplyStatus.parse('pending'), CreatorApplyStatus.pending);
      expect(CreatorApplyStatus.parse('approved'), CreatorApplyStatus.approved);
      expect(CreatorApplyStatus.parse('rejected'), CreatorApplyStatus.rejected);
    });

    test('★ 未知取值退到 notApplied —— 绝不能退到 approved', () {
      // 后端将来加了新状态时,页面退化成「去申请」比整页崩掉好;
      // 但退到 approved 会**给一个没通过审核的人开放创作者能力**。
      for (final String raw in <String>['', 'unknown', 'APPROVED_', 'x']) {
        expect(CreatorApplyStatus.parse(raw), CreatorApplyStatus.notApplied,
            reason: '「$raw」退错了档');
        expect(CreatorApplyStatus.parse(raw),
            isNot(CreatorApplyStatus.approved));
      }
      expect(CreatorApplyStatus.parse(null), CreatorApplyStatus.notApplied);
    });
  });

  group('★ 四态不许合并', () {
    test('只有 approved 算创作者 —— pending 不算', () {
      expect(_c(<String, dynamic>{'applyStatus': 'approved'}).isCreator, isTrue);
      expect(_c(<String, dynamic>{'applyStatus': 'pending'}).isCreator, isFalse,
          reason: '审核中就放开创作者能力,等于绕过审核');
      expect(
          _c(<String, dynamic>{'applyStatus': 'rejected'}).isCreator, isFalse);
    });

    test('审核中不能重复提交;已通过不需要再提交', () {
      expect(_c(<String, dynamic>{'applyStatus': 'pending'}).canApply, isFalse);
      expect(_c(<String, dynamic>{'applyStatus': 'approved'}).canApply, isFalse);
    });

    test('★ 没申请过和被驳回都能申请,但它们是两个不同的状态', () {
      final CreatorCenter notApplied =
          _c(<String, dynamic>{'applyStatus': 'not_applied'});
      final CreatorCenter rejected =
          _c(<String, dynamic>{'applyStatus': 'rejected'});
      // 两者都能再申请 ——
      expect(notApplied.canApply, isTrue);
      expect(rejected.canApply, isTrue);
      // 但**状态本身必须可分**,否则界面没法对被驳回的人说明原因。
      expect(notApplied.status, isNot(rejected.status));
    });
  });

  test('★ 被驳回但没给原因 → null,界面要说「未说明原因」而不是空着', () {
    final CreatorCenter c = _c(<String, dynamic>{
      'applyStatus': 'rejected',
      'profile': <String, dynamic>{'rejectReason': '   '},
    });
    expect(c.rejectReason, isNull);
  });

  test('驳回原因从 profile 里取得到', () {
    final CreatorCenter c = _c(<String, dynamic>{
      'applyStatus': 'rejected',
      'profile': <String, dynamic>{'rejectReason': '简介与实际内容不符'},
    });
    expect(c.rejectReason, '简介与实际内容不符');
  });

  test('收入金额保持字符串原样 —— 与商家结算同一条纪律', () {
    final CreatorCenter c = _c(<String, dynamic>{
      'applyStatus': 'approved',
      'recentIncome': <dynamic>[
        <String, dynamic>{'date': '2026-08-18', 'amount': '128.50', 'source': '分成'},
      ],
    });
    expect(c.recentIncome.single.amount, '128.50');
  });
}
