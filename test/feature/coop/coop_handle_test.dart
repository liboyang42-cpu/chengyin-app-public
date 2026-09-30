// 合作邀约的三个动作:接受 / 拒绝 / 取消。
//
// ★★ 后端 ApiCoopController.handle 写死:
//   「接受/拒绝须**受邀方**本人;取消须**发起方**本人」。
//   1/2 与 3 是**两个角色**的动作,不是同一件事的两份实现 ——
//   按「消费方去重」把它们合掉会同时砍掉一个角色的能力。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';

void main() {
  group('★★ 谁能做什么', () {
    test('待确认(0):只有受邀方能接受/拒绝', () {
      for (final CoopHandleAction a
          in <CoopHandleAction>[CoopHandleAction.accept, CoopHandleAction.reject]) {
        expect(a.allowed(inviteStatus: 0, isFrom: false, isTo: true), isTrue);
        expect(a.allowed(inviteStatus: 0, isFrom: true, isTo: false), isFalse,
            reason: '发起方不能替对方接受自己的邀约');
      }
    });

    test('待确认(0):只有发起方能取消(撤回)', () {
      expect(CoopHandleAction.cancel.allowed(inviteStatus: 0, isFrom: true, isTo: false),
          isTrue);
      expect(CoopHandleAction.cancel.allowed(inviteStatus: 0, isFrom: false, isTo: true),
          isFalse);
    });

    test('已接受(1):双方都能取消,但谁都不能再接受一次', () {
      expect(CoopHandleAction.cancel.allowed(inviteStatus: 1, isFrom: true, isTo: false),
          isTrue);
      expect(CoopHandleAction.cancel.allowed(inviteStatus: 1, isFrom: false, isTo: true),
          isTrue);
      expect(CoopHandleAction.accept.allowed(inviteStatus: 1, isFrom: false, isTo: true),
          isFalse);
    });

    test('已拒绝/已取消等终态:一个动作都不给', () {
      for (final int st in <int>[2, 3, 4, 5]) {
        expect(
            CoopHandleAction.availableFor(inviteStatus: st, isFrom: true, isTo: true),
            isEmpty);
      }
    });
  });

  group('★ 只有「取消一个已接受的合作」要填理由', () {
    test('已接受的取消要理由', () {
      expect(CoopHandleAction.needsReason(CoopHandleAction.cancel, 1), isTrue);
    });
    test('撤回一个还没人理的邀请不要理由', () {
      // 对所有取消都强制填,会让这件小事变得很重。
      expect(CoopHandleAction.needsReason(CoopHandleAction.cancel, 0), isFalse);
    });
    test('接受/拒绝都不要理由', () {
      expect(CoopHandleAction.needsReason(CoopHandleAction.accept, 0), isFalse);
      expect(CoopHandleAction.needsReason(CoopHandleAction.reject, 0), isFalse);
    });
  });

  test('status 是**目标状态**不是动作码', () {
    expect(CoopHandleAction.accept.wire, 1);
    expect(CoopHandleAction.reject.wire, 2);
    expect(CoopHandleAction.cancel.wire, 3);
  });
}
