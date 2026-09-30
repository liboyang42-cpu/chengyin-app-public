// 收益明细:金额与方向的表。三条都来自小程序那份实现踩过的坑。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/balance_detail.dart';
import 'package:chengyin_app/feature/account/income_detail_page.dart';

BalanceDetail _d({String? amount, int? changeType}) => BalanceDetail.fromJson(
  <String, dynamic>{'id': 1, 'changeBalance': amount, 'changeType': changeType},
);

void main() {
  test('★ 符号看 changeType,不看金额里有没有负号', () {
    // 后端存绝对值。自己判负号 ⇒ 所有支出都显示成收入。
    expect(incomeAmountText(_d(amount: '128.00', changeType: 1)), '+¥128.00');
    expect(incomeAmountText(_d(amount: '128.00', changeType: 2)), '−¥128.00');
    // 后端偶尔带负号(negate 的原值)时也不能变成 −¥-128.00。
    expect(incomeAmountText(_d(amount: '-128.00', changeType: 2)), '−¥128.00');
  });

  test('★★ 缺金额返回 null(由页面渲成中性的「—」),不能是 0', () {
    // 「没有数」≠「零元」。兜成 ¥0.00 是在替后端编一个事实。
    expect(incomeAmountText(_d(amount: null, changeType: 1)), isNull);
    expect(incomeAmountText(_d(amount: '', changeType: 1)), isNull);
    expect(incomeAmountText(_d(amount: '   ', changeType: 1)), isNull);
  });

  test('★ 方向必须有文字,不能只靠颜色(WCAG 1.4.1)', () {
    expect(incomeDirectionText(_d(amount: '1', changeType: 1)), '收入');
    expect(incomeDirectionText(_d(amount: '1', changeType: 2)), '支出');
    // 且金额文本里也带着符号 —— 两处冗余是有意的。
    expect(
      incomeAmountText(_d(amount: '1', changeType: 2))!.startsWith('−'),
      isTrue,
    );
  });

  test('★ 日期 = 真源 formatDate:今天/昨天/M月D日,不带秒', () {
    // scene-asset-income-detail/index.js:12-19。流水页看「哪天」,秒无信息量。
    final DateTime now = DateTime(2026, 9, 19, 13, 0);
    expect(incomeDateText('2026-09-19 20:31:00', now: now), '今天');
    expect(incomeDateText('2026-09-18 00:00:00', now: now), '昨天');
    expect(incomeDateText('2026-08-05 11:02:00', now: now), '8月5日');
    expect(incomeDateText(null, now: now), isNull);
    expect(incomeDateText('   ', now: now), isNull);
    // 解析不了的日期原样透传 —— 不编一个「—」冒充没有,也不藏。
    expect(incomeDateText('2026年9月某天', now: now), '2026年9月某天');
  });

  test('★ changeType 是方向不是状态 —— 模型里不该有「已到账/处理中」', () {
    // 库里没有状态字段。渲染成状态等于每条支出恒显示「处理中」。
    final String src = _source();
    expect(src.contains('已到账'), isFalse, reason: '没有这个字段,写出来就是编的');
    expect(src.contains('处理中'), isFalse);
  });

  test('俱乐部档不走本接口 —— wire 为空,选中要跳合作财务页', () {
    expect(IncomeEventFilter.club.wire, isEmpty);
    expect(
      _source().contains("/coop-finance"),
      isTrue,
      reason: '否则选中俱乐部会用空 eventType 重查一遍全部,看着像筛选坏了',
    );
  });
}

String _source() =>
    // ignore: avoid_slow_async_io
    _read('lib/feature/account/income_detail_page.dart');

String _read(String p) {
  final f = File(p);
  return f.readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), '');
}
