@Tags(<String>['needs-macos-fonts'])
// 确认按钮落在 800x600 视口下沿;换字体后被挤出屏幕,tap 打不中。
// CI 跑在自托管 Mac 上,这条用例在 CI 上会跑;tag 是给非 macOS 机器本地排除用的。
library;

import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/mall_api.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/feature/mall/cart_checkout_sheet.dart';
import 'package:chengyin_app/feature/mall/mall_controller.dart';
import 'package:chengyin_app/feature/mall/product_detail_page.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MallApi implements MallApi {
  final Completer<int> gate = Completer<int>();
  int settleCalls = 0;
  int? addressId;
  String? remark;
  List<int>? previewCartIds;
  CartSettlementPreview? previewResult;
  int cartAddCalls = 0;
  int? addedSkuId;
  int? addedQuantity;
  int? immediateOrderId;

  @override
  Future<void> cartAdd({
    required int productId,
    required int skuId,
    required int quantity,
    int isBuy = 0,
  }) async {
    cartAddCalls += 1;
    addedSkuId = skuId;
    addedQuantity = quantity;
  }

  @override
  Future<CartSettlementPreview> previewSettlement(List<int> cartIds) async {
    previewCartIds = List<int>.of(cartIds);
    return previewResult ?? preview();
  }

  @override
  Future<int> settleOrder({
    required List<int> cartIds,
    required String remark,
    required int addressId,
  }) async {
    settleCalls += 1;
    this.addressId = addressId;
    this.remark = remark;
    if (immediateOrderId != null) return immediateOrderId!;
    return gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 9, nickname: '探索者', avatar: '', role: 'player'),
  );
}

CartSettlementPreview preview({
  double? total = 120,
  double? balance = 500,
  SettlementAddress? address,
}) => CartSettlementPreview(
  cartType: 2,
  productAmount: total,
  productQuantity: 2,
  deliveryFee: 0,
  taxFee: 0,
  totalAmount: total,
  pointBalance: balance,
  products: <CartItem>[
    CartItem(
      id: 11,
      productId: 101,
      skuId: 1001,
      quantity: 2,
      productName: '城市邮票册',
      price: 60,
    ),
  ],
  address: address,
);

const MemberAddress addressA = MemberAddress(
  id: 7,
  fullName: '顾青',
  mobilePhone: '13900001111',
  province: '上海市 黄浦区',
  detailAddress: '中山东一路 1 号',
  isDefault: true,
);

const MemberAddress addressB = MemberAddress(
  id: 8,
  fullName: '林川',
  mobilePhone: '13800002222',
  province: '上海市 静安区',
  detailAddress: '愚园路 8 号',
);

Widget _app({
  required _MallApi api,
  required CartSettlementPreview settlement,
  required List<MemberAddress> addresses,
  ValueChanged<int>? onCompleted,
}) => ProviderScope(
  overrides: <dynamic>[
    mallApiProvider.overrideWithValue(api),
    addressListProvider.overrideWith((ref) async => addresses),
  ].cast(),
  child: MaterialApp(
    home: CartCheckoutSheet(
      preview: settlement,
      cartIds: const <int>[11],
      scrollController: ScrollController(),
      onCompleted: onCompleted,
    ),
  ),
);

