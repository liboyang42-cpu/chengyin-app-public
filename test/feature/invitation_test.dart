import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/invitation.dart';

void main() {
  String? r(String? code, {int? me}) =>
      InviterBinding.localReject(inviterId: code, myMemberId: me);

  group('本地能挡的先挡', () {
    test('空 / 全空格', () {
      expect(r(null), '邀请码是空的');
      expect(r(''), '邀请码是空的');
      expect(r('   '), '邀请码是空的');
    });
    test('非数字 / 非正数', () {
      expect(r('abc'), '这个邀请码不对');
      expect(r('0'), '这个邀请码不对');
      expect(r('-5'), '这个邀请码不对');
    });
    test('★ 不能绑自己', () {
      expect(r('42', me: 42), '不能填自己的邀请码');
    });
    test('合法且不是自己 → 放行给后端', () {
      expect(r('42', me: 7), isNull);
      expect(r(' 42 ', me: 7), isNull, reason: '两端空白应被裁掉');
    });
    test('不知道自己的 memberId 时不误挡', () {
      expect(r('42'), isNull);
    });
  });

  group('★ 远端失败:不要编一个确定的原因', () {
    test('文案同时说出两种可能', () {
      const hint = InviterBinding.remoteFailureHint;
      expect(hint.contains('不存在'), isTrue);
      expect(hint.contains('已经绑过'), isTrue,
          reason: '后端 bindInviterIfAbsent 只在未绑定时生效,'
              '「已绑过」是最可能的处境,不说出来用户会一直试');
    });
    test('★ 必须明说不用重试', () {
      expect(InviterBinding.remoteFailureHint.contains('重试不会有变化'), isTrue,
          reason: '邀请人只能绑一次,说「请重试」是让用户做一件永远不会成功的事');
    });
    test('不出现「请重试」这类误导', () {
      expect(InviterBinding.remoteFailureHint.contains('请重试'), isFalse);
    });
  });
}
