import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/feature/mall/cart_page.dart';
import 'package:chengyin_app/feature/mall/mall_controller.dart';
import 'package:chengyin_app/feature/publish/publish_pro_ticket_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('购物车数量步进器有可读名称和当前值', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          cartListProvider.overrideWith(
            (ref) async => <CartItem>[
              CartItem.fromJson(<String, dynamic>{
                'id': 1,
                'productId': 11,
                'skuId': 111,
                'quantity': 2,
                'productName': '城瘾帆布包',
                'price': 89.0,
              }),
            ],
          ),
        ].cast(),
        child: const MaterialApp(home: CartPage()),
      ),
    );
    await tester.pumpAndSettle();

    final decrease = tester.getSemantics(find.bySemanticsLabel('减少数量'));
    final increase = tester.getSemantics(find.bySemanticsLabel('增加数量'));
    expect(decrease.value, '2');
    expect(increase.value, '2');
    expect(decrease.rect.size.width, greaterThanOrEqualTo(44));
    expect(increase.rect.size.height, greaterThanOrEqualTo(44));
    handle.dispose();
  });

  testWidgets('专业发布票种删除动作有 VoiceOver 名称', (WidgetTester tester) async {
    final PublishDraft draft = PublishDraft()
      ..tickets = <PublishTicket>[PublishTicket(), PublishTicket()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PublishTicketTab(
              draft: draft,
              merchantPoolEditable: false,
              myClubs: const <Club>[],
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('删除票种'), findsNWidgets(2));
    for (final Element element in find.bySemanticsLabel('删除票种').evaluate()) {
      expect(tester.getSize(find.byWidget(element.widget)), const Size(44, 44));
    }
  });
}
