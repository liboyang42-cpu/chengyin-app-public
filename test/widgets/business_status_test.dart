// 商家营业状态开关。
//
// ★ 此前 App **只写不读**:接了 `/business-status/update`,没接 `/business-status`。
//   于是两个按钮恒定长一个样、「开始营业」永远实心高亮 ——
//   营业中的商家看上去像还没开门,而且**没有任何办法确认自己上次设成了什么**。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';

import '../feature/merchant/merchant_access_fixtures.dart';

/// 工作台整页的根是 `/api/merchant/access/me`,不 override 会卡在错误屏 ——
/// 那时两个按钮根本渲不出来,测试会因为"页面根本没画"而假红。
///
/// 这里给的是**核销员**(有 `canWriteProfile`、不是店主):营业状态对全部
/// 激活身份常驻,店主的收入/待办/动态/项目区反而不在这张页上,不必全桩。
final List<dynamic> _access = <dynamic>[
  merchantAccessProvider.overrideWith(
    (ref) async => activeAccess(
      roleCode: 'MERCHANT_CHECKIN',
      permissions: const <String>[
        'merchant:basic:read',
        'merchant:profile:write',
      ],
    ),
  ),
].cast();

void main() {
  testWidgets('★ 营业中 → 右侧显示「营业中」,不是「开始营业」',
      (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <dynamic>[
        ..._access,
        // 工作台还依赖这两个 —— 不 override 会卡在错误态,
        // 那时两个按钮都渲不出来,测试会因为"页面根本没画"而假红。
        merchantDashboardProvider.overrideWith(
            (ref) async => MerchantDashboard.fromJson(<String, dynamic>{})),
        merchantTodoProvider.overrideWith(
            (ref) async => MerchantTodo.fromJson(<String, dynamic>{})),
        businessStatusProvider
            .overrideWith((ref) async => (open: true, text: '营业中')),
      ].cast(),
      child: MaterialApp(
        theme: AppTheme.merchantLight(),
        home: const Scaffold(body: MerchantHomePage()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('营业中'), findsWidgets);
    expect(find.text('开始营业'), findsNothing,
        reason: '已经在营业还显示「开始营业」,商家会以为自己没开门');
  });

  testWidgets('★ 已打烊 → 左侧显示「已打烊」', (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <dynamic>[
        ..._access,
        // 工作台还依赖这两个 —— 不 override 会卡在错误态,
        // 那时两个按钮都渲不出来,测试会因为"页面根本没画"而假红。
        merchantDashboardProvider.overrideWith(
            (ref) async => MerchantDashboard.fromJson(<String, dynamic>{})),
        merchantTodoProvider.overrideWith(
            (ref) async => MerchantTodo.fromJson(<String, dynamic>{})),
        businessStatusProvider
            .overrideWith((ref) async => (open: false, text: '已打烊')),
      ].cast(),
      child: MaterialApp(
        theme: AppTheme.merchantLight(),
        home: const Scaffold(body: MerchantHomePage()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已打烊'), findsWidgets);
    expect(find.text('打烊'), findsNothing);
  });

  testWidgets('★ 还没读回来时不写死默认态 —— 别替商家宣称一个我们不知道的状态',
      (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: <dynamic>[
        ..._access,
        // 工作台还依赖这两个 —— 不 override 会卡在错误态,
        // 那时两个按钮都渲不出来,测试会因为"页面根本没画"而假红。
        merchantDashboardProvider.overrideWith(
            (ref) async => MerchantDashboard.fromJson(<String, dynamic>{})),
        merchantTodoProvider.overrideWith(
            (ref) async => MerchantTodo.fromJson(<String, dynamic>{})),
        businessStatusProvider.overrideWith(
            (ref) async => throw Exception('网络失败')),
      ].cast(),
      child: MaterialApp(
        theme: AppTheme.merchantLight(),
        home: const Scaffold(body: MerchantHomePage()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 拿不到就两边都是可点的中性态,谁都不冒充"当前状态"
    expect(find.text('营业中'), findsNothing);
    expect(find.text('已打烊'), findsNothing);
  });
}
