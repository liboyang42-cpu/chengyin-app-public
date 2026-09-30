import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/club_lead.dart';

void main() {
  TeamMember mem(int id, {bool arrived = false, bool leader = false}) =>
      TeamMember(
        memberId: id,
        nickname: 'U$id',
        arrived: arrived,
        isLeader: leader,
      );

  TeamProgress p({
    bool exists = true,
    bool isLeader = true,
    int arrived = 0,
    int total = 0,
  }) => TeamProgress(
    exists: exists,
    isLeader: isLeader,
    arrived: arrived,
    members: List<TeamMember>.generate(
      total,
      (int i) => mem(i + 1, arrived: i < arrived),
    ),
  );

  group('★ 没开队不是错误', () {
    test('exists=false → 界面该给「开始带队」而不是「加载失败」', () {
      const t = TeamProgress(exists: false);
      expect(t.exists, isFalse);
      expect(availableLeadActions(t), isEmpty, reason: '还没开队时不该摆队长动作');
    });
  });

  group('★ 非队长一个动作都不给', () {
    test('队员看不到任何队长动作', () {
      expect(
        availableLeadActions(p(isLeader: false, total: 3)),
        isEmpty,
        reason: '后端会拒,摆出来就是骗人',
      );
    });
    test('队长有广播与结算', () {
      final a = availableLeadActions(p(total: 3));
      expect(a, contains(LeadAction.broadcast));
      expect(a, contains(LeadAction.settle));
    });
  });

  group('★ 解锁下一章:全员到齐才给', () {
    test('没到齐 → 不给按钮,并说清还差几人', () {
      final t = p(arrived: 2, total: 5);
      expect(
        availableLeadActions(t),
        isNot(contains(LeadAction.unlockChapter)),
      );
      expect(unlockBlockedReason(t), '还差 3 人到达才能解锁下一章');
    });
    test('到齐 → 给按钮,不再显示阻塞说明', () {
      final t = p(arrived: 5, total: 5);
      expect(availableLeadActions(t), contains(LeadAction.unlockChapter));
      expect(unlockBlockedReason(t), isNull);
    });
    test('超额也算到齐(数据异常时别卡住队长)', () {
      expect(p(arrived: 7, total: 5).allArrived, isTrue);
    });
    test('★ 空队伍不算到齐 —— 否则 0>=0 会让空队直接放行', () {
      expect(p(arrived: 0, total: 0).allArrived, isFalse);
      expect(
        availableLeadActions(p(total: 0)),
        isNot(contains(LeadAction.unlockChapter)),
      );
    });
    test('非队长不显示阻塞说明(那不是他的事)', () {
      expect(
        unlockBlockedReason(p(isLeader: false, arrived: 1, total: 5)),
        isNull,
      );
    });
  });

  group('★ 到达进度:空队伍不显示 0/0', () {
    test('没有成员 → null', () {
      expect(p(total: 0).arrivedText, isNull, reason: '「0/0」既没信息,又让人以为出错了');
    });
    test('有成员 → 正常显示', () {
      expect(p(arrived: 2, total: 5).arrivedText, '2 / 5 人已到');
    });
  });

  group('成员名兜底', () {
    test('后端拿不到用户时下发空串 —— 兜底而不是留白', () {
      final m = TeamMember.fromJson(<String, dynamic>{
        'memberId': 42,
        'nickname': '',
      });
      expect(m.displayName, '队员 42');
      expect(
        TeamMember.fromJson(<String, dynamic>{'memberId': 42}).displayName,
        '队员 42',
      );
    });
    test('有昵称时裁掉空白', () {
      expect(
        TeamMember.fromJson(<String, dynamic>{
          'memberId': 1,
          'nickname': ' 阿岚 ',
        }).displayName,
        '阿岚',
      );
    });
  });
}
