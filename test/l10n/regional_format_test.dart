import 'package:intl/date_symbol_data_local.dart';
import 'package:chengyin_app/l10n/regional_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact activity date localizes calendar order without converting UTC fields', () async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('zh');
    final instant = DateTime.utc(2026, 9, 30, 14, 5);
    final english = formatCompactActivityDate(instant, 'en');
    final chinese = formatCompactActivityDate(instant, 'zh');
    expect(english, contains('Sep'));
    expect(chinese, contains('9月30日'));
    expect(english, contains('14:05'));
    expect(chinese, contains('14:05'));
  });

  test('English does not convert a CNY amount to USD', () {
    final amount = formatMoney(amount: 1234.5, currencyCode: 'CNY', locale: 'en_US');
    expect(amount, contains('CNY'));
    expect(amount, contains('1,234.50'));
    expect(amount, isNot(contains('USD')));
  });

  test('Chinese can display a server-declared USD amount including zero', () {
    final amount = formatMoney(amount: 0, currencyCode: 'USD', locale: 'zh_CN');
    expect(amount, contains('USD'));
    expect(amount, contains('0.00'));
  });

  test('missing currency or non-finite value cannot fabricate a price', () {
    expect(() => formatMoney(amount: 12, currencyCode: '', locale: 'en'), throwsArgumentError);
    expect(() => formatMoney(amount: double.nan, currencyCode: 'USD', locale: 'en'), throwsArgumentError);
  });
}
