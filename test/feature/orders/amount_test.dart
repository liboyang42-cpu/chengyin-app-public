// 订单卡要显示金额。
//
// ★ 起因:订单页整页看不到「付了多少钱」—— 而那是用户打开订单最先要找的东西。
//   查下去发现**不是后端没给**:`/api/registration/list` 返回的是完整
//   `CmsRegistration` 实体(controller 用 getDataTable(list) 包的),那上面有 8 个
//   金额字段;是 App 的 `MyRegistration.fromJson` 没解析。属前端缺口,不是后端缺口
//   —— 与「列表 VO 真缺时间/人数字段」那一类要分开看。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';

MyRegistration _parse(Object? amount) =>
    MyRegistration.fromJson(<String, dynamic>{
      'id': 1,
      'ownerType': 2,
      'ownerId': 2,
      'registrationNo': 'R1',
      'registrationStatus': 2,
      if (amount != null) 'payableAmount': amount,
      'cmsActivity': <String, dynamic>{'name': 'x'},
    });

void main() {
  test('解析后端下发的 payableAmount', () {
    expect(_parse(49.9).payableAmount, 49.9);
  });

  test('整数金额也要解析(后端可能给 int 不给 double)', () {
    expect(_parse(88).payableAmount, 88.0);
  });

  test('字段缺失时为 null,不崩也不显示 ¥0.00', () {
    // 显示成 ¥0.00 会让用户以为这单是免费的,比不显示更糟。
    expect(_parse(null).payableAmount, isNull);
  });

  test('零元单解析为 0,由页面渲染成「免费」', () {
    expect(_parse(0).payableAmount, 0.0);
  });
}
