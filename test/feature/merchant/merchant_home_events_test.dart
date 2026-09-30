// 工作台「最新动态」区(`/api/merchant/events`)。
//
// ★★ time 字段后端已格式化好(MM-dd HH:mm),这里只锁"原样展示",
//   不允许再解析/再格式化——那串没有年份和时区,跨年就会算错。
// ★ 空列表 = 当前没有动态,整块不显示,不留一个空卡片占位。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/merchant_access_provider.dart';
import 'package:chengyin_app/data/models/merchant_dashboard.dart';
import 'package:chengyin_app/feature/merchant/merchant_home_page.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;
import 'merchant_access_fixtures.dart' show ownerAccess;

Widget _app(List<dynamic> overrides) {
  return ProviderScope(
    overrides: <dynamic>[
      // 工作台根现在挂在 access/me 上(非店主连请求都不发),先给它店主身份。
      merchantAccessProvider.overrideWith((ref) async => ownerAccess()),
      merchantDashboardProvider.overrideWith(
        (ref) async => MerchantDashboard.fromJson(<String, dynamic>{}),
      ),
      businessStatusProvider.overrideWith(
        (ref) async => (open: true, text: '营业中'),
      ),
      merchantTodoProvider.overrideWith(
        (ref) async => MerchantTodo.fromJson(<String, dynamic>{}),
      ),
      ...overrides,
    ].cast(),
    child: MaterialApp(
      theme: merchantGoldenTheme(),
      home: const MerchantHomePage(),
    ),
  );
}

void main() {
  testWidgets('★★ 动态原样展示 content + time,不重新解析', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantEventsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'income',
              'label': '收入到账',
              'content': '主题分润 +¥128.00',
              'time': '08-19 14:30',
            },
            <String, dynamic>{
              'type': 'verify',
              'label': '核销',
              'content': '完成一笔到店核销',
              'time': '08-18 09:12',
            },
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('最新动态'), findsOneWidget);
    expect(find.text('主题分润 +¥128.00'), findsOneWidget);
    expect(find.text('08-19 14:30'), findsOneWidget);
    expect(find.text('完成一笔到店核销'), findsOneWidget);
  });

  testWidgets('空动态 → 整块不显示', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantEventsProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[],
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('最新动态'), findsNothing);
  });

  // ★ 加载失败与真源同口径**静默消失**:小程序 `pages/merchant/index/index.js`
  //   的 loadEvents 只有 success 回调、`hideLoading: true`,失败时 notifications
  //   保持 [],wxml `wx:if="{{notifications.length}}"` 整块不渲,页内无错误态。
  //   登记于 REPORT-sim-merchant-2 P2-b(判不修);这条钉子防止将来有人
  //   「好心」加错误横幅把行为改得偏离真源。
  testWidgets('动态加载失败 → 与真源同口径静默消失,不渲错误横幅', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    await tester.pumpWidget(
      _app(<dynamic>[
        merchantEventsProvider.overrideWith(
          (ref) async => throw Exception('network down'),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('最新动态'), findsNothing);
    expect(find.textContaining('加载失败'), findsNothing);
  });
}
