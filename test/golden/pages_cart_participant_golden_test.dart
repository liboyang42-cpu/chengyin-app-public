// 购物车 + 参与人两页快照。
//
// 挑它们是因为各自都有一个「拿不到就当 0/空」的隐患:
//   · 购物车:积分为 null 时小计算成 0 积分 —— 看着像免费,结账才发现不是
//   · 参与人:报名联系人需要有清晰的编辑/删除入口，手机号只露尾四位
//
// 更新基准图:flutter test --update-goldens test/golden/pages_cart_participant_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/participant_api.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/feature/mall/mall_controller.dart';
import 'golden_theme.dart';

import '../support/fixed_auth.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 860));
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('★ 购物车:含一件价格拿不到的商品', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        cartListProvider.overrideWith(
          (ref) async => <CartItem>[
            CartItem.fromJson(<String, dynamic>{
              'id': 1,
              'productId': 11,
              'skuId': 111,
              'quantity': 2,
              'productName': '城瘾联名帆布包',
              'price': 89.0,
              'skuName': '米白',
            }),
            // ★ 积分缺席时不能把小计兜成 0 积分；整车合计也不能冒充完整。
            //   这一屏就是用来看「拿不到价」到底被显示成了什么。
            CartItem.fromJson(<String, dynamic>{
              'id': 2,
              'productId': 12,
              'skuId': 121,
              'quantity': 1,
              'productName': '价格没拿到的一件',
            }),
          ],
        ),
      ], const CartPage()),
      'goldens/page_cart.png',
    );
  });

  testWidgets('购物车:空车', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        cartListProvider.overrideWith((ref) async => <CartItem>[]),
      ], const CartPage()),
      'goldens/page_cart_empty.png',
    );
  });

  testWidgets('参与人:编辑/删除入口 + 掩码只露尾四位', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        signedInAuthOverride(),
        participantsProvider.overrideWith(
          (ref) async => <Participant>[
            Participant.fromJson(<String, dynamic>{
              'id': 1,
              'fullName': '张三',
              'mobilePhone': '13812341234',
              'isDefault': 1,
            }),
            Participant.fromJson(<String, dynamic>{
              'id': 2,
              'fullName': '李四',
              'mobilePhone': '13900009999',
            }),
            // ★ 号码本来就短 —— 不该盖成一片星号
            Participant.fromJson(<String, dynamic>{
              'id': 3,
              'fullName': '号码很短的一位',
              'mobilePhone': '1234',
            }),
          ],
        ),
      ], const ParticipantsPage()),
      'goldens/page_participants.png',
    );
  });
}
