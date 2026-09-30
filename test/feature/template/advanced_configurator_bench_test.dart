// 玩法配置器的渲染取证(bench)截图 —— a5-ios27-configurator 外观首遍复核的
// critic 输入。先例:#356 `out/bench-blindtaste-*`、`cc61fe1b`。
//
// 默认只跑轻量断言(任何机器都绿,不进 CI 的 golden 比对);
// 需要出图时:
//   BENCH_CAPTURE=1 flutter test test/feature/template/advanced_configurator_bench_test.dart
// 产物写到 `out/bench_adv_*.png`(随复核留档,不当回归基准)。
//
// ★ 主题必须用 `AppTheme.topicEditorLight()`:template 编辑路由在
//   `app_router.dart` 里包 `_topicEditorLight`,配置器真实长相是浅底白卡,
//   用全局暗色拍会拍出一个线上不存在的画面。

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/feature/template/advanced_game_configurator.dart';
import 'package:chengyin_app/feature/template/advanced_game_configurator_view.dart';

const Key _cardKey = Key('bench-adv-card');

bool get _capture => Platform.environment['BENCH_CAPTURE'] == '1';

Future<void> _pump(WidgetTester tester, AdvancedConfigDraft draft) async {
  await tester.binding.setSurfaceSize(const Size(390, 2600));
  final ThemeData theme = AppTheme.topicEditorLight();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: CupertinoTheme(
        data: CupertinoThemeData(
          brightness: Brightness.light,
          primaryColor: theme.colorScheme.primary,
          scaffoldBackgroundColor: theme.scaffoldBackgroundColor,
          barBackgroundColor: theme.scaffoldBackgroundColor,
        ),
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              // 复刻 template_edit_page 的 `_section('玩法配置', …)` 卡壳,
              // 让 critic 看到配置器在页面里的真实上下文。
              child: RepaintBoundary(
                key: _cardKey,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '玩法配置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AdvancedGameConfigurator(draft: draft),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  if (!_capture) return;
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(_cardKey),
  );
  final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
  final ByteData? bytes = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  File('out/bench_adv_$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

AdvancedConfigDraft _coin({bool filled = false}) {
  final AdvancedConfigDraft d = AdvancedConfigDraft();
  d.selectGame('coin');
  if (filled) {
    d.setText('coinFlip', 'kicker', '正反天注定');
    d.setNested('coinFlip', 'heads', 'label', '正面');
    d.setNested('coinFlip', 'heads', 'action', '这杯店家请');
    d.setNested('coinFlip', 'tails', 'label', '反面');
    d.setNested('coinFlip', 'tails', 'action', '自己掏');
    d.setNumber('coinFlip', 'xp', '5');
  }
  return d;
}

AdvancedConfigDraft _diceWithTimer() {
  final AdvancedConfigDraft d = AdvancedConfigDraft();
  d.selectGame('dice');
  d.setText('diceRoll', 'kicker', '一把定输赢');
  for (int i = 0; i < 6; i++) {
    d.setFace(i, '第 ${i + 1} 面要做的事');
  }
  d.setEnabled('timer', true);
  d.setNumber('timer', 'durationSeconds', '600');
  return d;
}

void main() {
  testWidgets('bench · 空态:未选玩法,只有目录', (tester) async {
    await _pump(tester, AdvancedConfigDraft());
    expect(find.text('选择玩法'), findsOneWidget);
    await _shoot(tester, 'empty');
  });

  testWidgets('bench · 错误态:抛硬币未填动作', (tester) async {
    await _pump(tester, _coin());
    expect(find.byKey(const Key('advanced-config-error')), findsOneWidget);
    await _shoot(tester, 'coin_error');
  });

  testWidgets('bench · 内容态:抛硬币配齐', (tester) async {
    await _pump(tester, _coin(filled: true));
    expect(find.byKey(const Key('advanced-config-error')), findsNothing);
    await _shoot(tester, 'coin_filled');
  });

  testWidgets('bench · 内容态:骰子六面 + 计时修饰段开启', (tester) async {
    await _pump(tester, _diceWithTimer());
    expect(find.byKey(const Key('dice-count')), findsOneWidget);
    await _shoot(tester, 'dice_timer');
  });
}
