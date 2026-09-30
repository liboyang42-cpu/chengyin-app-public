import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MyRegistration _order() => MyRegistration(
  id: 41,
  ownerType: 2,
  ownerId: 9,
  title: '静安探店日',
  registrationStatus: 2,
  payableAmount: 49.9,
);

void main() {
  testWidgets('刷新失败但已有订单:保留列表 + 顶部刷新失败条,不退回整屏错误', (WidgetTester tester) async {
    int calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith((ref) async {
            calls++;
            if (calls == 1) return <MyRegistration>[_order()];
            throw Exception('boom');
          }),
        ],
        child: const MaterialApp(home: OrdersPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('静安探店日'), findsOneWidget);

    ProviderScope.containerOf(
      tester.element(find.byType(OrdersPage)),
    ).invalidate(myOrdersProvider);
    await tester.pumpAndSettle();

    expect(
      find.text('静安探店日'),
      findsOneWidget,
      reason: '刷新失败不该丢掉已加载的订单(小程序同分支保留列表)',
    );
    expect(find.text('订单刷新失败'), findsOneWidget);
    expect(find.text('已加载的订单仍为你保留'), findsOneWidget);
    expect(find.text('订单暂时没有加载出来'), findsNothing);
  });

  testWidgets('刷新失败且一条都没有:仍是整屏错误 + 重试', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith((ref) async => throw Exception('boom')),
        ],
        child: const MaterialApp(home: OrdersPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('订单暂时没有加载出来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('订单刷新失败'), findsNothing);
  });
}
