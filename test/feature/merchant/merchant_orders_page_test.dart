// 商家订单页。
//
// ★★ 「没拿到」≠「没有」这类缺陷本批最高频:
//   · payAmount 缺席 → 必须显破折号,不能冒充 ¥0.00(cny() 已经处理,这里锁一道回归)
//   · aftersaleStatus == 1 是后端定义里的「无售后」——**不是** 0,也不是缺席。
//     只有 ≥2 才是真的在处理售后,这条不锁的话很容易顺手写成 `> 0` 而不是 `> 1`。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/merchant/merchant_orders_page.dart';
import '../../golden/golden_theme.dart' show merchantGoldenTheme;

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(theme: merchantGoldenTheme(), home: home),
  );
}

void main() {
  group('订单状态字典', () {
    test('六档明确文案', () {
      expect(orderStatusText(0), '待付款');
      expect(orderStatusText(1), '待发货');
      expect(orderStatusText(2), '已发货');
      expect(orderStatusText(3), '待评价');
      expect(orderStatusText(4), '已完成');
      expect(orderStatusText(5), '已关闭');
      expect(orderStatusText(6), '无效订单');
    });
    test('未知编号不瞎猜含义,原样带出编号', () {
      expect(orderStatusText(99), '状态 99');
    });
    test('缺席给空串,不是某个具体状态', () {
      expect(orderStatusText(null), '');
    });
  });

  group('★★ 售后状态:1 是「无售后」,不是 0 也不是缺席', () {
    test('1 → 不显示售后标签', () {
      expect(aftersaleStatusText(1), isNull);
    });
    test('缺席 → 同样不显示', () {
      expect(aftersaleStatusText(null), isNull);
    });
    test('2/3/4 → 对应文案', () {
      expect(aftersaleStatusText(2), '售后处理中');
      expect(aftersaleStatusText(3), '退款中');
      expect(aftersaleStatusText(4), '退款成功');
    });
  });

  testWidgets('★ 金额缺席显破折号,不冒充 ¥0.00', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(_app(
      <dynamic>[
        merchantOrdersProvider.overrideWith((ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'orderSn': 'OMS_NO_AMOUNT',
                'status': 0,
                // payAmount 故意缺席
              },
              <String, dynamic>{
                'orderSn': 'OMS_AFTERSALE',
                'status': 4,
                'payAmount': 38.5,
                'aftersaleStatus': 3,
              },
            ]),
      ],
      const MerchantOrdersPage(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('—'), findsOneWidget, reason: '金额缺席不能显示成 ¥0.00');
    expect(find.text('¥38.50'), findsOneWidget);
    expect(find.text('退款中'), findsOneWidget);
    // 第一条 aftersaleStatus 缺席,不该有任何售后标签跟着它。
    expect(find.text('待付款'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('空列表:说清"还没有订单",不是加载失败', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(_app(
      <dynamic>[
        merchantOrdersProvider.overrideWith((ref) async => <Map<String, dynamic>>[]),
      ],
      const MerchantOrdersPage(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('还没有订单'), findsOneWidget);
  });
}
