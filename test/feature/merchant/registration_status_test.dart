// 报名卡上的两个状态字段。
//
// ★★ `status` 与 `auditStatus` 管的不是一件事,合并会**同时错两处**:
//   · 能不能改 看 status(0待审 / 2驳回);
//   · 能不能取消 看 auditStatus(1=已中标 ⇒ 一律不能取消,闸在 service)。
//
//   合成一个的话:已中标的会给出取消按钮(点了必撞后端的拒绝),
//   或者被驳回的给不出修改按钮 —— 而"被驳回还能改"正是 update 接口存在的理由
//   (后端原注释:「被驳回的商家想补一张现场图,只能取消重报,记录丢失、重新排队」)。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_apply.dart';
import '../../support/source_text.dart';

TopicRegistration reg({int? status, int? auditStatus, String? reason}) =>
    TopicRegistration.fromJson(<String, dynamic>{
      'id': 1,
      'topicId': 2,
      if (status != null) 'status': status,
      if (auditStatus != null) 'auditStatus': auditStatus,
      if (reason != null) 'reason': reason,
    });

void main() {
  group('★★ 两个字段各管各的', () {
    test('已中标(auditStatus=1):不能取消,即使 status=1 已通过', () {
      final r = reg(status: 1, auditStatus: 1);
      expect(r.isWon, isTrue);
      expect(r.canCancel, isFalse,
          reason: '给了取消按钮 = 点下去必撞 service 的闸');
    });

    test('★ 已驳回(status=2):能改,而且没中标所以也能取消', () {
      final r = reg(status: 2);
      expect(r.isRejected, isTrue);
      expect(r.canEdit, isTrue,
          reason: '被驳回还能改正是 update 接口存在的理由 —— '
              '不给修改入口就退回到"取消重报、重新排队"');
      expect(r.canCancel, isTrue);
    });

    test('待审核(status=0):能改能取消', () {
      final r = reg(status: 0);
      expect(r.canEdit, isTrue);
      expect(r.canCancel, isTrue);
    });

    test('已通过但没中标(status=1, auditStatus 缺):不能改,但能取消', () {
      final r = reg(status: 1);
      expect(r.canEdit, isFalse);
      expect(r.canCancel, isTrue);
    });
  });

  group('★ 缺席不许兜 0', () {
    test('status 缺席保持 null —— 兜 0 会变成"待审核"这个真实状态', () {
      final r = reg();
      expect(r.status, isNull,
          reason: '把"没拿到"说成"待审核",界面就会给出它其实没有的操作');
      expect(r.isPending, isFalse);
      expect(r.canEdit, isFalse);
    });

    test('auditStatus 缺席保持 null', () {
      expect(reg(status: 0).auditStatus, isNull);
    });
  });

  group('页面', () {
    final String code =
        codeOf('lib/feature/merchant/merchant_registrations_page.dart');

    test('★ 取消按钮受 canCancel 管,修改按钮受 canEdit 管', () {
      expect(code.contains('if (r.canCancel)'), isTrue);
      expect(code.contains('if (r.canEdit)'), isTrue);
    });

    test('★★ 驳回原因必须显示 —— 没有它商家只知道"没过",不知道改什么', () {
      expect(code.contains('驳回原因:'), isTrue);
      // 后端没填原因时说实话,别编一句。
      expect(code.contains('后台没填原因'), isTrue);
    });

    test('★ 状态拿不到时说「状态未知」,不默认成「审核中」', () {
      expect(code.contains('状态未知'), isTrue);
      expect(
        code.contains("default:\n        return '审核中';"),
        isFalse,
        reason: '默认成审核中 = 把"不知道"说成一个确定状态,界面会给出错的操作',
      );
    });

    test('★★ 「修改」不再是假入口 —— 跳真页面,不弹提示', () {
      // 2026-08-19 之前这里是「弹一句『表单还在做』」的假入口,理由是
      // 「没有完整表单,接了会拿半截数据覆盖后端」。核到服务端后前提只对一半:
      //   · 覆盖成空不会发生 —— 白名单只有九个字段,mapper 逐字段增量更新;
      //   · 真正的实害是「表单缺一项 = 那一项永远改不了」。
      // 现在给的是按那份白名单做的完整表单(merchant_registration_edit_page)。
      expect(code.contains('报名修改表单还在做'), isFalse,
          reason: '假入口已经换成真页面,提示文案不该留着');
      expect(code.contains("/merchant/registration/"), isTrue,
          reason: '「修改」得真跳到编辑页');
      // ⚠️ 调用 update 的地方是编辑页,不是这一页 —— 列表页只负责跳转。
      expect(code.contains('updateTopicRegistration'), isFalse,
          reason: '列表页直接调 update 就绕过了那张完整表单');
    });

    test('★ 编辑页真的调了 update,而且带上了 id', () {
      final String edit =
          codeOf('lib/feature/merchant/merchant_registration_edit_page.dart');
      expect(edit.contains('updateTopicRegistration'), isTrue);
      expect(edit.contains("'id': widget.detail.id"), isTrue,
          reason: '不带 id 的话服务端会回「缺少报名 id」');
    });
  });
}
