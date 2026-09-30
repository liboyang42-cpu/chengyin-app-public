// 契约测试:账号注销状态模型(对齐后端 DeregistrationStatusVO)。
//
// 后端 status 取值:NORMAL(无记录)/ ELIGIBLE(预检通过)/ BLOCKED(有阻断)
// / 其余为提交后的流水状态(冷静期中,带 executeAfter)。
//
// ★ 关键断言是 isPending 的判定:只有「拿得到 executeAfter 且不是三种预检态」
//   才算在途申请。若谁把它简化成「executeAfter != null」,BLOCKED 态一旦
//   同时带上时间就会被误判成冷静期中 ⇒ 页面给出撤销按钮而不是阻断原因。

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/deregistration.dart';

void main() {
  group('DeregistrationStatus.fromJson', () {
    test('NORMAL:从未申请过', () {
      final s = DeregistrationStatus.fromJson(<String, dynamic>{
        'status': 'NORMAL',
        'blockers': <dynamic>[],
      });
      expect(s.isNormal, isTrue);
      expect(s.isPending, isFalse);
      expect(s.blockers, isEmpty);
      expect(s.executeAfter, isNull);
    });

    test('ELIGIBLE:预检通过,可申请', () {
      final s = DeregistrationStatus.fromJson(<String, dynamic>{
        'status': 'ELIGIBLE',
        'blockers': <dynamic>[],
      });
      expect(s.isEligible, isTrue);
      expect(s.isBlocked, isFalse);
      expect(s.isPending, isFalse);
    });

    test('BLOCKED:阻断项原样保留,顺序不变', () {
      final s = DeregistrationStatus.fromJson(<String, dynamic>{
        'status': 'BLOCKED',
        'blockers': <dynamic>[
          '账户余额未处理',
          '存在处理中的提现，请等到账后再申请注销',
        ],
      });
      expect(s.isBlocked, isTrue);
      expect(s.blockers.length, 2);
      expect(s.blockers.first, '账户余额未处理');
      // 文案是服务端下发的资金域判据,客户端不得改写。
      expect(s.blockers[1], contains('提现'));
    });

    test('冷静期中:流水状态 + executeAfter ⇒ isPending', () {
      final s = DeregistrationStatus.fromJson(<String, dynamic>{
        'status': 'PENDING',
        'executeAfter': '2026-09-01 10:00:00',
        'blockers': <dynamic>[],
      });
      expect(s.isPending, isTrue);
      expect(s.executeAfter, '2026-09-01 10:00:00');
    });

    test('★ BLOCKED 即使带 executeAfter 也不能算冷静期中', () {
      // 否则页面会给出「撤销申请」而不是展示阻断原因,用户被卡在死路上。
      final s = DeregistrationStatus.fromJson(<String, dynamic>{
        'status': 'BLOCKED',
        'executeAfter': '2026-09-01 10:00:00',
        'blockers': <dynamic>['账户余额未处理'],
      });
      expect(s.isBlocked, isTrue);
      expect(s.isPending, isFalse, reason: 'BLOCKED 优先于 executeAfter');
    });

    test('边界:字段全缺 → 默认 NORMAL,不崩', () {
      final s = DeregistrationStatus.fromJson(<String, dynamic>{});
      expect(s.status, 'NORMAL');
      expect(s.blockers, isEmpty);
      expect(s.isPending, isFalse);
    });

    test('边界:blockers 元素非字符串时按 toString 收敛', () {
      final s = DeregistrationStatus.fromJson(<String, dynamic>{
        'status': 'BLOCKED',
        'blockers': <dynamic>[123, '余额未处理'],
      });
      expect(s.blockers, <String>['123', '余额未处理']);
    });
  });
}
