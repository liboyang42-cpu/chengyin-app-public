import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/feature/template/template_dict.dart';
import 'package:chengyin_app/feature/template/template_edit_page.dart';

class _CategoryApi implements CategoryApi {
  @override
  Future<List<Category>> list({String? type}) async => const <Category>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        categoryApiProvider.overrideWithValue(_CategoryApi()),
        dictProvider('app_template_players').overrideWith(
          (Ref ref) async => const <DictOption>[
            DictOption(value: '0', label: '1-2 人'),
            DictOption(value: '1', label: '3-5 人'),
          ],
        ),
        dictProvider('app_template_duration').overrideWith(
          (Ref ref) async => const <DictOption>[
            DictOption(value: '0', label: '10min'),
          ],
        ),
        dictProvider('app_template_difficulty').overrideWith(
          (Ref ref) async => const <DictOption>[
            DictOption(value: '0', label: '简易'),
          ],
        ),
      ].cast(),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: const TemplateEditPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('玩家人数使用 Cupertino 底部选择器而非 Material 下拉', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final Finder pickerButton = find.descendant(
      of: find.byKey(const Key('template-field-players')),
      matching: find.byType(CupertinoButton),
    );
    expect(tester.widget<CupertinoButton>(pickerButton).onPressed, isNotNull);
    await tester.tap(pickerButton);
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('选择玩家人数'), findsOneWidget);
    expect(find.text('1-2 人'), findsOneWidget);
  });

  testWidgets('同步开关使用 CupertinoSwitch 且仍位于页面尾部', (WidgetTester tester) async {
    await _pump(tester);
    final Finder label = find.text('同步到模板库');
    await tester.scrollUntilVisible(
      label,
      600,
      scrollable: find.byType(Scrollable).first,
    );

    expect(label, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('template-sync-switch-row')),
        matching: find.byType(CupertinoSwitch),
      ),
      findsOneWidget,
    );
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('200% 动态字号下双列选择器自动叠放且仍可滚动访问', (WidgetTester tester) async {
    await _pump(tester, textScaler: const TextScaler.linear(2));
    expect(tester.takeException(), isNull);

    final Rect players = tester.getRect(
      find.byKey(const Key('template-field-players')),
    );
    final Rect duration = tester.getRect(
      find.byKey(const Key('template-field-duration')),
    );
    expect(duration.top, greaterThan(players.bottom));
  });
}
