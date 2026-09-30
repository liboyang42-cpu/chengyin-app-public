// 承接邀约收件箱:按 partyType 分派到正确的接口。
//
// ★★ 原来这一页对**所有行**都调 `/v2/organizer-invites/{id}/{accept|decline}`,
//   而那条接口要**官方发布白名单**。收件箱本身只要求登录,里面同时装着
//   OFFICIAL / MERCHANT / CLUB 三类(SQL 的 where 就是这三个 or)。
//   ⇒ 商家点「接受」拿到的是「无官方发布权限」——
//     一个点了必然失败的按钮,而这页本来就是发给商家看的。
//   反向也不行:后端 respondParty 对 OFFICIAL 直接回
//   「官方主办关系只能由专用受控命令处理」。两条路严格互斥。
//
// ★ 第二个原来就在的错:模型读 `state`,后端字段是 `status`
//   (SQL 里就是 `p.status`)。读错名字不报错,只是恒为 null ——
//   于是"还能不能操作"恒真,已接受的邀约照样显示两个按钮。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/official_event.dart';
import '../../support/source_text.dart';

PartyInviteItem item(Map<String, dynamic> j) => PartyInviteItem.fromJson(j);

void main() {
  group('字段名', () {
    test('★★ 读的是 status 不是 state', () {
      final p = item(<String, dynamic>{'partyId': 1, 'status': 'ACCEPTED'});
      expect(p.status, 'ACCEPTED',
          reason: '读成 state 的话这里是 null,已接受的邀约会继续显示「接受/拒绝」');
    });

    test('后端真的不发 state —— 发了也不该认', () {
      final p = item(<String, dynamic>{'partyId': 1, 'state': 'ACCEPTED'});
      expect(p.status, isNull);
    });
  });

  group('分派', () {
    test('★★ MERCHANT / CLUB 走 parties 路径', () {
      for (final String t in <String>['MERCHANT', 'CLUB']) {
        final p = item(<String, dynamic>{'partyId': 1, 'partyType': t, 'status': 'INVITED'});
        expect(p.isPartyRoute, isTrue, reason: '$t 应走 parties');
        expect(p.organizerActionable, isFalse,
            reason: '$t 走 organizer-invites 会撞「无官方发布权限」');
      }
    });

    test('★★ OFFICIAL 走 organizer-invites', () {
      final p = item(<String, dynamic>{
        'partyId': 1,
        'partyType': 'OFFICIAL',
        'status': 'INVITED',
      });
      expect(p.isPartyRoute, isFalse,
          reason: 'OFFICIAL 走 parties 会撞「官方主办关系只能由专用受控命令处理」');
      expect(p.organizerActionable, isTrue);
    });

    test('partyType 缺席时两条路都不给 —— 宁可不显示按钮', () {
      final p = item(<String, dynamic>{'partyId': 1, 'status': 'INVITED'});
      expect(p.isPartyRoute, isFalse);
      expect(p.organizerActionable, isFalse);
      expect(p.actions, isEmpty,
          reason: '不知道该走哪条就别给按钮 —— 猜一条等于二选一地必错一半');
    });
  });

  group('按状态露动作', () {
    test('★ INVITED 的商家邀约:接受 / 拒绝,没有退出', () {
      final p = item(<String, dynamic>{
        'partyId': 1,
        'partyType': 'MERCHANT',
        'status': 'INVITED',
      });
      expect(p.actions, <OfficialPartyAction>[
        OfficialPartyAction.accept,
        OfficialPartyAction.decline,
      ]);
    });

    test('★ ACCEPTED / ACTIVE:只有退出承接', () {
      for (final String st in <String>['ACCEPTED', 'ACTIVE']) {
        final p = item(<String, dynamic>{
          'partyId': 1,
          'partyType': 'CLUB',
          'status': st,
        });
        expect(p.actions, <OfficialPartyAction>[OfficialPartyAction.withdraw],
            reason: '$st 下摆「接受」= 点了必撞「当前邀约不可接受」');
      }
    });

    test('★ OFFICIAL 已接受 → 不再可操作', () {
      final p = item(<String, dynamic>{
        'partyId': 1,
        'partyType': 'OFFICIAL',
        'status': 'ACCEPTED',
      });
      expect(p.organizerActionable, isFalse);
    });
  });

  test('★ 页面确实按 partyType 分派 —— 不是只在模型里算了一遍', () {
    final String code =
        codeOf('lib/feature/official/official_inbox_page.dart');
    expect(code.contains("item.partyType == 'OFFICIAL'"), isTrue);
    expect(code.contains('_respondOrganizer'), isTrue);
    expect(code.contains('_respondParty'), isTrue);
    // 原来的写法:所有行统一 respondInvite。留着就等于没修。
    expect(code.contains('item.actionable'), isFalse,
        reason: '还在用那个恒真的 actionable —— 说明分派没真接上');
  });

  test('★ 退出承接的文案不能写成「拒绝」', () {
    final String code =
        codeOf('lib/feature/official/official_inbox_page.dart');
    expect(code.contains('退出承接'), isTrue,
        reason: 'WITHDRAW 是「已经接了又退出」,写成「拒绝」'
            '会让用户以为在拒绝一个还没接的邀约');
  });
}
