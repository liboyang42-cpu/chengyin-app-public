import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_invite.dart';

void main() {
  const t1 = CoopInviteTarget(toId: 7, name: 'A');

  group('★ 后端五道闸,前端先挡能挡的', () {
    test('没选主题 → 挡住并指出', () {
      const f = CoopInviteForm(targets: <CoopInviteTarget>[t1]);
      expect(f.canSubmit, isFalse);
      expect(f.blocker, '请先选择要合作的主题');
    });
    test('没选受邀方 → 挡住,并说清要选哪一类', () {
      const f = CoopInviteForm(topicId: 1);
      expect(f.canSubmit, isFalse);
      expect(f.blocker, '请至少选择一个商家');
      const c = CoopInviteForm(topicId: 1, type: CoopInviteType.club);
      expect(c.blocker, '请至少选择一个俱乐部');
    });
    test('都齐了 → 放行', () {
      const f = CoopInviteForm(topicId: 1, targets: <CoopInviteTarget>[t1]);
      expect(f.canSubmit, isTrue);
      expect(f.blocker, isNull);
    });
    test('固定合作费必须是正数', () {
      const missing = CoopInviteForm(
        topicId: 1,
        targets: <CoopInviteTarget>[t1],
        shareMode: CoopShareMode.fixed,
      );
      expect(missing.canSubmit, isFalse);
      expect(missing.blocker, '请填写大于 0 的固定合作费');
      expect(missing.copyWith(fixedFee: 0).canSubmit, isFalse);
      expect(missing.copyWith(fixedFee: 12.5).canSubmit, isTrue);
      expect(
        () => missing.toJson(t1),
        throwsStateError,
        reason: '即使调用方绕过按钮禁用，也不能产生 fixedFee=null 的假 payload',
      );
    });
  });

  group('★ 换类型必须清空已选(两套 id 空间)', () {
    test('商家 → 俱乐部,已选被清空', () {
      const f = CoopInviteForm(topicId: 1, targets: <CoopInviteTarget>[t1]);
      final next = f.copyWith(type: CoopInviteType.club);
      expect(next.targets, isEmpty, reason: '不清空会把商家 id 当俱乐部 id 发出去');
      expect(next.topicId, 1, reason: '主题不该被一起清掉');
    });
    test('类型没变时不清空', () {
      const f = CoopInviteForm(topicId: 1, targets: <CoopInviteTarget>[t1]);
      expect(f.copyWith(type: CoopInviteType.merchant).targets.length, 1);
      expect(f.copyWith(message: 'hi').targets.length, 1);
    });
  });

  group('提交体', () {
    test('商家 → inviteType 0 / toType merchant', () {
      const f = CoopInviteForm(topicId: 9, targets: <CoopInviteTarget>[t1]);
      final j = f.toJson(t1);
      expect(j['inviteType'], 0);
      expect(j['toType'], 'merchant');
      expect(j['toId'], 7);
      expect(j['topicId'], 9);
    });
    test('俱乐部 → inviteType 1 / toType club', () {
      const f = CoopInviteForm(
        topicId: 9,
        type: CoopInviteType.club,
        targets: <CoopInviteTarget>[t1],
      );
      final j = f.toJson(t1);
      expect(j['inviteType'], 1);
      expect(j['toType'], 'club');
    });
    test('留言为空时发小程序同款的角色默认邀请语', () {
      const f = CoopInviteForm(topicId: 9, targets: <CoopInviteTarget>[t1]);
      expect(f.toJson(t1)['message'], '邀请贵店承接本主题合作');
      expect(
        CoopInviteForm(
          topicId: 9,
          message: '  ',
          targets: const <CoopInviteTarget>[t1],
        ).toJson(t1)['message'],
        '邀请贵店承接本主题合作',
      );
      expect(
        const CoopInviteForm(
          topicId: 9,
          type: CoopInviteType.club,
          targets: <CoopInviteTarget>[t1],
        ).toJson(t1)['message'],
        '邀请贵俱乐部来参加活动',
      );
    });
    test('留言两端空白裁掉', () {
      const f = CoopInviteForm(
        topicId: 9,
        message: '  一起做吧  ',
        targets: <CoopInviteTarget>[t1],
      );
      expect(f.toJson(t1)['message'], '一起做吧');
    });
    test('★★ 商家员工代 owner 主题发邀约:scope 必须原样进提交体', () {
      const f = CoopInviteForm(
        topicId: 9,
        type: CoopInviteType.club,
        targets: <CoopInviteTarget>[t1],
        originApplyId: 31,
        scope: 'MERCHANT',
      );
      final j = f.toJson(t1);
      expect(
        j['scope'],
        'MERCHANT',
        reason: '小程序 pages/coop/invite/index.js:526 就是这句;'
            '漏了会被判成无权处理,而报错只说"失败"',
      );
      expect(j['originApplyId'], 31);
    });
    test('★ 没有归属标记时不发这个键(普通商家自己发的邀约)', () {
      const f = CoopInviteForm(topicId: 9, targets: <CoopInviteTarget>[t1]);
      expect(f.toJson(t1).containsKey('scope'), isFalse);
    });
    test('★ copyWith 不许把 scope 弄丢 —— 改一下留言就丢是最隐蔽的那种', () {
      const f = CoopInviteForm(
        topicId: 9,
        targets: <CoopInviteTarget>[t1],
        scope: 'MERCHANT',
      );
      expect(f.copyWith(message: '一起做吧').toJson(t1)['scope'], 'MERCHANT');
    });
    test('普通邀约只允许小程序现役的引流/固定两档', () {
      const traffic = CoopInviteForm(
        topicId: 9,
        targets: <CoopInviteTarget>[t1],
      );
      expect(traffic.toJson(t1)['shareMode'], 0);
      expect(traffic.toJson(t1).containsKey('fixedFee'), isFalse);

      const fixed = CoopInviteForm(
        topicId: 9,
        targets: <CoopInviteTarget>[t1],
        shareMode: CoopShareMode.fixed,
        fixedFee: 18.8,
      );
      expect(fixed.toJson(t1)['shareMode'], 2);
      expect(fixed.toJson(t1)['fixedFee'], 18.8);
      expect(
        fixed.toJson(t1).containsKey('shareRate'),
        isFalse,
        reason: '普通 /invite 后端明确拒绝分成模式',
      );
    });
    test('originApplyId 只跟 type1 俱乐部邀约发送', () {
      const club = CoopInviteForm(
        topicId: 9,
        type: CoopInviteType.club,
        targets: <CoopInviteTarget>[t1],
        originApplyId: 66,
      );
      expect(club.toJson(t1)['originApplyId'], 66);

      const merchant = CoopInviteForm(
        topicId: 9,
        targets: <CoopInviteTarget>[t1],
        originApplyId: 66,
      );
      expect(
        merchant.toJson(t1).containsKey('originApplyId'),
        isFalse,
        reason: '后端只允许开放报名溯源用于邀约俱乐部',
      );
    });
  });
}
