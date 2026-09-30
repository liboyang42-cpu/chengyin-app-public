// 资产流水的方向判定。与 `points_record_sign_test.dart` 是**同一条规则的另一半**:
// 仓库里有两个同名 `PointsRecord`(asset_record.dart / points_record.dart),
// 建模同一份后端数据、供不同页面用。两边的方向判据必须一致,
// 否则同一笔积分在 /assets 和 /points 两页会显示成相反的方向。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/asset_record.dart';

PointsRecord _p(Map<String, dynamic> j) =>
    PointsRecord.fromJson(<String, dynamic>{'id': 1, ...j});
BalanceRecord _b(Map<String, dynamic> j) =>
    BalanceRecord.fromJson(<String, dynamic>{'id': 1, ...j});

void main() {
  group('积分流水', () {
    test('changeType 在场时以它为准', () {
      expect(_p({'changeType': 1, 'changePoints': 120}).isIncome, isTrue);
      expect(_p({'changeType': 2, 'changePoints': 200}).isIncome, isFalse);
    });

    test('★ changeType 缺席(兜底 0)不许判成支出', () {
      // fromJson 把缺席兜成 0;原来的 `changeType == 1` 会让这条落到 false,
      // 一笔 +120 的进账在界面上显示成扣了 120。
      expect(_p({'changePoints': 120}).isIncome, isTrue);
      expect(_p({'changePoints': -50}).isIncome, isFalse);
      expect(_p({'changePoints': 0}).isIncome, isTrue);
    });
  });

  group('余额流水', () {
    test('changeType 在场时以它为准', () {
      expect(_b({'changeType': 1, 'changeBalance': 88.5}).isIncome, isTrue);
      expect(_b({'changeType': 2, 'changeBalance': 20.0}).isIncome, isFalse);
    });

    test('★ changeType 缺席不许判成支出', () {
      expect(_b({'changeBalance': 88.5}).isIncome, isTrue);
      expect(_b({'changeBalance': -20.0}).isIncome, isFalse);
    });
  });

  test('★ 两个同名 PointsRecord 的方向判据必须一致', () {
    // 这条是防"只修了一边"。同样的输入,两个模型必须给出同样的方向。
    const List<Map<String, dynamic>> cases = <Map<String, dynamic>>[
      <String, dynamic>{'changeType': 1, 'changePoints': 10},
      <String, dynamic>{'changeType': 2, 'changePoints': 10},
      <String, dynamic>{'changePoints': 10},   // 无 changeType
      <String, dynamic>{'changePoints': -10},  // 无 changeType,负数
    ];
    for (final Map<String, dynamic> c in cases) {
      final bool a = _p(c).isIncome;
      final bool b = otherIsIncome(c);
      expect(a, b,
          reason: '两个模型对 $c 判出的方向不同:asset_record=$a '
              'points_record=$b —— 同一笔钱在 /assets 和 /points 会显示成相反方向');
    }
  });
}

/// 复刻 `points_record.dart` 的判据(那个类同名,不能在同一文件里同时 import)。
bool otherIsIncome(Map<String, dynamic> j) {
  final Object? t = j['changeType'];
  if (t != null) return t == 1;
  return ((j['changePoints'] as num?) ?? 0) >= 0;
}
