// 队长核销队员票。
//
// ★★★ **必须从本团入口走,必须带 activityId**。
//   小程序注释原话:「带队主题的玩家票必须从当前 activity 入口核销。
//   不能复用商家首页的通用扫码,否则请求没有场次身份,后端会 fail closed,
//   **结算也无法区分同主题的不同团**」。
//
// ★★ 动作只给队长:判据 `isLeader && exists`,与其余队长动作同一道闸 ——
//   队员看到它点下去必被拒。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/club_lead.dart';

// ⚠️ allArrived 是**派生的**(arrived >= members.length),不是后端下发的字段 ——
//   第一版我直接往 fixture 里塞 'allArrived',结果它恒为 false。
TeamProgress _p({
  bool leader = true,
  bool exists = true,
  bool allArrived = false,
}) => TeamProgress.fromJson(<String, dynamic>{
  'exists': exists,
  'isLeader': leader,
  'arrived': allArrived ? 2 : 1,
  'members': <dynamic>[
    <String, dynamic>{'memberId': 1, 'nickname': '甲'},
    <String, dynamic>{'memberId': 2, 'nickname': '乙'},
  ],
});

void main() {
  test('★★★ 核销队员票只给队长', () {
    expect(availableLeadActions(_p()), contains(LeadAction.verifyMemberTicket));
    expect(
      availableLeadActions(_p(leader: false)),
      isEmpty,
      reason: '队员看到它点下去必被后端拒',
    );
    expect(
      availableLeadActions(_p(exists: false)),
      isEmpty,
      reason: '没有团的时候没有场次身份,这个动作无从谈起',
    );
  });

  test('★★ 它不依赖「全员到齐」—— 那是解锁下一章的条件', () {
    // 到齐前也要能核销:队员是陆续到的,到一个核一个。
    final List<LeadAction> before = availableLeadActions(_p());
    expect(before, contains(LeadAction.verifyMemberTicket));
    expect(before, isNot(contains(LeadAction.unlockChapter)));

    final List<LeadAction> after = availableLeadActions(_p(allArrived: true));
    expect(after, contains(LeadAction.verifyMemberTicket));
    expect(after, contains(LeadAction.unlockChapter));
  });

  test('★ 文案说清是核销队员的票,不是自己的', () {
    // 照真源工具行(index.wxml:608)逐字:「扫成员票核销」。
    expect(LeadAction.verifyMemberTicket.label, '扫成员票核销');
  });
}
