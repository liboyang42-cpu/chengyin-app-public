// 常备权益列表左滑 = 删除(#382 P0「我的内容列表左滑操作」rollout 第二批,
// a5-ios27-swipe-rollout-2)。测法参照第一批的 cart_swipe_delete_test。
//
// 盯三件事:
//   ① 旧的行内单删按钮收进左滑后,**动作没变味** —— 点一下仍按原模板 id
//      调 `CoopApi.deletePerkTemplate`,且 `cyConfirm` 二次确认闸原样保留;
//   ② 组件默认「划到底不执行、必须点一下」在页面上成立(滑动只露出);
//   ③ 同一时刻只开一行。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/models/coop_perk_template.dart';
import 'package:chengyin_app/feature/coop/coop_perk_template_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCoopApi implements CoopApi {
  final List<int> deletedIds = <int>[];

  @override
  Future<void> deletePerkTemplate(int id) async {
    deletedIds.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CoopPerkTemplate _perk(int id, String name) =>
    CoopPerkTemplate.fromJson(<String, dynamic>{
      'id': id,
      'perkType': 0,
      'name': name,
      'retailValue': 28.0,
      'quota': 20,
    });

Future<void> _pump(WidgetTester tester, _FakeCoopApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        coopApiProvider.overrideWithValue(api),
        coopPerkTemplatesProvider.overrideWith(
          (ref) async => <CoopPerkTemplate>[_perk(7, '夜游套餐'), _perk(8, '晨间茶位')],
        ),
      ].cast(),
      child: MaterialApp(
        theme: AppTheme.merchantLight(),
        home: const CoopPerkTemplatePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('收起态没有常驻删除钮;左滑露出,点一下过确认闸才按原 id 删', (tester) async {
    final api = _FakeCoopApi();
    await _pump(tester, api);

    expect(find.text('删除'), findsNothing, reason: '操作钮不该常驻在列表里');

    await tester.drag(find.text('夜游套餐'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 旧页的 cyConfirm 二次确认闸一个字没动:滑动点钮后先出确认弹窗,
    // 这时还没发删除。
    expect(find.text('删除「夜游套餐」?'), findsOneWidget);
    expect(api.deletedIds, isEmpty);

    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
    await tester.pumpAndSettle();
    expect(api.deletedIds, <int>[7]);
    expect(find.text('删除'), findsNothing, reason: '执行后自动收起');
  });

  testWidgets('划到底不直接执行(滑动本身不许变成后果)', (tester) async {
    final api = _FakeCoopApi();
    await _pump(tester, api);

    await tester.fling(find.text('夜游套餐'), const Offset(-600, 0), 1200);
    await tester.pumpAndSettle();

    expect(api.deletedIds, isEmpty);
    expect(find.text('删除'), findsOneWidget, reason: '只负责露出');
  });

  testWidgets('同一时刻只开一行', (tester) async {
    final api = _FakeCoopApi();
    await _pump(tester, api);

    await tester.drag(find.text('夜游套餐'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('晨间茶位'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('coop-perk-row-7')),
        matching: find.text('删除'),
      ),
      findsNothing,
      reason: '第二行滑开时第一行必须收起',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('coop-perk-row-8')),
        matching: find.text('删除'),
      ),
      findsOneWidget,
    );
  });
}
