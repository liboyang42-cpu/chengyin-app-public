// 整屏决定类五件套(抛硬币 / 掷骰子 / 变色就点 / 弹球 / 安静挑战)的快照。
//
// ★ 为什么这五屏值得一轮基线:它们是**玩法本身**,布局被改形不会有任何测试红 ——
//   而「球撞的是不是四条边」「大字有没有被压出屏」「按钮还看得见吗」只有图看得见。
//   基线同时把玩法信号色(红/绿/深色场地)钉住:这三档颜色本身就是规则,
//   谁顺手换成主题色就等于把规则改了。
//
// ⚠️ 暂停/进行中的态不拍:那几态开着 `Timer.periodic`(物理步、限时读数),
//   快照留一个未完成的定时器 = 测完红。这里只拍「没有定时器在跑」的那几态。
//
// 更新基准图:
//   flutter test test/golden --exclude-tags needs-local-env --concurrency=1 --update-goldens

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/play/advanced/fullscreen/ball_shake_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/coin_flip_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/dice_roll_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_fullscreen_sources.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/quiet_hold_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/reaction_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';

import 'golden_theme.dart';

/// 没有传感器的来源:快照不需要摇一摇,但组件会订阅,给它一条空流 ——
/// 不注入的话会去碰真的 MethodChannel(测试环境没有实现)。
class _NoAcceleration implements PlayKitAccelerationSource {
  const _NoAcceleration();

  @override
  Stream<PlayKitAcceleration> watch() =>
      const Stream<PlayKitAcceleration>.empty();
}

void main() {
  const Size shot = Size(390, 844);

  Widget host(Widget child) => MaterialApp(
    theme: goldenTheme(),
    debugShowCheckedModeBanner: false,
    home: MediaQuery(
      data: const MediaQueryData(
        size: shot,
        padding: EdgeInsets.only(top: 47, bottom: 34),
      ),
      child: Scaffold(body: child),
    ),
  );

  PlayKitFullscreenContext context(PlayKitCard card) =>
      PlayKitFullscreenContext(card: card, enabled: true);

  PlayKitCard card(
    PlayKitKind kind, {
    String eyebrow = '',
    String detail = '',
    String selectedKey = '',
    int? maxLength,
    int durationSeconds = 0,
    List<PlayKitAction> choices = const <PlayKitAction>[],
  }) => PlayKitCard(
    kind: kind,
    title: '',
    eyebrow: eyebrow,
    detail: detail,
    selectedKey: selectedKey,
    maxLength: maxLength,
    durationSeconds: durationSeconds,
    choices: choices,
  );

  testWidgets('抛硬币 · 服务端给了反面就落反面', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitCoinFlipView(
          data: context(
            card(
              PlayKitKind.coinFlip,
              eyebrow: '抛一次，认结果',
              selectedKey: 'TAILS',
              choices: const <PlayKitAction>[
                PlayKitAction(label: '正面', action: ''),
                PlayKitAction(
                  label: '反面',
                  action: '',
                  payload: <String, Object?>{'do': '喝一杯水'},
                ),
              ],
            ),
          ),
          accelerationSource: const _NoAcceleration(),
          random: math.Random(1),
        ),
      ),
    );
    // 转完(2.2s)+ 彩片收场,才拍得到落面那一刻。
    await tester.pump(const Duration(milliseconds: 2400));
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_coinflip_tails.png'),
    );
  });

  testWidgets('掷骰子 · 两颗只报点数和', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitDiceRollView(
          data: context(
            card(
              PlayKitKind.diceRoll,
              eyebrow: '掷到几就做第几件事',
              selectedKey: '5,4',
              maxLength: 2,
              choices: const <PlayKitAction>[
                PlayKitAction(label: '学猫叫', action: ''),
                PlayKitAction(label: '喝一杯', action: ''),
                PlayKitAction(label: '唱首歌', action: ''),
                PlayKitAction(label: '讲个冷笑话', action: ''),
                PlayKitAction(label: '真心话', action: ''),
                PlayKitAction(label: '大冒险', action: ''),
              ],
            ),
          ),
          accelerationSource: const _NoAcceleration(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1000));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_diceroll_two.png'),
    );
  });

  testWidgets('变色就点 · 还没开始是红的', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitReactionView(
          data: context(
            card(
              PlayKitKind.reaction,
              eyebrow: '变色就点',
              maxLength: 3,
              durationSeconds: 400,
            ),
          ),
          random: () => 0,
        ),
      ),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_reaction_idle.png'),
    );
  });

  testWidgets('变色就点 · 绿了才点', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitReactionView(
          data: context(
            card(
              PlayKitKind.reaction,
              eyebrow: '变色就点',
              maxLength: 3,
              durationSeconds: 400,
            ),
          ),
          // 0 → 最短等待(1.4s):这一轮不等运气,只要它转绿。
          random: () => 0,
        ),
      ),
    );
    await tester.tap(find.byType(PlayKitReactionView));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_reaction_go.png'),
    );
  });

  testWidgets('弹球 · 开局前:墙是四条边,球在场上', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitBallShakeView(
          data: context(
            card(
              PlayKitKind.ballShake,
              eyebrow: '撞够 30 次',
              maxLength: 30,
              durationSeconds: 20,
            ),
          ),
          accelerationSource: const _NoAcceleration(),
          random: math.Random(5),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_ballshake_idle.png'),
    );
  });

  testWidgets('弹球 · 校准层压在场地上,底下还看得见', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitBallShakeView(
          data: context(
            card(
              PlayKitKind.ballShake,
              eyebrow: '撞够 30 次',
              maxLength: 30,
              durationSeconds: 20,
            ),
          ),
          accelerationSource: const _NoAcceleration(),
          random: math.Random(5),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_ballshake_calibrating.png'),
    );
  });

  testWidgets('安静挑战 · 开局前是绿的', (WidgetTester tester) async {
    setGoldenViewport(tester, shot);
    await tester.pumpWidget(
      host(
        PlayKitQuietHoldView(
          data: context(
            card(
              PlayKitKind.quietHold,
              eyebrow: '别出声',
              detail: '整整 15 秒，一声都不许出',
              durationSeconds: 15,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/playkit_quiethold_idle.png'),
    );
  });
}
