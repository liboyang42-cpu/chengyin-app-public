import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/npc/widgets/npc_bubble.dart';
import 'package:chengyin_app/feature/square/square_compose_page.dart';

void main() {
  test('商家普通点击使用 CupertinoButton，不保留裸 GestureDetector', () {
    for (final String path in <String>[
      'lib/feature/merchant/merchant_marketing_page.dart',
      'lib/feature/merchant/merchant_discover_page.dart',
      'lib/feature/merchant/merchant_chapters_page.dart',
      'lib/feature/merchant/merchant_settlement_view.dart',
      'lib/feature/merchant/merchant_ledger_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoButton('), reason: path);
      expect(source, isNot(contains('GestureDetector(')), reason: path);
    }
  });

  testWidgets('可点击 NPC 冒泡是具名的 VoiceOver 按钮', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NpcBubble(
            line: const NpcLine(profileId: 7, name: '阿岩', line: '到了'),
            onTap: () => taps++,
          ),
        ),
      ),
    );

    final Finder action = find.bySemanticsLabel('阿岩，到了');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);

    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        nodeId: tester.getSemantics(action).id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(taps, 1);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });

  testWidgets('俱乐部动态卡只在有打开落点时暴露按钮动作', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var opens = 0;
    const ClubPost post = ClubPost(
      id: 1,
      clubId: 9,
      nickname: '阿兰',
      content: '周六六点集合',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ClubPostTile(post: post, onOpenClub: () => opens++),
          ),
        ),
      ),
    );

    final Finder action = find.bySemanticsLabel('打开这条动态所属的俱乐部');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);

    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        nodeId: tester.getSemantics(action).id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(opens, 1);
    semantics.dispose();
  });

  testWidgets('已选图片删除动作有明确名称和可执行语义', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var removals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareComposeThumb(
            url: 'https://example.invalid/a.png',
            onRemove: () => removals++,
          ),
        ),
      ),
    );

    final Finder action = find.bySemanticsLabel('删除图片');
    expect(action, findsOneWidget);
    final data = tester.getSemantics(action).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);

    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        nodeId: tester.getSemantics(action).id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();
    expect(removals, 1);
    semantics.dispose();
  });
}
