import 'dart:io';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/coop_invite.dart';
import 'package:chengyin_app/feature/coop/coop_perk_template_page.dart';
import 'package:chengyin_app/feature/coop/coop_target_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PerkApi implements CoopApi {
  Map<String, dynamic>? saved;

  @override
  Future<List<Map<String, dynamic>>> perkTemplates() async => const [];

  @override
  Future<int> savePerkTemplate(Map<String, dynamic> data) async {
    saved = data;
    return 7;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TargetHarness extends StatefulWidget {
  const _TargetHarness({required this.onResult});
  final ValueChanged<List<CoopInviteTarget>?> onResult;

  @override
  State<_TargetHarness> createState() => _TargetHarnessState();
}

class _TargetHarnessState extends State<_TargetHarness> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext sheetContext) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await pickCoopTargets(
                  sheetContext,
                  type: CoopInviteType.merchant,
                  already: const <CoopInviteTarget>[
                    CoopInviteTarget(toId: 1, name: '已选商家'),
                  ],
                );
                widget.onResult(result);
              },
              child: const Text('选择对象'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  test('合作流弹层不再使用 Material sheet/dialog 和 Material 表单控件', () {
    final files = <String>[
      'lib/feature/coop/coop_perk_template_page.dart',
      'lib/feature/coop/coop_target_picker.dart',
      'lib/feature/coop/coop_list_page.dart',
    ];
    final source = files
        .map((path) => File(path).readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('showModalBottomSheet')));
    expect(source, isNot(contains('showDialog<')));
    expect(source, isNot(contains('return AlertDialog(')));
    expect(source, isNot(contains('CheckboxListTile(')));
    expect(source, isNot(contains('child: FilledButton(')));
    expect(source, contains('showCupertinoSheet'));
    expect(source, contains('CupertinoAlertDialog'));
    expect(source, contains('CupertinoTextField'));
    expect(source, contains('CupertinoCheckbox'));
  });

  testWidgets('常备权益表单使用 Cupertino 输入、系统日期并保持小程序 payload', (
    WidgetTester tester,
  ) async {
    final api = _PerkApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[coopApiProvider.overrideWithValue(api)].cast(),
        child: const MaterialApp(home: CoopPerkTemplatePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加权益'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.byKey(const Key('coop-perk-name')),
        matching: find.byType(CupertinoPageScaffold),
      ),
      findsOneWidget,
    );
    expect(find.byType(CupertinoTextField), findsNWidgets(4));
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);

    await tester.enterText(find.byKey(const Key('coop-perk-name')), '集章礼袋');
    await tester.enterText(find.byKey(const Key('coop-perk-retail')), '88.500');
    await tester.enterText(find.byKey(const Key('coop-perk-cost')), '20');
    await tester.enterText(find.byKey(const Key('coop-perk-quota')), '30');
    await tester.pump();
    expect(
      tester
          .widget<CupertinoButton>(find.byKey(const Key('coop-perk-save')))
          .onPressed,
      isNull,
      reason: '小程序和服务端都只允许两位小数，不能等请求后才失败',
    );
    await tester.enterText(find.byKey(const Key('coop-perk-retail')), '88.50');
    await tester.tap(find.byKey(const Key('coop-perk-valid-end')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await tester.tap(find.byKey(const Key('cy-native-picker-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coop-perk-save')));
    await tester.pumpAndSettle();

    expect(api.saved, isNotNull);
    expect(api.saved!['perkType'], 0);
    expect(api.saved!['name'], '集章礼袋');
    expect(api.saved!['retailValue'], 88.5);
    expect(api.saved!['unitCost'], 20.0);
    expect(api.saved!['quota'], 30);
    expect(api.saved!['validEnd'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  testWidgets('邀约对象多选使用 Cupertino checkbox，已选项不可重复返回', (
    WidgetTester tester,
  ) async {
    List<CoopInviteTarget>? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          coopTargetsProvider(CoopInviteType.merchant).overrideWith(
            (ref) async => const <CoopInviteTarget>[
              CoopInviteTarget(toId: 1, name: '已选商家'),
              CoopInviteTarget(toId: 2, name: '新商家'),
            ],
          ),
        ].cast(),
        child: _TargetHarness(onResult: (value) => result = value),
      ),
    );

    await tester.tap(find.text('选择对象'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoCheckbox), findsNWidgets(2));

    final disabled = tester.widget<CupertinoButton>(
      find.byKey(const Key('coop-target-1')),
    );
    expect(disabled.onPressed, isNull, reason: '已选项必须是真禁用，不只是变灰');
    await tester.tap(find.byKey(const Key('coop-target-2')));
    await tester.pump();
    expect(find.text('确定(1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coop-target-done')));
    await tester.pumpAndSettle();
    expect(result?.map((item) => item.toId), <int>[2]);
  });
}
