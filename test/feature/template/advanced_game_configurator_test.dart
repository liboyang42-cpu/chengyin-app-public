import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/template/advanced_game_configurator.dart';
import 'package:chengyin_app/feature/template/advanced_game_configurator_view.dart';

Future<void> _pump(WidgetTester tester, AdvancedConfigDraft draft) async {
  await tester.binding.setSurfaceSize(const Size(390, 2000));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdvancedGameConfigurator(draft: draft),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _editable(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

void main() {
  group('高级玩法配置器 · 决定类', () {
    testWidgets('未选玩法:九宫格在,无配置面板、无错误(空态)', (tester) async {
      final draft = AdvancedConfigDraft();
      await _pump(tester, draft);
      expect(find.byKey(const Key('game-chip-coin')), findsOneWidget);
      expect(find.byKey(const ValueKey('panel-coin')), findsNothing);
      expect(find.byKey(const Key('advanced-config-error')), findsNothing);
    });

    testWidgets('选中抛硬币但未填动作:出错误文案、序列化挡住(错误态)', (tester) async {
      final draft = AdvancedConfigDraft();
      await _pump(tester, draft);
      await tester.tap(find.byKey(const Key('game-chip-coin')));
      await tester.pump();
      expect(find.byKey(const ValueKey('panel-coin')), findsOneWidget);
      expect(draft.gameKey, 'coin');
      expect(find.byKey(const Key('advanced-config-error')), findsOneWidget);
      expect(find.text('正面要做什么不能为空'), findsOneWidget);
      // 校验不过时不写脏数据。
      expect(draft.serialize(), '');
    });

    testWidgets('补齐正反面动作:错误消失并产出可落库 JSON(内容态)', (tester) async {
      final draft = AdvancedConfigDraft();
      await _pump(tester, draft);
      await tester.tap(find.byKey(const Key('game-chip-coin')));
      await tester.pump();
      await tester.enterText(_editable('coinFlip-heads-action'), '这杯店家请');
      await tester.enterText(_editable('coinFlip-tails-action'), '自己掏');
      await tester.pump();
      expect(find.byKey(const Key('advanced-config-error')), findsNothing);
      final json = draft.serialize();
      expect(json, contains('coinFlip'));
      expect(json, contains('这杯店家请'));
      expect(json, contains('自己掏'));
    });

    testWidgets('序列化落库 → 反序列化识别回抛硬币(与玩家侧同一份 JSON)', (tester) async {
      final draft = AdvancedConfigDraft();
      await _pump(tester, draft);
      await tester.tap(find.byKey(const Key('game-chip-coin')));
      await tester.pump();
      await tester.enterText(_editable('coinFlip-heads-action'), 'A');
      await tester.enterText(_editable('coinFlip-tails-action'), 'B');
      await tester.pump();
      final restored = AdvancedConfigDraft.fromJson(draft.serialize());
      expect(restored.gameKey, 'coin');
      expect(restored.serialize(), draft.serialize());
    });
  });

  testWidgets('未接面板的玩法:仍显示真源 sub,但禁用不可选,不给假输入框', (tester) async {
    final draft = AdvancedConfigDraft();
    await _pump(tester, draft);
    // qaPick(选项问答)本批未接面板。
    expect(find.text('2-4 个选项里选一个 · 闭眼盲品也是这套'), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-chip-qaPick')));
    await tester.pump();
    expect(draft.gameKey, '');
    expect(find.byKey(const ValueKey('panel-qaPick')), findsNothing);
  });

  testWidgets('限时修饰段:打开开关才出现时长输入', (tester) async {
    final draft = AdvancedConfigDraft();
    await _pump(tester, draft);
    expect(find.byKey(const ValueKey('timer-durationSeconds')), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('modifier-timer-switch')),
        matching: find.byType(CupertinoSwitch),
      ),
    );
    await tester.pump();
    expect(draft.isEnabled('timer'), isTrue);
    expect(find.byKey(const ValueKey('timer-durationSeconds')), findsOneWidget);
  });
}
