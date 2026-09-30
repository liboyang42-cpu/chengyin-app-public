// 金额没算出来时,不许在付款按钮旁边摆一个「实付 ¥0.00」。
//
// ★★ `(q.payAmount ?? 0).toStringAsFixed(2)` —— 报价对象拿到了、
//   但后端没给 payAmount(模型里它是可空的)时,页面显示 ¥0.00,
//   而提交按钮当时只判 `_quote == null`,是**开着的**。
//   用户看到「实付 ¥0.00」按下去,要么被后端拒,要么按真实金额扣。
//
// ★ 这是「闸放错层」的又一例:闸判的是**报价对象存不存在**,
//   而真正该判的是**金额算没算出来**。对象在、金额空 —— 闸恒绿。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/source_text.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';

Future<void> _pump(WidgetTester t, RegistrationQuote? q,
    {bool loading = false}) async {
  await t.binding.setSurfaceSize(const Size(390, 800));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: FeeBreakdown(
          quote: q,
          loading: loading,
          error: null,
          usePoints: false,
          onRetry: () {},
          onTogglePoints: (_) {},
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★ payAmount 为空不许显示 ¥0.00', (WidgetTester t) async {
    await _pump(t, const RegistrationQuote(quoteSign: 'sig'));
    expect(find.text('¥0.00'), findsNothing,
        reason: '金额没拿到却显示 ¥0.00 —— 用户会以为这单免费');
    expect(find.text('金额没算出来'), findsOneWidget);
  });

  testWidgets('★ 真的是 0 元就照实显示 ¥0.00', (WidgetTester t) async {
    await _pump(t, const RegistrationQuote(payAmount: 0, quoteSign: 'sig'));
    expect(find.text('¥0.00'), findsOneWidget,
        reason: '免单是真事实,不能被上一条一起吞掉');
  });

  testWidgets('★ 正常金额照旧', (WidgetTester t) async {
    await _pump(t, const RegistrationQuote(payAmount: 149, quoteSign: 'sig'));
    expect(find.text('¥149.00'), findsOneWidget);
  });

  test('★★ 放行支付的闸,判据要和显示金额的判据一致', () {
    // ⚠️ 这是**静态**判据 —— 真判据是整页渲染,但那要造一整套活动/报价替身。
    //   它只钉住一件事:提交钮的 onPressed 不许只判「有没有 quote 对象」。
    //   对象在、payAmount 为空时闸会恒绿,而那正是上面三条测的那个态。
    //
    //   2026-09-17 接线换了位置:闸从按钮自己的 onPressed 提到了上层传进去的
    //   `quoteReady`(结算页底部条与费用明细共用同一份判据),锚点随之更新 ——
    //   钉的东西没变:闸判的是**金额**,不是报价对象存不存在。
    final String code =
        codeOf('lib/feature/activity/activity_detail_page.dart');
    final int at = code.indexOf('quoteReady:');
    expect(at, greaterThan(0), reason: '找不到提交闸的接线 —— 断言写法失效了');
    final String seg = code.substring(at, (at + 160).clamp(0, code.length));
    expect(seg.contains('_quote?.payAmount != null'), isTrue,
        reason: '提交钮的闸退回了「_quote == null」——'
            '报价对象在但金额没算出来时它会放行,用户按着「实付」就付了');
  });
}
