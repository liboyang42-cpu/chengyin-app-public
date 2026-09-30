import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/merchant_ledger.dart';

/// 商家台账。**资金显示页,前端一个金额都不许算。**
void main() {
  MerchantRedemption row({String? amount, String state = 'SETTLED', String? refund}) =>
      MerchantRedemption.fromJson(<String, dynamic>{
        'recordKey': 'k',
        'settlementAmount': amount,
        'displayState': state,
        'refundState': refund,
      });

  group('金额四态 —— 对齐 ledger/index.js:107-109', () {
    test('确认不产生现金 → 破折号', () {
      expect(row(amount: null, state: 'NO_CASH_SETTLEMENT').amountDisplay, '—');
      expect(row(amount: '0.00', state: 'NO_CASH_SETTLEMENT').amountDisplay, '—');
    });
    test('★ 金额尚未成立 → 待定,不是 ¥0.00', () {
      expect(row(amount: null, state: 'PENDING_SETTLEMENT').amountDisplay, '待定');
      expect(row(amount: '0.00', state: 'PENDING_SETTLEMENT').amountDisplay, '待定');
    });
    test('有金额 → 正数带加号', () {
      expect(row(amount: '38.50').amountDisplay, '+¥38.50');
    });
    test('负数 → 符号跟在 ¥ 后', () {
      expect(row(amount: '-10.00').amountDisplay, '¥-10.00');
    });
  });

  group('状态文案', () {
    test('不结现金时把原因说出来 —— 只显示「—」商家会以为是 bug', () {
      final r = MerchantRedemption.fromJson(<String, dynamic>{
        'recordKey': 'k',
        'displayState': 'NO_CASH_SETTLEMENT',
        'noCashReason': '该章节为免费体验',
      });
      expect(r.stateText, '该章节为免费体验');
    });
    test('没给原因时兜底,不显示空白', () {
      expect(row(state: 'NO_CASH_SETTLEMENT').stateText, '不结现金');
    });
    test('三态与后端一一对应,不发明中间态', () {
      expect(row(state: 'PENDING_SETTLEMENT').stateText, '待结算');
      expect(row(state: 'SETTLED').stateText, '已结算');
    });
    test('未知态原样透出,不吞成空白', () {
      expect(row(state: 'WHATEVER').stateText, 'WHATEVER');
      expect(row(state: '').stateText, '—');
    });
  });

  group('退款标记', () {
    test('退款中必须能识别 —— 不标商家会把已退的算成收入', () {
      expect(row(refund: 'REFUNDING').refunding, isTrue);
    });
    test('NONE / 空 / null 都不算退款中', () {
      expect(row(refund: 'NONE').refunding, isFalse);
      expect(row(refund: '').refunding, isFalse);
      expect(row(refund: null).refunding, isFalse);
    });
  });

  group('汇总条', () {
    test('三个值全部用后端下发的,缺席显破折号', () {
      final s = MerchantRedemptionSummary.fromJson(<String, dynamic>{
        'count': 12,
        'pendingAmount': '340.00',
      });
      expect(s.count, 12);
      expect(s.pendingDisplay, '¥340.00');
      expect(s.arrivedDisplay, '—', reason: '后端没下发就是没下发,不冒充 ¥0.00');
    });
  });

  test('★ 页面里不许出现对金额的算术 —— 汇总必须由服务端算', () {
    final src = File('lib/feature/merchant/merchant_ledger_page.dart')
        .readAsStringSync();
    // 后端注释原话:「这份聚合必须在服务端算:前端只拿得到当前页 rows,
    // 对它求和分页后必错,而且错得静默。」
    //
    // ⚠️ 模式必须精确:第一版写了裸的 '.sum',结果匹配到 `page.summary` 里的
    //    `.sum` 而误报。子串匹配在这类门禁里极易假阳性 —— 用词边界锁住。
    final banned = <RegExp, String>{
      RegExp(r'\.fold\('): 'fold(',
      RegExp(r'\.reduce\('): 'reduce(',
      RegExp(r'\bsum\b'): '裸的 sum 变量/方法',
      RegExp(r'double\.parse'): 'double.parse',
    };
    banned.forEach((RegExp re, String label) {
      expect(re.hasMatch(src), isFalse,
          reason: '台账页出现了 $label —— 前端对分页数据求和必错,而且错得静默');
    });
  });
}
