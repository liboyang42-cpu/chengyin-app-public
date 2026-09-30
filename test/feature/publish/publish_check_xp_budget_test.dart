// 发布前检查里的 XP 预算条(`/api/topic/xp-budget`)。
//
// ★ 是否超预算**以后端的 `over`/`overBy` 为准** —— 边界与豁免规则在服务端,
//   前端自己比大小只会多一个会漂移的判据。
// ★ budget 为 0 时 `usedRatio` 是 null:不画进度条,更不写 0%。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/xp_budget.dart';
import 'package:chengyin_app/feature/publish/publish_draft_logic.dart';
import 'package:chengyin_app/feature/publish/publish_pro_sheets.dart';

Future<void> _pumpSheet(WidgetTester t, {XpBudget? budget}) async {
  await t.binding.setSurfaceSize(const Size(390, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext c) => CupertinoButton(
            onPressed: () => showPublishCheckSheet(
              c,
              blocking: const <PublishCheckItem>[],
              advisory: const <PublishCheckItem>[],
              xpBudget: budget,
            ),
            child: const Text('开'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★ 预算正常:显示 已分配/上限 与未分配会成为通关奖励', (
    WidgetTester t,
  ) async {
    await _pumpSheet(
      t,
      budget: const XpBudget(budget: 200, totalXp: 120, remain: 80),
    );
    expect(find.text('探索值(XP)'), findsOneWidget);
    expect(find.text('120 / 200'), findsOneWidget);
    expect(find.textContaining('未分配的 80 XP'), findsOneWidget);
  });

  testWidgets('★★ 超预算:用后端的 over/overBy,并说清提交会被拒', (
    WidgetTester t,
  ) async {
    await _pumpSheet(
      t,
      budget: const XpBudget(
        budget: 200,
        totalXp: 260,
        over: true,
        overBy: 60,
      ),
    );
    expect(find.textContaining('已超预算 60 XP'), findsOneWidget);
    expect(find.textContaining('拒收'), findsOneWidget);
  });

  testWidgets('★ 读不到预算就整栏不显示,不兜 0', (WidgetTester t) async {
    await _pumpSheet(t, budget: null);
    expect(find.text('探索值(XP)'), findsNothing);
    expect(find.textContaining('0 / 0'), findsNothing);
  });
}
