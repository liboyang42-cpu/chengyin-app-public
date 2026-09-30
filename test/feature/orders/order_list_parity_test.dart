import 'dart:ui' show Tristate;

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:chengyin_app/feature/orders/order_list_state.dart';
import 'package:chengyin_app/feature/orders/orders_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MyRegistration _order({
  int registrationStatus = 2,
  int verificationStatus = 0,
  Object? refundApplication,
  Object? refundInfo,
  String? startDate = '2026-08-23 13:00:00',
  String? endDate = '2026-08-23 17:00:00',
  bool activity = true,
}) => MyRegistration.fromJson(<String, dynamic>{
  'id': 41,
  'ownerType': activity ? 2 : 1,
  'ownerId': 9,
  'registrationNo': 'CY-41',
  'registrationStatus': registrationStatus,
  'verificationStatus': verificationStatus,
  if (refundApplication != null) 'refundApplication': refundApplication,
  if (refundInfo != null) 'refundInfo': refundInfo,
  activity ? 'cmsActivity' : 'cmsTopic': <String, dynamic>{
    'name': activity ? '静安城市定向' : '城市自由探索',
    'imgUrl': activity ? 'https://img.example/activity.jpg' : null,
    if (!activity) 'imgArr': 'https://img.example/topic.jpg,second.jpg',
    'startDate': startDate,
    'endDate': endDate,
    'addressName': '静安寺 1 号口',
  },
});

