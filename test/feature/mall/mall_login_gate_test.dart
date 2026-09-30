// 商城两页的游客态:后端 401 必须变成「登录后查看」+ 去登录,不能渲成「请检查网络」。
//
// ★ 依据是对生产后端的实测(b1-sim-mall 报告 §6,2026-09-18,无 token):
//   `POST /api/product/info` → 401 · `POST /api/cart/list` → 401 ·
//   而 `POST /api/product/list` → 200(列表公开、详情与购物车要登录)。
//   原实现两页都把 401 说成「请检查网络或稍后再试」+ 重试:
//   重试永远不会成功,页面上也没有登录出口 —— 游客从列表点进商品就是死路。
//
// 同时守住反面:网络故障**不能**也被当成要登录,否则断网用户会被反复推去登录页
// (同活动详情页 2026-08-18 的判据,test/feature/activity/detail_unauthorized_test.dart)。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/feature/mall/mall_controller.dart';
import 'package:chengyin_app/feature/mall/product_detail_page.dart';

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

DioException _http(int status, String path) => DioException(
  requestOptions: RequestOptions(path: path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: status,
  ),
);

// Riverpod 3 把 `Override` 导出在另一处,这里按仓内既有写法靠推断。
Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
  overrides: <dynamic>[
    authControllerProvider.overrideWith(_GuestAuth.new),
    ...overrides,
  ].cast(),
  child: MaterialApp(home: home),
);

void main() {
  testWidgets('商品详情 401 → 登录引导(不是「请检查网络」)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        productDetailProvider(
          101,
        ).overrideWith((ref) async => throw _http(401, '/api/product/info')),
      ], const ProductDetailPage(productId: 101)),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看商品详情'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.textContaining('请检查网络'), findsNothing);
  });

  testWidgets('商品详情网络故障 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        productDetailProvider(101).overrideWith(
          (ref) async => throw DioException(
            requestOptions: RequestOptions(path: '/api/product/info'),
            type: DioExceptionType.connectionError,
          ),
        ),
      ], const ProductDetailPage(productId: 101)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('商品拉取失败'), findsOneWidget);
    expect(find.text('登录后查看商品详情'), findsNothing);
  });

  testWidgets('购物车 401 → 登录引导 + 点「去登录」真能打开登录弹窗', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        cartListProvider.overrideWith(
          (ref) async => throw _http(401, '/api/cart/list'),
        ),
      ], const CartPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看购物车'), findsOneWidget);
    expect(find.textContaining('请检查网络'), findsNothing);

    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
  });

  testWidgets('购物车网络故障 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app(<dynamic>[
        cartListProvider.overrideWith(
          (ref) async => throw DioException(
            requestOptions: RequestOptions(path: '/api/cart/list'),
            type: DioExceptionType.connectionError,
          ),
        ),
      ], const CartPage()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('购物车拉取失败'), findsOneWidget);
    expect(find.text('登录后查看购物车'), findsNothing);
  });
}
