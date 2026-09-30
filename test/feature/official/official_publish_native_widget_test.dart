import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/feature/official/official_publish_page.dart';

class _NativeFakeApi implements OfficialApi {
  @override
  Future<bool> canPublish() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        officialApiProvider.overrideWithValue(_NativeFakeApi()),
      ].cast(),
      child: const MaterialApp(home: OfficialPublishPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('完整发布表单使用 Apple 原生输入、分段控件与开关', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.byType(CupertinoTextField), findsNWidgets(6));
    expect(
      find.byType(CupertinoSlidingSegmentedControl<String>),
      findsOneWidget,
    );
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNWidgets(4));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(DropdownButtonFormField<dynamic>), findsNothing);
  });

  testWidgets('分类使用 Action Sheet，日期使用系统 Cupertino picker', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('official-category')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('城市点亮日'), findsWidgets);
    Navigator.of(tester.element(find.byType(CupertinoActionSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('official-start-date')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('只发通知时隐藏活动配置，未选受众明确禁用', (WidgetTester tester) async {
    await _pump(tester);

    final CupertinoSlidingSegmentedControl<String> mode = tester.widget(
      find.byKey(const Key('official-mode')),
    );
    mode.onValueChanged('notice');
    await tester.pump();

    expect(find.byKey(const Key('official-title')), findsNothing);
    expect(find.text('通知配置 （可选）'), findsNothing);
    expect(find.text('通知配置'), findsOneWidget);
    expect(find.text('请选择通知对象'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('official-publish')))
          .onPressed,
      isNull,
    );
  });
}
