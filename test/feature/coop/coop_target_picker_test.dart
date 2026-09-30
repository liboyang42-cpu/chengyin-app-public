// 候选行折成邀约对象。
//
// ★ 后端三个来源的字段名不一样(id / merchantId / clubId),
//   折错的表现是「列表有内容但一提交全失败」。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/coop/coop_target_picker.dart';

void main() {
  test('三种 id 字段名都认', () {
    for (final String k in <String>['id', 'merchantId', 'clubId']) {
      final t = coopTargetFromRow(<String, dynamic>{k: 7, 'name': '甲'});
      expect(t?.toId, 7, reason: '$k 没认出来');
    }
  });

  test('★★ id 拿不到就整条丢掉,不兜 0', () {
    // toId=0 的候选提交必被后端拒,而界面上它和别的长得一样 ——
    // 用户不知道为什么只有这条失败。
    expect(coopTargetFromRow(<String, dynamic>{'name': '没有 id'}), isNull);
    expect(coopTargetFromRow(<String, dynamic>{'id': 0, 'name': '零'}), isNull);
    expect(coopTargetFromRow(<String, dynamic>{'id': '', 'name': '空串'}), isNull);
  });

  test('id 是字符串也认(后端两种形态都出现过)', () {
    expect(coopTargetFromRow(<String, dynamic>{'id': '12', 'name': '甲'})?.toId, 12);
  });

  test('名字三种字段名都认;都拿不到时用 #id 兜,不留空条目', () {
    expect(coopTargetFromRow(<String, dynamic>{'id': 1, 'merchantName': '咖啡'})?.name,
        '咖啡');
    expect(coopTargetFromRow(<String, dynamic>{'id': 1, 'clubName': '夜跑'})?.name, '夜跑');
    expect(coopTargetFromRow(<String, dynamic>{'id': 9})?.name, '#9',
        reason: '空条目点不出所以然,#id 至少能对上');
  });
}
