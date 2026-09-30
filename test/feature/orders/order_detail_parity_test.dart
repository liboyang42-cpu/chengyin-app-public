import 'dart:async';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/explore_completion.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RegistrationDetail detail([Map<String, dynamic> patch = const {}]) =>
      RegistrationDetail.fromJson(<String, dynamic>{
        'id': 31,
        'ownerType': 2,
        'ownerId': 9,
        'registrationNo': 'CY-31',
        'registrationStatus': 2,
        'verificationStatus': 0,
        'paymentStatus': 2,
        'purchaseKind': 3,
        'ticketName': '探店票',
        'ticketPrice': 49.9,
        'orderNum': 2,
        'payableAmount': 89.8,
        'pointUsed': 100,
        'pointPaymentAmount': 1,
        'wechatPaymentAmount': 88.8,
        'paymentTime': '2026-08-22 10:20:00',
        'paymentTypeLabel': '微信+积分',
        'transactionId': 'WX123',
        'realName': '李某',
        'phone': '138****8000',
        'participateDate': '2026-08-22',
        'expiresAt': '2026-11-22 23:59:59',
        'refundDeadlineDisplay': '可免费取消至 8月23日 12:00',
        'organizerName': '城市漫游俱乐部',
        'cmsActivity': <String, dynamic>{
          'name': '静安探店日',
          'description': '四家店的城市游戏',
          'imgUrl': 'https://img.example/hero.jpg',
          'startDate': '2026-08-23 13:00:00',
        },
        'omsTicket': <String, dynamic>{
          'startTime': '2026-08-23 13:00:00',
          'endTime': '2026-08-23 17:00:00',
          'meetingPoint': '静安寺 1 号口',
          'gatherLat': 31.22,
          'gatherLng': 121.45,
        },
        'entitlements': <dynamic>[
          <String, dynamic>{
            'id': 1,
            'chapterId': 101,
            'chapterName': '咖啡站',
            'status': 1,
            'statusLabel': '已核销',
          },
          <String, dynamic>{
            'id': 2,
            'chapterId': 102,
            'chapterName': '书店站',
            'status': 0,
            'statusLabel': '待核销',
          },
        ],
        ...patch,
      });

  Widget app({
    required Future<RegistrationDetail> order,
    Future<ExploreCompletion?>? completion,
    Future<void> Function()? onPay,
    Future<void> Function()? onCancel,
  }) {
    return ProviderScope(
      overrides: [
        orderDetailProvider(31).overrideWith((_) => order),
        orderCompletionProvider(
          31,
        ).overrideWith((_) => completion ?? Future.value(null)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: OrderDetailSheet(orderId: 31, onPay: onPay, onCancel: onCancel),
        ),
      ),
    );
  }

  testWidgets('详情使用真实 detail，完整展示 Hero/场次/价格/支付/报名人/权益', (tester) async {
    await tester.pumpWidget(app(order: Future.value(detail())));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('order-detail-sheet')), findsOneWidget);
    for (final text in <String>[
      '静安探店日',
      '场次',
      '价格明细',
      '探店票',
      '¥89.80',
      '支付信息',
      '微信+积分',
      '报名人信息',
      '李某',
      '凭证与有效期',
      '权益明细',
      '咖啡站',
      '书店站',
      '退款与客服',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.textContaining('静安寺 1 号口'), findsOneWidget);
    expect(find.textContaining('城市漫游俱乐部'), findsOneWidget);
  });

  testWidgets('接口缺失的段落诚实隐藏，不用 0 或空卡冒充', (tester) async {
    await tester.pumpWidget(
      app(
        order: Future.value(
          RegistrationDetail.fromJson(<String, dynamic>{
            'id': 31,
            'ownerType': 1,
            'ownerId': 7,
            'cmsTopic': <String, dynamic>{'name': '城市路线'},
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('城市路线'), findsWidgets);
    expect(find.text('支付信息'), findsNothing);
    expect(find.text('报名人信息'), findsNothing);
    expect(find.text('凭证与有效期'), findsNothing);
    expect(find.text('权益明细'), findsNothing);
    expect(find.text('¥0.00'), findsNothing);
  });

  testWidgets('探店完局面展示图鉴/真实到账奖励/回访，无流水不写 0', (tester) async {
    final completion = ExploreCompletion.fromJson(<String, dynamic>{
      'completed': true,
      'requiredChapterCount': 2,
      'redeemedChapterCount': 2,
      'stamps': <dynamic>[
        <String, dynamic>{'chapterId': 1, 'title': '咖啡站', 'collected': true},
        <String, dynamic>{'chapterId': 2, 'title': '书店站', 'collected': true},
      ],
      'awards': <String, dynamic>{
        'credited': true,
        'items': <dynamic>[
          <String, dynamic>{'kind': 'BADGE', 'title': '城市漫游家'},
          <String, dynamic>{'kind': 'POINTS', 'title': '积分', 'amount': 30},
        ],
      },
      'revisit': <String, dynamic>{
        'clubId': 8,
        'clubName': '城市漫游俱乐部',
        'followed': false,
        'joined': false,
        'nextEdition': <String, dynamic>{
          'topicId': 12,
          'name': '下一期',
          'startDate': '2026-09-01 10:00:00',
        },
      },
    });
    await tester.pumpWidget(
      app(order: Future.value(detail()), completion: Future.value(completion)),
    );
    await tester.pumpAndSettle();

    expect(find.text('探店图鉴'), findsOneWidget);
    expect(find.text('已集齐 2/2'), findsOneWidget);
    expect(find.text('通关奖励'), findsOneWidget);
    expect(find.text('城市漫游家'), findsOneWidget);
    expect(find.text('+30'), findsOneWidget);
    expect(find.text('下次再来'), findsOneWidget);
    expect(find.textContaining('下一期'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
  });

  testWidgets('详情失败只显示错误与重试，不泄漏列表卡伪详情', (tester) async {
    await tester.pumpWidget(
      app(
        order: Future<RegistrationDetail>.delayed(
          Duration.zero,
          () => throw Exception('无权查看该报名信息'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('订单详情加载失败'), findsOneWidget);
    expect(find.textContaining('无权查看'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('价格明细'), findsNothing);
  });

  testWidgets('待支付按小程序顺序显示取消、客服、票夹和底部去支付', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        order: Future<RegistrationDetail>.value(
          detail(<String, dynamic>{
            'registrationStatus': 1,
            'paymentStatus': 1,
            'refundInfo': null,
          }),
        ),
        onPay: () async {},
        onCancel: () async {},
      ),
    );
    await tester.pumpAndSettle();

    for (final Key key in <Key>[
      const Key('order-detail-cancel'),
      const Key('order-detail-contact'),
      const Key('order-detail-secondary-ticket'),
      const Key('order-detail-primary-pay'),
    ]) {
      await tester.scrollUntilVisible(find.byKey(key), 300);
      expect(find.byKey(key), findsOneWidget);
    }
    expect(find.text('取消订单'), findsOneWidget);
    expect(find.text('去支付'), findsOneWidget);
    for (final Key key in <Key>[
      const Key('order-detail-cancel'),
      const Key('order-detail-contact'),
      const Key('order-detail-secondary-ticket'),
      const Key('order-detail-primary-pay'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getTopLeft(find.byKey(const Key('order-detail-cancel'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('order-detail-primary-pay'))).dy,
      ),
    );
  });

  testWidgets('已支付可退款只显示主票夹和取消并退款', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        order: Future<RegistrationDetail>.value(
          detail(<String, dynamic>{
            'refundInfo': <String, dynamic>{'refundable': true},
          }),
        ),
        onPay: () async {},
        onCancel: () async {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('order-detail-primary-ticket')),
      300,
    );
    expect(find.text('取消并退款'), findsOneWidget);
    expect(
      find.byKey(const Key('order-detail-primary-ticket')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('order-detail-secondary-ticket')),
      findsNothing,
    );
    expect(find.byKey(const Key('order-detail-primary-pay')), findsNothing);
  });

  testWidgets('已支付不可退时不暴露取消入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        order: Future<RegistrationDetail>.value(
          detail(<String, dynamic>{
            'refundInfo': <String, dynamic>{'refundable': false},
          }),
        ),
        onCancel: () async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('取消并退款'), findsNothing);
    expect(find.text('取消订单'), findsNothing);
  });

  testWidgets('支付在请求完成前防重，不在客户端改订单状态', (WidgetTester tester) async {
    final Completer<void> pending = Completer<void>();
    int calls = 0;
    await tester.pumpWidget(
      app(
        order: Future<RegistrationDetail>.value(
          detail(<String, dynamic>{
            'registrationStatus': 1,
            'paymentStatus': 1,
          }),
        ),
        onPay: () {
          calls += 1;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('order-detail-primary-pay')),
      300,
    );

    await tester.tap(find.byKey(const Key('order-detail-primary-pay')));
    await tester.tap(find.byKey(const Key('order-detail-primary-pay')));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('支付中…'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Sheet 有 44pt 且 VoiceOver 可达的显式关闭按钮', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      app(order: Future<RegistrationDetail>.value(detail())),
    );
    await tester.pumpAndSettle();

    final Finder close = find.byKey(const Key('order-detail-close'));
    expect(close, findsOneWidget);
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    expect(tester.getSemantics(close).label, contains('关闭订单详情'));
  });
}