void main() {
  final DateTime now = DateTime(2026, 8, 23, 12);

  test('订单列表逐字保留小程序八个筛选与顺序', () {
    expect(
      OrderListFilter.values.map((OrderListFilter item) => item.label),
      <String>['全部', '待支付', '未开始', '进行中', '已完成', '退款中', '已退款', '不可退款'],
    );
  });

  test('订单状态以退款打款回执、报名、核销与时间的既有优先级归一', () {
    expect(
      summarizeOrderListState(_order(registrationStatus: 1), now: now),
      OrderListState.pendingPayment,
    );
    expect(
      summarizeOrderListState(_order(), now: now),
      OrderListState.notStarted,
    );
    expect(
      summarizeOrderListState(
        _order(startDate: '2026-08-23 10:00:00'),
        now: now,
      ),
      OrderListState.inProgress,
    );
    expect(
      summarizeOrderListState(_order(endDate: '2026-08-23 11:00:00'), now: now),
      OrderListState.completed,
    );
    expect(
      summarizeOrderListState(_order(verificationStatus: 1), now: now),
      OrderListState.completed,
    );
    expect(
      summarizeOrderListState(
        _order(refundInfo: <String, dynamic>{'refundable': false}),
        now: now,
      ),
      OrderListState.nonRefundable,
    );
    expect(
      summarizeOrderListState(
        _order(
          registrationStatus: 3,
          refundApplication: <String, dynamic>{'payoutStatus': 0},
        ),
        now: now,
      ),
      OrderListState.refunding,
    );
    expect(
      summarizeOrderListState(
        _order(
          registrationStatus: 3,
          refundApplication: <String, dynamic>{'payoutStatus': 4},
        ),
        now: now,
      ),
      OrderListState.refunded,
    );
  });

  test('退款处理中不能被伪装为已退款（负控）', () {
    final MyRegistration pendingRefund = _order(
      registrationStatus: 3,
      refundApplication: <String, dynamic>{'payoutStatus': 0},
    );
    final OrderListState actual = summarizeOrderListState(
      pendingRefund,
      now: now,
    );
    expect(actual, isNot(OrderListState.refunded));
    expect(actual, OrderListState.refunding);
    expect(orderListStateLabel(pendingRefund, now: now), '退款中');
    expect(
      orderListStateLabel(
        _order(
          registrationStatus: 3,
          refundApplication: <String, dynamic>{'payoutStatus': 2},
        ),
        now: now,
      ),
      '退款处理中',
    );
  });

  test('列表模型从小程序同源嵌套对象读取封面、时间、地点与玩法摘要', () {
    final MyRegistration activity = _order();
    final MyRegistration topic = _order(activity: false);

    expect(activity.imgUrl, 'https://img.example/activity.jpg');
    expect(activity.startDate, '2026-08-23 13:00:00');
    expect(activity.endDate, '2026-08-23 17:00:00');
    expect(activity.addressName, '静安寺 1 号口');
    expect(activity.orderMode!.label, '城市定向');
    expect(activity.orderMode!.summary, '按路线完成现场节点互动');
    expect(topic.imgUrl, 'https://img.example/topic.jpg');
    expect(topic.orderMode!.label, '自由探索');
    expect(topic.orderMode!.summary, '打开票夹后开始探索');
  });

  test('当前筛选无命中保留真实订单存在事实，并且不改变服务端列表顺序', () {
    final List<MyRegistration> rows = <MyRegistration>[
      _order(registrationStatus: 1),
      _order(refundInfo: <String, dynamic>{'refundable': false}),
    ];
    final List<MyRegistration> filtered = filterOrderList(
      rows,
      OrderListFilter.refunded,
      now: now,
    );
    expect(filtered, isEmpty);
    expect(rows, hasLength(2));
    expect(
      filterOrderList(rows, OrderListFilter.all, now: now),
      orderedEquals(rows),
    );
  });

  testWidgets('订单页保留小程序八态横滑筛选和行卡的封面时间地点玩法摘要', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith(
            (Ref ref) async => <MyRegistration>[_order()],
          ),
        ],
        child: const MaterialApp(home: OrdersPage()),
      ),
    );
    await tester.pumpAndSettle();

    for (final String label in <String>[
      '全部',
      '待支付',
      '未开始',
      '进行中',
      '已完成',
      '退款中',
      '已退款',
      '不可退款',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('城市定向'), findsOneWidget);
    expect(find.text('按路线完成现场节点互动'), findsOneWidget);
    expect(find.text('08.23 13:00 - 08.23 17:00'), findsOneWidget);
    expect(find.text('静安寺 1 号口'), findsOneWidget);
    expect(find.byKey(const Key('order-card-cover-41')), findsOneWidget);
    final Finder refunded = find.byKey(
      const ValueKey<String>('order-filter-refunded'),
    );
    expect(tester.getSize(refunded).height, greaterThanOrEqualTo(44));
    expect(tester.getSemantics(refunded).label, contains('已退款'));

    await tester.tap(refunded);
    await tester.pumpAndSettle();
    expect(find.text('当前筛选暂无订单'), findsOneWidget);
    expect(find.text('去发现城市路线'), findsNothing);
  });

  testWidgets('订单八态筛选使用 Apple 控件并支持 44pt、VoiceOver、触感与减少动态', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith(
            (Ref ref) async => <MyRegistration>[_order()],
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: OrdersPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    for (final OrderListFilter item in OrderListFilter.values) {
      final Finder control = find.byKey(
        ValueKey<String>('order-filter-${item.name}'),
      );
      expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
      expect(
        find.descendant(of: control, matching: find.byType(CupertinoButton)),
        findsOneWidget,
      );
    }

    final Finder refunded = find.byKey(
      const ValueKey<String>('order-filter-refunded'),
    );
    final Finder refundedButton = find.descendant(
      of: refunded,
      matching: find.byType(CupertinoButton),
    );
    expect(tester.widget<CupertinoButton>(refundedButton).pressedOpacity, 1);
    expect(
      tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: refunded,
              matching: find.byType(AnimatedContainer),
            ),
          )
          .duration,
      Duration.zero,
    );

    await tester.tap(refunded);
    await tester.pump();

    expect(
      platformCalls,
      contains(
        isA<MethodCall>()
            .having(
              (MethodCall call) => call.method,
              'method',
              'HapticFeedback.vibrate',
            )
            .having(
              (MethodCall call) => call.arguments,
              'arguments',
              'HapticFeedbackType.selectionClick',
            ),
      ),
    );
    expect(
      tester.getSemantics(refunded).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(tester.getSemantics(refunded).label, '已退款，已选中');
  });

  testWidgets('行卡的查看票夹先落到小程序同款订单详情 Sheet，不跳过三级页', (WidgetTester tester) async {
    final MyRegistration order = _order(
      refundInfo: <String, dynamic>{'refundable': false},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith(
            (Ref ref) async => <MyRegistration>[order],
          ),
          orderDetailProvider(41).overrideWith(
            (Ref ref) async => RegistrationDetail.fromJson(<String, dynamic>{
              'id': 41,
              'ownerType': 2,
              'ownerId': 9,
              'registrationStatus': 2,
              'refundInfo': <String, dynamic>{'refundable': false},
              'cmsActivity': <String, dynamic>{'name': '静安城市定向'},
            }),
          ),
          orderCompletionProvider(41).overrideWith((Ref ref) async => null),
        ],
        child: const MaterialApp(home: OrdersPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看票夹'));
    for (
      int attempt = 0;
      attempt < 20 &&
          find.byKey(const Key('order-detail-sheet')).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('order-detail-sheet')), findsOneWidget);
  });
}
