import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/feature/merchant/merchant_money.dart';

/// 商家资金域金额展示。
///
/// ★ 核心一条:**「没有这个字段」和「金额是 0」必须分得开**。
///   用 `?? 0` 糊掉,会把「未结算」渲染成「收入 0 元」—— 商家会以为这单白干了。
///   这与提现页「余额没取到 ≠ 余额是 0」是同一条纪律。
void main() {
  group('cny 规范化', () {
    test('数字形态都收,统一两位小数', () {
      expect(cny(12), '12.00');
      expect(cny(12.5), '12.50');
      expect(cny('12.345'), '12.35');
      expect(cny('0'), '0.00');
    });

    test('字段缺席 → null,不是 0', () {
      expect(cny(null), isNull);
      expect(cny(''), isNull);
      expect(cny('  '), isNull);
      expect(cny('abc'), isNull);
    });

    test('非有限数不当 0 放行', () {
      expect(cny(double.infinity), isNull);
      expect(cny(double.nan), isNull);
    });
  });

  group('isZeroCny:null 不算零', () {
    test('明确的 0 才算零', () {
      expect(isZeroCny(0), isTrue);
      expect(isZeroCny('0.00'), isTrue);
      expect(isZeroCny('-0.00'), isTrue);
    });
    test('★ 缺席不算零 —— 这是与 ?? 0 的关键区别', () {
      expect(isZeroCny(null), isFalse);
      expect(isZeroCny(''), isFalse);
    });
    test('非零就是非零', () {
      expect(isZeroCny(0.01), isFalse);
      expect(isZeroCny(-1), isFalse);
    });
  });

  group('核销行金额', () {
    // 对齐小程序 pages/merchant/ledger/index.js:107-109 ——
    // 「两种未成立要分开:明确不产生现金 → 破折号;金额尚未成立 → 待定」
    test('不产生现金 → 破折号', () {
      expect(redemptionAmountDisplay(null, 'NO_CASH_SETTLEMENT'), '—');
      expect(redemptionAmountDisplay(0, 'NO_CASH_SETTLEMENT'), '—');
    });
    test('尚未结算 → 待定(不是 ¥0.00)', () {
      expect(redemptionAmountDisplay(null, 'PENDING'), '待定');
      expect(redemptionAmountDisplay(0, 'PENDING'), '待定');
    });
    test('有金额 → 正数带加号', () {
      expect(redemptionAmountDisplay(38.5, 'SETTLED'), '+¥38.50');
    });
    test('负数符号跟在 ¥ 后', () {
      expect(redemptionAmountDisplay(-10, 'SETTLED'), '¥-10.00');
    });
  });

  group('其余三种展示', () {
    test('收入明细行带符号', () {
      expect(signedAmountDisplay(20), '+¥20.00');
      expect(signedAmountDisplay(-20), '¥-20.00');
      expect(signedAmountDisplay(null), '—');
    });
    test('对公批次不带符号', () {
      expect(batchAmountDisplay(1000), '¥1000.00');
      expect(batchAmountDisplay(null), '—');
    });
    test('概要数字缺席显破折号,不冒充 0', () {
      expect(summaryMoney(88), '¥88.00');
      expect(summaryMoney(null), '—');
      expect(summaryMoney(0), '¥0.00', reason: '明确的 0 要如实显示 ¥0.00');
    });
  });
}
