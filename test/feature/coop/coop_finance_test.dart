import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/coop_finance.dart';

/// 合作结算。★★ 资金显示,「没有值」与「值是 0」必须分开。
void main() {
  CoopFinanceRow r(Map<String, dynamic> m) =>
      CoopFinanceRow.fromJson(<String, dynamic>{'topicName': 'X', ...m});

  group('★ 我的分润:未结算 ≠ 赚了 0 元', () {
    test('myIncome 为 null → 待结算', () {
      expect(r(<String, dynamic>{}).myIncomeDisplay, '待结算');
      expect(r(<String, dynamic>{'myIncome': null}).myIncomeDisplay, '待结算');
    });
    test('★ 确实是 0 → 显示 ¥0.00,这是真实的 0', () {
      expect(r(<String, dynamic>{'myIncome': '0.00'}).myIncomeDisplay, '¥0.00');
    });
    test('有金额 → 原样两位小数', () {
      expect(r(<String, dynamic>{'myIncome': '128.5'}).myIncomeDisplay, '¥128.50');
    });
  });

  group('★ 没金额时不谈到账', () {
    test('未结算 → 不显示到账提示', () {
      expect(r(<String, dynamic>{'myIncomeArrived': true}).myIncomeHint, isNull,
          reason: '没有金额时说「已到账」毫无意义,还会让人以为钱已经进来了');
    });
    test('有金额且已到账', () {
      expect(
          r(<String, dynamic>{'myIncome': '10', 'myIncomeArrived': true})
              .myIncomeHint,
          '已到账');
    });
    test('有金额但未到账 → 说清在途', () {
      expect(
          r(<String, dynamic>{'myIncome': '10', 'myIncomeArrived': false})
              .myIncomeHint,
          '结算完成,等待打款');
    });
  });

  group('承接方到账', () {
    test('实际到账日优先于预告日', () {
      final row = r(<String, dynamic>{
        'merchantPayableTime': '2026-08-20',
        'merchantPayoutTime': '2026-08-18',
      });
      expect(row.merchantPayoutHint, '承接方已于 2026-08-18 到账');
    });
    test('只有预告日 → 说"预计"', () {
      expect(r(<String, dynamic>{'merchantPayableTime': '2026-08-20'})
          .merchantPayoutHint, '承接方预计 2026-08-20 到账');
    });
    test('都没有 → 整行不显示,不编一个日期', () {
      expect(r(<String, dynamic>{}).merchantPayoutHint, isNull);
    });
    test('空串等同没有', () {
      expect(r(<String, dynamic>{'merchantPayoutTime': '', 'merchantPayableTime': ''})
          .merchantPayoutHint, isNull);
    });
  });

  test('缺主题名兜底', () {
    expect(CoopFinanceRow.fromJson(<String, dynamic>{}).topicName, '未命名主题');
  });
}
