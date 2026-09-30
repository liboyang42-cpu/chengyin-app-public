// 积分正负号。**这是钱面上的显示**,错了用户会以为自己被扣了分。
//
// 2026-08-19 拍 page_points 基准图时实拍到两种错法:
//   · changeType 缺席 → 一笔 +120 的收入渲成「-120」
//   · changePoints 本身是负数 → 渲成「--200」(符号拼了两次)
// 前者的根因是 `changeType == 1` 在 null 时落到 false,**默认判成支出**。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/points_record.dart';

PointsRecord _r(Map<String, dynamic> j) =>
    PointsRecord.fromJson(<String, dynamic>{'id': 1, ...j});

/// 复刻页面的拼法,保证这里测的和界面渲的是同一件事。
String _display(PointsRecord r) =>
    '${r.isIncome ? '+' : '-'}${r.displayPoints}';

void main() {
  group('changeType 在场时以它为准', () {
    test('1 = 收入', () {
      expect(_display(_r({'changeType': 1, 'changePoints': 120})), '+120');
    });
    test('2 = 支出', () {
      expect(_display(_r({'changeType': 2, 'changePoints': 200})), '-200');
    });
    test('★ changeType=2 但金额是负数 —— 不许出现双负号', () {
      expect(_display(_r({'changeType': 2, 'changePoints': -200})), '-200');
    });
    test('★ changeType=1 且金额是负数 —— 以 changeType 为准,不被符号带跑', () {
      expect(_display(_r({'changeType': 1, 'changePoints': -120})), '+120');
    });
  });

  group('★ changeType 缺席时不许默认判成支出', () {
    test('正数 → 收入', () {
      // 原来 `changeType == 1` 在 null 时落到 false,这条会渲成「-120」:
      // 用户赚了 120 分,界面告诉他扣了 120。
      expect(_display(_r({'changePoints': 120})), '+120');
    });
    test('负数 → 支出(符号本身就是方向信息)', () {
      expect(_display(_r({'changePoints': -200})), '-200');
    });
    test('0 → 按收入侧显示,不显示成扣分', () {
      expect(_display(_r({'changePoints': 0})), '+0');
    });
  });

  test('★ 收入与支出的显示必须不同 —— 防止以后被改成同一个模板', () {
    final String income = _display(_r({'changeType': 1, 'changePoints': 50}));
    final String expense = _display(_r({'changeType': 2, 'changePoints': 50}));
    expect(income, isNot(expense));
  });
}
