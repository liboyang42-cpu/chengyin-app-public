// 投诉页的三条硬约束。
//
// ★★ ① 选择源必须是 /api/coop/complaint/topics。
//   拿「我参与的」列表顶替会同时踩两个真库实测过的坑:
//   那条链路砍掉结束超 7 天的主题(而投诉没有时间窗)、
//   且只对 owner_type=1 挂主题(③ 自由探索玩家整条选不到)。
//
// ★★ ② 表单只有主题 + 说明两项。后端只信任这两个,
//   过错方/垫付额/过错比例/扣划额由客服后台设。
//   放一个"选择过错方"或"填赔付金额",用户填完会以为自己已经索赔了。
//
// ★ ③ 成功文案说「已提交,客服会跟进」,不说「已解决」——
//   后端 status=0 只叫受理,后面还有垫付/追偿/关闭三档。

import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

void main() {
  final String code = codeOf('lib/feature/coop/complaint_page.dart');

  test('★★ 选择源是 complaint/topics', () {
    expect(code.contains('complainableTopics()'), isTrue);
    // 不许出现从订单/参与列表取主题的写法。
    for (final String wrong in <String>[
      'myRegistrations',
      'registration/list',
      'ordersProvider',
    ]) {
      expect(
        code.contains(wrong),
        isFalse,
        reason: '$wrong 与受理口判据不同 —— 必然出现"玩家选不到、后端却允许"',
      );
    }
  });

  test('★★ 表单不许有过错方 / 金额一类输入', () {
    for (final String forbidden in <String>[
      'faultParty',
      'advanceAmount',
      'faultRatio',
      'deductAmount',
      '赔付金额',
      '过错方',
    ]) {
      expect(
        code.contains(forbidden),
        isFalse,
        reason: '$forbidden 后端一律不取 —— 填了也不生效,而用户以为索赔了',
      );
    }
  });

  test('★ 提交只发 topicId + reason(后端就这两个字段)', () {
    expect(code.contains('topicId: _topicId!'), isTrue);
    // 2026-08-20:reason 现在是**拼好的**(正文 + 可选联系方式),
    // 因为后端没有单独的 contact 字段 —— 小程序也是这么拼的。
    // 关键仍然是「只发这两个」,别多发一个后端不认的参数。
    expect(code.contains('reason: _composedReason()'), isTrue);
    expect(
      RegExp(r'contact\s*:').hasMatch(code),
      isFalse,
      reason: '后端没有 contact 字段,多发一个等于用户白填',
    );
  });

  test('★ 成功文案不替客服承诺结果', () {
    expect(code.contains('投诉已提交'), isTrue, reason: '保持小程序提交成功回执原文');
    for (final String overclaim in <String>['已解决', '已赔付', '已受理并赔付']) {
      expect(
        code.contains(overclaim),
        isFalse,
        reason: '后端 status=0 只叫受理,后面还有垫付/追偿/关闭三档',
      );
    }
  });

  test('★ 两种正常拒绝靠原文说清,不渲成「提交失败,请重试」', () {
    expect(code.contains("replaceFirst('Exception: ', '')"), isTrue);
    expect(
      code.contains('提交失败,请重试'),
      isFalse,
      reason:
          '「仅本主题已支付参与者可投诉」「你对该主题已有处理中的投诉」'
          '都是正常态,渲成重试会让人一直点',
    );
  });

  test('★ 空态说清判据 —— 否则玩家以为是 bug', () {
    expect(code.contains('已报名并支付'), isTrue);
    expect(code.contains('报名并支付后可在这里发起'), isTrue);
  });

  test('★ 入口按**主题**发起,不做「这一单投诉」', () {
    final String orders = codeOf('lib/feature/orders/orders_page.dart');
    expect(orders.contains("push('/complaint')"), isTrue);
    // 按单发起会让人以为投诉挂在这一单上,而后端是按主题去重的。
    expect(orders.contains('/complaint/'), isFalse);
  });
}
