import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('从我的预览进订单页时自动打开对应订单详情 Sheet', (WidgetTester tester) async {
    final order = MyRegistration(
      id: 31,
      ownerType: 2,
      ownerId: 9,
      title: '城市夜游',
      registrationStatus: 2,
      payableAmount: 19.9,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith((ref) async => <MyRegistration>[order]),
          orderDetailProvider(31).overrideWith(
            (ref) async => RegistrationDetail.fromJson(<String, dynamic>{
              'id': 31,
              'ownerType': 2,
              'ownerId': 9,
              'registrationStatus': 2,
              'paymentStatus': 2,
              'payableAmount': 19.9,
              'refundInfo': <String, dynamic>{'refundable': true},
              'cmsActivity': <String, dynamic>{'name': '城市夜游'},
            }),
          ),
          orderCompletionProvider(31).overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          navigatorObservers: <NavigatorObserver>[_RouteObserver()],
          home: const OrdersPage(initialDetailId: 31),
        ),
      ),
    );
    // 原生 Cupertino Sheet / Liquid Glass 允许持续的系统动画，
    // 这里验收的是详情在有界时间内出现，不要求整棵树「零动画」。
    await _pumpUntilFound(tester, find.byKey(const Key('order-detail-sheet')));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byKey(const Key('order-detail-sheet')), findsOneWidget);
    expect(find.text('城市夜游'), findsWidgets);
    expect(find.text('¥19.90'), findsWidgets);

    final Finder cancel = find.byKey(const Key('order-detail-cancel')).last;
    await tester.scrollUntilVisible(
      cancel,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('order-detail-sheet')).last,
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(cancel);
    await _pumpUntilFound(tester, find.text('取消报名并退款'));
    expect(find.text('取消报名并退款'), findsOneWidget);
    expect(find.textContaining('退款将原路退回微信'), findsOneWidget);
    expect(find.text('取消并退款'), findsWidgets);
    expect(find.text('再想想'), findsOneWidget);
  });

  testWidgets('连点订单只打开一个官方 Cupertino Sheet', (WidgetTester tester) async {
    final _RouteObserver observer = _RouteObserver();
    final MyRegistration order = MyRegistration(
      id: 31,
      ownerType: 2,
      ownerId: 9,
      title: '城市夜游',
      registrationStatus: 2,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith((_) async => <MyRegistration>[order]),
          orderDetailProvider(31).overrideWith(
            (_) async => RegistrationDetail.fromJson(<String, dynamic>{
              'id': 31,
              'ownerType': 2,
              'ownerId': 9,
              'registrationStatus': 2,
              'cmsActivity': <String, dynamic>{'name': '城市夜游'},
            }),
          ),
          orderCompletionProvider(31).overrideWith((_) async => null),
        ],
        child: MaterialApp(
          navigatorObservers: <NavigatorObserver>[observer],
          home: const OrdersPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final CupertinoButton card = tester.widget<CupertinoButton>(
      find.ancestor(
        of: find.text('城市夜游').first,
        matching: find.byType(CupertinoButton),
      ),
    );
    card.onPressed!();
    card.onPressed!();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-detail-sheet')), findsOneWidget);
    expect(
      observer.pushed.whereType<CupertinoSheetRoute<void>>(),
      hasLength(1),
    );
  });
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (int attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget, reason: '官方 Cupertino Sheet 应在 1 秒内呈现');
}

class _RouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}
