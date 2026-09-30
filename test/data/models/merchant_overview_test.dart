// 商家结算概览的五个口径。**这是对账页,差一分就对不上。**
//
// 后端把它们称作「互不偷算」(MerchantSettlementOverview 类注释):
// 五个口径各自独立,前端**不许再做加减**,也不许把缺席当成 0。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/merchant_ledger.dart';

MerchantSettlementOverview _o(Map<String, dynamic> j) =>
    MerchantSettlementOverview.fromJson(j);

void main() {
  test('金额保持后端下发的字符串原样', () {
    // ★ 不转 double 再格式化 —— 那会引入精度与舍入差异,而这是对账口径。
    final o = _o(<String, dynamic>{
      'personalArrivedThisMonthGross': '12840.05',
      'personalExecutedAdjustmentsThisMonth': '-120.00',
      'personalArrivedThisMonthNet': '12720.05',
      'publicPayablePending': '3400.00',
      'adjustmentPending': '0.00',
      'adjustmentPendingCount': 2,
    });
    expect(o.personalArrivedThisMonthGross, '12840.05');
    expect(o.personalExecutedAdjustmentsThisMonth, '-120.00');
    expect(o.personalArrivedThisMonthNet, '12720.05');
  });

  test('★ 净额取后端的,不在前端算 gross + adjustments', () {
    // 后端算的就是 gross + adjustments(MerchantFinanceQueryService:65-68)。
    // 前端再算一遍,两边算法一旦漂移,页面上会出现自相矛盾的三个数。
    final o = _o(<String, dynamic>{
      'personalArrivedThisMonthGross': '100.00',
      'personalExecutedAdjustmentsThisMonth': '-30.00',
      // 后端下发的净额(哪怕看起来"不对",也以它为准 —— 口径解释权在服务端)
      'personalArrivedThisMonthNet': '70.00',
    });
    expect(o.personalArrivedThisMonthNet, '70.00');
  });

  test('★ 缺席是 null 不是 "0.00" —— 「没有这个口径」≠「这个口径是 0」',
      () {
    final o = _o(<String, dynamic>{'personalArrivedThisMonthGross': '10.00'});
    expect(o.publicPayablePending, isNull);
    expect(o.adjustmentPending, isNull);
    expect(o.personalArrivedThisMonthNet, isNull);
  });

  test('空字符串也算缺席 —— 别在界面上渲一个空的金额位', () {
    final o = _o(<String, dynamic>{'publicPayablePending': '   '});
    expect(o.publicPayablePending, isNull);
  });

  test('★ 有没有待执行调整看**笔数**不看金额', () {
    // 一笔 +100 和一笔 -100,金额合计是 0.00,但确实有两笔待处理。
    final o = _o(<String, dynamic>{
      'adjustmentPending': '0.00',
      'adjustmentPendingCount': 2,
    });
    expect(o.hasPendingAdjustment, isTrue,
        reason: '按金额判会把"正负抵消"误判成"没有待处理"');

    final none = _o(<String, dynamic>{'adjustmentPending': '0.00'});
    expect(none.hasPendingAdjustment, isFalse);
  });
}
