// 「点到店」的三态。**全部走 success,判据在 data 不在 code。**
//
// 后端(ApiRoamController:457-495):
//   ① tooFar: true          → 离得太远,什么都没发生
//   ② participating: true   → 参与据点,要接着走扫码核销(带 poiId)
//   ③ participating: false  → 非参与点,已直接点亮;firstVisit 决定发不发探索值
//
// ★ 只判 `code == 200` 会把「离得有点远」当成打卡成功 ——
//   用户站在两条街外,App 告诉他已经到店了。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/roam.dart';

RoamCheckinResult _r(Map<String, dynamic> body) =>
    RoamCheckinResult.fromBody(body);

void main() {
  test('★ tooFar → 不是成功,是「没到」', () {
    final RoamCheckinResult r = _r(<String, dynamic>{
      'code': 200,
      'msg': '离得有点远，走近点',
      'data': <String, dynamic>{'tooFar': true},
    });
    expect(
      r.outcome,
      RoamCheckinOutcome.tooFar,
      reason: 'code 是 200,只看它就会渲成打卡成功',
    );
    expect(r.message, contains('走近点'));
  });

  test('★ 参与据点 → 需要扫码,并带出 poiId', () {
    final RoamCheckinResult r = _r(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'participating': true, 'poiId': 42},
    });
    expect(r.outcome, RoamCheckinOutcome.needsScan);
    expect(r.poiId, 42, reason: '没有 poiId 就跳不到扫码页');
  });

  test('非参与点 → 已点亮', () {
    final RoamCheckinResult r = _r(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'participating': false, 'firstVisit': true},
    });
    expect(r.outcome, RoamCheckinOutcome.lit);
    expect(r.firstVisit, isTrue);
  });

  test('★ 首亮读服务端 xp;非首亮兜底文案是「已点亮过」不是失败', () {
    final RoamCheckinResult first = _r(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'participating': false,
        'firstVisit': true,
        'xp': 15,
      },
    });
    expect(first.xp, 15, reason: '「+N 探索值」只能来自回执,不能本地编');
    expect(first.message, '已点亮');
    final RoamCheckinResult repeat = _r(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'participating': false, 'firstVisit': false},
    });
    expect(repeat.xp, 0);
    expect(repeat.outcome, RoamCheckinOutcome.lit);
    expect(repeat.message, '已点亮过');
  });

  test('★ 非首次到点也是成功 —— 只是不再发探索值,别渲成失败', () {
    final RoamCheckinResult r = _r(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'participating': false, 'firstVisit': false},
    });
    expect(r.outcome, RoamCheckinOutcome.lit);
    expect(r.firstVisit, isFalse);
  });

  test('★ 三态两两不同 —— 防止以后被合并成「成功/失败」两态', () {
    final Set<RoamCheckinOutcome> all = <RoamCheckinOutcome>{
      _r(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'tooFar': true},
      }).outcome,
      _r(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'participating': true},
      }).outcome,
      _r(<String, dynamic>{'code': 200, 'data': <String, dynamic>{}}).outcome,
    };
    expect(all.length, 3);
  });

  group('迷雾格', () {
    test('对象与裸字符串两种下发都收', () {
      expect(RoamTile.fromJson('a:1').key, 'a:1');
      expect(RoamTile.fromJson(<String, dynamic>{'tileKey': 'b:2'}).key, 'b:2');
      expect(RoamTile.fromJson(<String, dynamic>{'key': 'c:3'}).key, 'c:3');
    });
  });
}