void main() {
  testWidgets('确认兑换后先展示商城成功页和订单号，再返回商城', (tester) async {
    final api = _MallApi()
      ..immediateOrderId = 9876
      ..previewResult = preview(
        address: const SettlementAddress(
          id: 7,
          fullName: '顾青',
          mobilePhone: '13900001111',
          province: '上海市 黄浦区',
          detailAddress: '中山东一路 1 号',
        ),
      );
    final router = GoRouter(
      initialLocation: '/cart',
      routes: <RouteBase>[
        GoRoute(path: '/cart', builder: (_, _) => const CartPage()),
        GoRoute(path: '/mall', builder: (_, _) => const Text('商城首页')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          mallApiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          cartListProvider.overrideWith(
            (ref) async => <CartItem>[
              CartItem(
                id: 11,
                productId: 101,
                skuId: 1001,
                quantity: 2,
                productName: '城市邮票册',
                price: 60,
              ),
            ],
          ),
          addressListProvider.overrideWith(
            (ref) async => const <MemberAddress>[addressA],
          ),
        ].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mall-cart-checkout')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.scrollUntilVisible(
      find.byKey(const Key('mall-checkout-confirm')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    // scrollUntilVisible 只保证控件已构建,字号落 iOS Body 17 后按钮中心仍可能压线。
    await tester.ensureVisible(find.byKey(const Key('mall-checkout-confirm')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mall-checkout-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(router.routeInformationProvider.value.uri.path, '/cart');
    expect(find.text('兑换成功'), findsOneWidget);
    expect(find.text('订单编号：9876'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mall-checkout-success-done')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/mall');
    expect(find.text('商城首页'), findsOneWidget);
  });

  testWidgets('加购 Sheet 选择真实 SKU，并按该规格积分与库存提交', (tester) async {
    final api = _MallApi();
    final product = Product(
      id: 101,
      productName: '城市邮票册',
      price: 120,
      stock: 0,
      skuList: <ProductSku>[
        ProductSku(id: 1001, skuName: '雾灰', price: 120, stock: 5),
        ProductSku(id: 1002, skuName: '城市蓝', price: 150, stock: 2),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          mallApiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          productDetailProvider(101).overrideWith((ref) async => product),
        ].cast(),
        child: const MaterialApp(home: ProductDetailPage(productId: 101)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('加入购物车'), findsOneWidget);
    await tester.tap(find.text('加入购物车'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const Key('mall-sku-1002')));
    await tester.pump();

    expect(find.text('150 积分'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('增加数量'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('增加数量'));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('确认加入'));
    await tester.pump();

    expect(api.cartAddCalls, 1);
    expect(api.addedSkuId, 1002);
    expect(api.addedQuantity, 2);
  });

  testWidgets('购物车“去兑换”会用当前 cart id 请求预览并打开原生 Sheet', (tester) async {
    final api = _MallApi()..previewResult = preview(address: null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          mallApiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          cartListProvider.overrideWith(
            (ref) async => <CartItem>[
              CartItem(
                id: 11,
                productId: 101,
                skuId: 1001,
                quantity: 2,
                productName: '城市邮票册',
                price: 60,
              ),
            ],
          ),
          addressListProvider.overrideWith((ref) async => const []),
        ].cast(),
        child: const MaterialApp(home: CartPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('120 积分'), findsOneWidget);
    expect(find.textContaining('¥'), findsNothing);
    await tester.tap(find.byKey(const Key('mall-cart-checkout')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(api.previewCartIds, <int>[11]);
    expect(find.text('确认兑换'), findsWidgets);
    expect(find.byType(CartCheckoutSheet), findsOneWidget);
  });

  testWidgets('无收货地址时明确引导管理地址且不能确认兑换', (tester) async {
    final api = _MallApi();
    await tester.pumpWidget(
      _app(api: api, settlement: preview(address: null), addresses: const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有可用的收货地址'), findsOneWidget);
    expect(find.text('管理收货地址'), findsOneWidget);
    final button = tester.widget<CyNativeButton>(
      find.widgetWithText(CyNativeButton, '请选择收货地址'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('地址列表还没回来时是加载态，不冒充空地址', (tester) async {
    final Completer<List<MemberAddress>> pending =
        Completer<List<MemberAddress>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          mallApiProvider.overrideWithValue(_MallApi()),
          addressListProvider.overrideWith((ref) => pending.future),
        ].cast(),
        child: MaterialApp(
          home: CartCheckoutSheet(
            preview: preview(address: null),
            cartIds: const <int>[11],
            scrollController: ScrollController(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text('还没有可用的收货地址'), findsNothing);

    pending.complete(const <MemberAddress>[addressA]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoadingView), findsNothing);
    expect(find.textContaining('顾青'), findsOneWidget);
  });

  testWidgets('积分余额明确不足时禁用兑换，不把它当人民币支付', (tester) async {
    final api = _MallApi();
    await tester.pumpWidget(
      _app(
        api: api,
        settlement: preview(
          balance: 100,
          address: const SettlementAddress(
            id: 7,
            fullName: '顾青',
            mobilePhone: '13900001111',
            province: '上海市 黄浦区',
            detailAddress: '中山东一路 1 号',
          ),
        ),
        addresses: const <MemberAddress>[addressA],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('需要 120 积分'), findsWidgets);
    expect(find.text('当前 100 积分'), findsOneWidget);
    expect(find.textContaining('¥'), findsNothing);
    final button = tester.widget<CyNativeButton>(
      find.widgetWithText(CyNativeButton, '积分不足'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('可以选择地址、使用系统输入备注，并防止重复提交', (tester) async {
    final api = _MallApi();
    int? completed;
    await tester.pumpWidget(
      _app(
        api: api,
        settlement: preview(
          address: const SettlementAddress(
            id: 7,
            fullName: '顾青',
            mobilePhone: '13900001111',
            province: '上海市 黄浦区',
            detailAddress: '中山东一路 1 号',
          ),
        ),
        addresses: const <MemberAddress>[addressA, addressB],
        onCompleted: (int id) => completed = id,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTextField), findsOneWidget);
    await tester.tap(find.byKey(const Key('mall-checkout-address-8')));
    await tester.enterText(
      find.byKey(const Key('mall-checkout-remark')),
      '工作日送达',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('mall-checkout-confirm')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('mall-checkout-confirm')));
    await tester.tap(find.byKey(const Key('mall-checkout-confirm')));
    await tester.pump();

    expect(api.settleCalls, 1, reason: '处理中再次点击不能创建第二笔订单');
    expect(api.addressId, 8);
    expect(api.remark, '工作日送达');

    api.gate.complete(9876);
    await tester.pumpAndSettle();
    expect(find.text('订单编号：9876'), findsOneWidget);
    expect(completed, isNull);

    await tester.tap(find.byKey(const Key('mall-checkout-success-done')));
    await tester.pumpAndSettle();
    expect(completed, 9876);
  });
}
