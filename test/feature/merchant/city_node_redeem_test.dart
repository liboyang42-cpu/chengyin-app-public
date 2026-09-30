// 据点核销的结果文案。
//
// ★★★ 后端的拒绝话术**自带可执行信息**,一律原文透传(roam_api 注释写死了):
//   ·「玩家未到店打卡,或该券已核销」→ **那是保护不是故障**。
//     笼统换成「核销失败,请重试」会让商家一直重扫一张不可能成功的码;
//     换成「网络错误」更糟 —— 他会去查 wifi。
//   · 库存耗尽 → 后端整体回滚、补货后可重扫,那句话里带着下一步。
//   笼统换成「核销失败」会让商家完全不知道下一步该做什么。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/merchant/city_node_redeem_page.dart';
import '../../golden/golden_theme.dart';

Future<void> _pump(WidgetTester t,
    {required bool ok, required String message}) async {
  await t.binding.setSurfaceSize(const Size(390, 700));
  await t.pumpWidget(MaterialApp(
    // 商家域是浅色页。
    theme: merchantGoldenTheme(),
    home: Scaffold(
      body: CityNodeRedeemResult(ok: ok, message: message, onNext: () {}),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★★ 保护类拒绝:原文透传,不加「请重试」', (WidgetTester t) async {
    const String backend = '玩家未到店打卡,或该券已核销';
    await _pump(t, ok: false, message: backend);
    expect(find.text(backend), findsOneWidget);
    expect(find.textContaining('请重试'), findsNothing,
        reason: '这是保护不是故障 —— 让商家重扫一张不可能成功的码');
    expect(find.textContaining('网络'), findsNothing,
        reason: '说成网络问题他会去查 wifi');
  });

  testWidgets('★★ 库存耗尽:那句话带着下一步,不许改写',
      (WidgetTester t) async {
    const String backend = '该据点优惠券库存已用完,补货后可重新扫码';
    await _pump(t, ok: false, message: backend);
    expect(find.text(backend), findsOneWidget);
    expect(find.text('核销失败'), findsNothing,
        reason: '笼统换成「核销失败」商家完全不知道下一步该做什么');
  });

  testWidgets('★ 成功也用后端原话 —— 它会说清给玩家发了什么',
      (WidgetTester t) async {
    const String backend = '核销成功,已给玩家发放「静安咖啡 8 折券」';
    await _pump(t, ok: true, message: backend);
    expect(find.text(backend), findsOneWidget);
  });

  testWidgets('★ 成功/失败图标要分得开', (WidgetTester t) async {
    await _pump(t, ok: true, message: 'x');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await _pump(t, ok: false, message: 'x');
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
