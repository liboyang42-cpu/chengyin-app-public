import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/node_template.dart';
import 'package:chengyin_app/feature/merchant/node_template_edit_page.dart';

void main() {
  testWidgets('五种完成方式使用 CupertinoRadio 并保留原顺序', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: NodeTemplateEditPage())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RadioListTile), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is CupertinoRadio<NodeValidationMethod>,
      ),
      findsNWidgets(5),
    );
    expect(
      <String>[
        '文字作答',
        '拍照打卡',
        '选项问答',
        '到店扫码',
        'GPS 到达',
      ].map((String label) => find.text(label).evaluate().length).toList(),
      everyElement(1),
    );

    final Finder firstRow = find.byKey(const Key('node-method-1'));
    expect(tester.getSize(firstRow).height, greaterThanOrEqualTo(44));
    await tester.tap(firstRow);
    await tester.pump();
    expect(find.text('暗号答案'), findsOneWidget);
  });

  testWidgets('200% 动态字号下表单与完成方式不溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: NodeTemplateEditPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ai-node-assist')), findsOneWidget);
    expect(find.byKey(const Key('node-method-5')), findsOneWidget);
  });
}
