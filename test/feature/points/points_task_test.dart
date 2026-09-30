// 赚分任务的过滤规则。
//
// ★★ `eventType == 14`(解锁提示)是**花分**规则。把它列进「怎么赚分」,
//   等于告诉用户"花分能赚分" —— 这条如果自己从头写,几乎必然漏掉。
//   判据抄小程序 components/cy/profile 里的同一处过滤。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/points_task.dart';

PointsTask _t({int eventType = 1, int status = 1}) =>
    PointsTask.fromJson(<String, dynamic>{
      'id': 1,
      'eventType': eventType,
      'title': '完成一次探店',
      'description': '每完成一次探店日',
      'value': 12.00,
      'pointsNum': 3,
      'status': status,
    });

void main() {
  test('★ 启用中的赚分规则要列出来', () {
    expect(_t().isEarnTask, isTrue);
    expect(_t().points, 12, reason: 'value 是 BigDecimal,12.00 要取成 12');
    expect(_t().doneCount, 3);
  });

  test('★★ 没启用的规则不许列 —— 列出来等于承诺一件做不到的事', () {
    expect(_t(status: 0).isEarnTask, isFalse);
  });

  test('★★★ 解锁提示(eventType=14)是花分,不是赚分任务', () {
    expect(_t(eventType: PointsTask.kSpendHintUnlock).isEarnTask, isFalse,
        reason: '列进赚分列表 = 告诉用户"花分能赚分"');
  });
}
