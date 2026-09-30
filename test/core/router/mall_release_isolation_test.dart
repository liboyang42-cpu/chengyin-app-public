import 'package:dio/dio.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/mall_api.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/feature/mall/product_detail_page.dart';
import 'package:chengyin_app/feature/mall/product_list_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _CountingMallApi implements MallApi {
  /// 生产后端对游客的购物车请求返回 HTTP 401(`/api/cart/list`,实测 2026-09-18)。
  /// 默认 false 让「已登录」那条用例继续跑空表;游客那条必须显式打开 ——
  /// 见下面那条用例的注释:原来的 stub 无条件返回空表,把死路演成了活路。
  _CountingMallApi({this.cartNeedsLogin = false});

  final bool cartNeedsLogin;
  int productListCalls = 0;
  int productInfoCalls = 0;
  int cartListCalls = 0;

  @override
  Future<List<Product>> productList({
    int? merchantId,
    int sortType = 0,
    String? keyword,
  }) async {
    productListCalls += 1;
    return <Product>[];
  }

  @override
  Future<Product> productInfo(int id) async {
    productInfoCalls += 1;
    return Product(id: id, productName: '城市邮票册', price: 120, stock: 3);
  }

  @override
  Future<List<CartItem>> cartList() async {
    cartListCalls += 1;
    if (cartNeedsLogin) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/cart/list'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/cart/list'),
          statusCode: 401,
        ),
      );
    }
    return <CartItem>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('三条商城深链打开真实积分商城页面并请求各自 API', (WidgetTester tester) async {
    final api = _CountingMallApi();
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_FixedAuth.new),
        mallApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();

    final router = container.read(appRouterProvider);
    router.go('/mall');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ProductListPage), findsOneWidget);
    expect(api.productListCalls, 1);

    router.go('/cart');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(CartPage), findsOneWidget);
    expect(api.cartListCalls, 1);

    router.go('/product/123');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ProductDetailPage), findsOneWidget);
    expect(find.text('120 积分'), findsOneWidget);
    expect(api.productInfoCalls, 1);
    expect(find.text('商城暂未开放'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ★ 这条用例原来写的是「游客冷启动可浏览购物车，兑换动作再触发登录门」,
  //   并且断言游客能看到「购物车空空如也」。那是**假绿**:stub 无条件返回空表,
  //   而生产后端 `/api/cart/list` 对无 token 请求是 HTTP 401(实测 2026-09-18),
  //   游客永远看不到空态,只看到「购物车拉取失败 / 请检查网络」。
  //   设计意图(游客可浏览购物车)要成立得由后端放开读接口 —— App 侧做不到,
  //   所以这里改成守住**线上真实口径**:401 → 登录引导 + 真能走通的登录出口。
  testWidgets('游客进购物车撞 401：走登录引导，不谎报网络故障', (WidgetTester tester) async {
    final api = _CountingMallApi(cartNeedsLogin: true);
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_GuestAuth.new),
        mallApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    container.read(appRouterProvider).go('/cart?source=push');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/cart',
    );
    expect(find.byType(CartPage), findsOneWidget);
    expect(find.text('登录后查看购物车'), findsOneWidget);
    expect(find.textContaining('请检查网络'), findsNothing);
    expect(api.cartListCalls, 1);

    // 「去登录」得真的能点开登录弹窗 —— 否则还是条没有出口的死路。
    await tester.tap(find.text('去登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录城瘾'), findsOneWidget);
  });
}
