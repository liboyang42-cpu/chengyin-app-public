// 邀请记录的状态×文案表。★ 逐条对着小程序
// components/cy/scene-member-invite-history/index.js 的 buildGroups 校。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/account/invite_history_logic.dart';

typedef Row = ({int? eventType, String? eventId, num? changePoints, String? createTime});
typedef Member = ({int id, String name, String? avatar, String? createTime});

void main() {
  group('积分流水折成奖励表', () {
    test('只认 eventType==5 的正数行', () {
      final Map<String, InviteReward> m = inviteRewardMap(<Row>[
        (eventType: 5, eventId: '7', changePoints: 30, createTime: '2026-08-01 10:00:00'),
        (eventType: 3, eventId: '8', changePoints: 30, createTime: null), // 别的事件
        (eventType: 5, eventId: '9', changePoints: -30, createTime: null), // 扣减
        (eventType: 5, eventId: '0', changePoints: 30, createTime: null), // 无效 id
      ]);
      expect(m.keys.toSet(), <String>{'7'});
      expect(m['7']!.points, 30);
    });

    test('同一个人多条奖励累加', () {
      final Map<String, InviteReward> m = inviteRewardMap(<Row>[
        (eventType: 5, eventId: '7', changePoints: 30, createTime: '2026-08-01 10:00:00'),
        (eventType: 5, eventId: '7', changePoints: 20, createTime: '2026-08-02 10:00:00'),
      ]);
      expect(m['7']!.points, 50);
      expect(m['7']!.createTime, '2026-08-01 10:00:00', reason: '保留最早那条的时间');
    });

    test('★ 前导零要归一 —— 不然「奖励到账了却显示待解锁」', () {
      final Map<String, InviteReward> m = inviteRewardMap(<Row>[
        (eventType: 5, eventId: '007', changePoints: 30, createTime: null),
      ]);
      expect(m.containsKey('7'), isTrue);
    });

    test('非纯数字 id 一律作废', () {
      expect(normalizeId('7a'), '');
      expect(normalizeId(null), '');
      expect(normalizeId('0'), '');
      expect(normalizeId(7), '7');
    });
  });

  group('★★ rewardReady —— 「没赚到」和「没看全」不是一回事', () {
    test('流水没拉到 ⇒ 不许下结论', () {
      expect(inviteRewardReady(fetched: null, total: null), isFalse);
    });
    test('后端没给 total ⇒ 按拉到的算数', () {
      expect(inviteRewardReady(fetched: 10, total: null), isTrue);
    });
    test('total 比拉到的多 ⇒ 没看全', () {
      expect(inviteRewardReady(fetched: 200, total: 512), isFalse);
    });
    test('total 不超过拉到的 ⇒ 看全了', () {
      expect(inviteRewardReady(fetched: 200, total: 200), isTrue);
    });
  });

  group('分组与四种文案', () {
    const List<Member> two = <Member>[
      (id: 7, name: '小李', avatar: null, createTime: '2026-08-03 09:05:00'),
      (id: 8, name: '小王', avatar: null, createTime: '2026-08-04 21:30:00'),
    ];

    test('有奖励 ⇒ 已到账 + 具体积分', () {
      final List<InviteGroup> g = buildInviteGroups(
        members: two,
        rewards: <String, InviteReward>{'7': const InviteReward(30, '2026-08-05 12:00:00')},
        rewardReady: true,
      );
      expect(g.single.label, '2026年8月');
      expect(g.single.rows[0].statusText, '首购奖励已到账');
      expect(g.single.rows[0].rewardText, '+30 积分');
    });

    test('看全了没奖励 ⇒ 首购待完成 / 待解锁', () {
      final List<InviteGroup> g = buildInviteGroups(
        members: two, rewards: const <String, InviteReward>{}, rewardReady: true);
      expect(g.single.rows[0].statusText, '已加入 · 首购待完成');
      expect(g.single.rows[0].rewardText, '待解锁');
    });

    test('★ 没看全 ⇒ 必须说「待同步」,不许说「待完成」', () {
      final List<InviteGroup> g = buildInviteGroups(
        members: two, rewards: const <String, InviteReward>{}, rewardReady: false);
      expect(g.single.rows[0].statusText, '已加入 · 奖励待同步');
      expect(g.single.rows[0].rewardText, '待同步');
      expect(g.single.rows[0].statusText, isNot(contains('待完成')),
          reason: '流水没拉全就说「首购待完成」= 在编;用户会以为朋友没下单');
    });

    test('邀请时间缺失 ⇒ 说「暂未记录」,有奖励时补上到账时间', () {
      final List<InviteGroup> g = buildInviteGroups(
        members: const <Member>[(id: 7, name: '小李', avatar: null, createTime: null)],
        rewards: <String, InviteReward>{'7': const InviteReward(30, '2026-08-05 12:00:00')},
        rewardReady: true,
      );
      expect(g.single.label, '其他邀请');
      expect(g.single.rows[0].timeText, '邀请时间暂未记录');
      expect(g.single.rows[0].statusText, '首购奖励已到账 · 8月5日 12:00');
    });

    test('★ 整组零奖励 ⇒ 组头显示「N 人」,不显示「+0 积分」', () {
      final List<InviteGroup> g = buildInviteGroups(
        members: two, rewards: const <String, InviteReward>{}, rewardReady: true);
      expect(g.single.rewardText, '2 人');
      expect(g.single.rewardText, isNot(contains('+0')),
          reason: '「+0 积分」看着像结算错了');
    });

    test('跨月分两组,且不重排后端顺序', () {
      final List<InviteGroup> g = buildInviteGroups(
        members: const <Member>[
          (id: 7, name: 'a', avatar: null, createTime: '2026-08-03 09:00:00'),
          (id: 8, name: 'b', avatar: null, createTime: '2026-07-30 09:00:00'),
          (id: 9, name: 'c', avatar: null, createTime: '2026-08-01 09:00:00'),
        ],
        rewards: const <String, InviteReward>{}, rewardReady: true);
      expect(g.map((InviteGroup x) => x.label).toList(), <String>['2026年8月', '2026年7月']);
      expect(g[0].rows.map((InviteRow r) => r.name).toList(), <String>['a', 'c']);
    });
  });
}
