// orders 域错误落点:不把 `Exception: ...` / `DioException [...]` 实现细节抛给用户。
// 口径同 participation 域 b1 收口(#283):后端中文原话透传,网络/401 给固定人话。

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/explore_completion.dart';
import 'package:chengyin_app/feature/orders/order_detail_sheet.dart';
import 'package:chengyin_app/feature/orders/order_list_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('后端中文原话透传,剥掉 Exception: 前缀', () {
    expect(orderUserErrorText(Exception('无权查看该报名信息')), '无权查看该报名信息');
  });

  test('DioException 不再把英文异常原文直出', () {
    final DioException e = DioException(
      requestOptions: RequestOptions(path: '/api/registration/info'),
      type: DioExceptionType.connectionTimeout,
    );
    expect(orderUserErrorText(e), '网络异常，请重试');
    expect(orderUserErrorText(e), isNot(contains('DioException')));
  });

  test('401 说「登录状态已失效」,不让人重试一条死路', () {
    final DioException e = DioException(
      requestOptions: RequestOptions(path: '/api/registration/info'),
      response: Response(
        statusCode: 401,
        requestOptions: RequestOptions(path: '/api/registration/info'),
      ),
    );
    expect(orderUserErrorText(e), '登录状态已失效，请重新登录');
  });

  testWidgets('详情失败态渲染人话,不出现异常原文', (tester) async {
    final Future<RegistrationDetail> failing = Future<RegistrationDetail>(
      () => throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderDetailProvider(31).overrideWith((_) => failing),
          orderCompletionProvider(
            31,
          ).overrideWith((_) => Future<ExploreCompletion?>.value(null)),
        ],
        child: MaterialApp(home: Scaffold(body: OrderDetailSheet(orderId: 31))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('订单详情加载失败'), findsOneWidget);
    expect(find.text('网络异常，请重试'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });
}
