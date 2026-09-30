// 购物车行左滑 = 删除(#382 P0「我的内容列表左滑操作」rollout,a5-ios27-swipe-rollout)。
//
// 盯两件事:
//   ① 旧的行内单删按钮收进左滑后,**动作没变味** —— 点一下仍按 cartId
//      调 `MallApi.cartDelete`,不走别的出口;
//   ② 组件默认「划到底不执行、必须点一下」在页面上成立(滑动只露出)。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/mall_api.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/feature/mall/mall_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMallApi implements MallApi {
  final List<int> deletedCartIds = <int>[];
  int updateCalls = 0;

  @override
  Future<void> cartDelete(int cartId) async {
    deletedCartIds.add(cartId);
  }

  @override
  Future<void> cartUpdate({
    required int cartId,
    required int quantity,
    required int skuId,
  }) async {
    updateCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CartItem _item(int id, String name) => CartItem(
  id: id,
  productId: 100 + id,
  skuId: 1000 + id,
  quantity: 1,
  productName: name,
  price: 60,
);

class _LoggedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 9, nickname: '探索者', avatar: '', role: 'player'),
  );
}

Future<void> _pump(WidgetTester tester, _FakeMallApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        mallApiProvider.overrideWithValue(api),
        authControllerProvider.overrideWith(_LoggedIn.new),
        cartListProvider.overrideWith(
          (ref) async => <CartItem>[_item(11, '城市邮票册'), _item(12, '夜游门票')],
        ),
      ].cast(),
      child: const MaterialApp(home: CartPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('收起态没有常驻删除钮;左滑露出,点一下才按原 cartId 删', (tester) async {
    final api = _FakeMallApi();
    await _pump(tester, api);

    expect(find.text('删除'), findsNothing, reason: '操作钮不该常驻在列表里');

    await tester.drag(find.text('城市邮票册'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(api.deletedCartIds, <int>[11]);
    expect(find.text('删除'), findsNothing, reason: '执行后自动收起');
  });

  testWidgets('划到底不直接执行(破坏性动作必须点一下)', (tester) async {
    final api = _FakeMallApi();
    await _pump(tester, api);

    // 一次惯性长滑 = 全划开。组件默认 performsFirstActionWithFullSwipe=false。
    await tester.fling(find.text('夜游门票'), const Offset(-600, 0), 1200);
    await tester.pumpAndSettle();

    expect(api.deletedCartIds, isEmpty, reason: '滑动本身不许变成后果');
    expect(find.text('删除'), findsOneWidget, reason: '只负责露出');

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(api.deletedCartIds, <int>[12]);
  });

  testWidgets('同一时刻只开一行;步进器等既有行内交互不受影响', (tester) async {
    final api = _FakeMallApi();
    await _pump(tester, api);

    await tester.drag(find.text('城市邮票册'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('夜游门票'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget, reason: '两行都开着就分不清删的是谁');

    // 数量步进仍直达(没被滑动壳吃掉)。
    await tester.tap(find.bySemanticsLabel('增加数量').first);
    await tester.pumpAndSettle();
    expect(api.updateCalls, 1);
  });
}
