import 'dart:async';
import 'dart:math' as math;

import 'package:chengyin_app/feature/play/advanced/fullscreen/ball_shake_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/coin_flip_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/dice_roll_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_fullscreen_sources.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/quiet_hold_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/reaction_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 整屏决定类五件套的**行为**判据(widget 测试)。
///
/// 三条本批铁律在这一层落地,而且**都只能在这里验**:
/// 1. 结果一律由服务端定 —— 组件不许自己掷出正反/点数,只把动作抛给宿主;
/// 2. 挑战类先发 START_CHALLENGE —— 数据流顺序错一眼看不出,但服务端会判
///    「还没开始」,玩家做完那一下什么也没发生;
/// 3. 单位在宿主层换算 —— 组件报玩家读得懂的单位(见 payload 测试)。
void main() {
  Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 47, bottom: 34),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(body: child),
    ),
  );

  PlayKitCard card(
    PlayKitKind kind, {
    String eyebrow = '',
    String detail = '',
    String selectedKey = '',
    int? maxLength,
    int durationSeconds = 0,
    bool complete = false,
    List<PlayKitAction> choices = const <PlayKitAction>[],
  }) => PlayKitCard(
    kind: kind,
    title: '',
    detail: detail,
    eyebrow: eyebrow,
    selectedKey: selectedKey,
    maxLength: maxLength,
    durationSeconds: durationSeconds,
    complete: complete,
    choices: choices,
  );

  group('coinflip', () {
    testWidgets('★ 摇一摇就抛:报 FLIP_COIN 且不带参数(结果服务端算)', (WidgetTester tester) async {
      final _FakeAccelerationSource acceleration = _FakeAccelerationSource();
      addTearDown(acceleration.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitCoinFlipView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.coinFlip),
              enabled: true,
              onAction: actions.add,
            ),
            accelerationSource: acceleration,
            random: math.Random(7),
          ),
        ),
      );
      acceleration.emit(x: 10, y: 10, z: 10, atMs: 0);
      await tester.pump();
      expect(actions, hasLength(1));
      expect(actions.single.action, 'FLIP_COIN');
      expect(actions.single.payload, isEmpty, reason: '客户端说了不算');

      // 900ms 防抖窗内的第二次摇不算 —— 一次晃动不该被读成好几次。
      acceleration.emit(x: 10, y: 10, z: 10, atMs: 500);
      await tester.pump();
      expect(actions, hasLength(1));
    });

    testWidgets('面由服务端给:Reduce Motion 下直接落面,不转也不猜', (WidgetTester tester) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitCoinFlipView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.coinFlip,
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
              enabled: true,
              onAction: actions.add,
            ),
            random: math.Random(1),
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      expect(find.text('反面'), findsOneWidget);
      expect(find.text('喝一杯水'), findsOneWidget);
      expect(actions, isEmpty, reason: '落面只是把服务端给的结果演出来,不该再发一次动作');
    });
  });

  group('diceroll', () {
    testWidgets('★ 摇一摇就扔:报 ROLL_DICE 且不带参数', (WidgetTester tester) async {
      final _FakeAccelerationSource acceleration = _FakeAccelerationSource();
      addTearDown(acceleration.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitDiceRollView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.diceRoll, maxLength: 1),
              enabled: true,
              onAction: actions.add,
            ),
            accelerationSource: acceleration,
          ),
        ),
      );
      acceleration.emit(x: 10, y: 10, z: 10, atMs: 0);
      await tester.pump();
      expect(actions, hasLength(1));
      expect(actions.single.action, 'ROLL_DICE');
      expect(actions.single.payload, isEmpty);
    });

    testWidgets('两颗只报点数和,不索引六个面', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          PlayKitDiceRollView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.diceRoll,
                selectedKey: '5,4',
                maxLength: 2,
                choices: const <PlayKitAction>[
                  PlayKitAction(label: '第一件事', action: ''),
                  PlayKitAction(label: '第二件事', action: ''),
                ],
              ),
              enabled: true,
            ),
          ),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      expect(find.text('9'), findsOneWidget, reason: '两颗报和:5 + 4');
      expect(find.text('5 + 4，两颗只比大小'), findsOneWidget);
      expect(find.text('第一件事'), findsNothing, reason: '两颗没有任务,不能拿和去索引六面');
    });
  });

  group('reaction', () {
    testWidgets('★ 先开表再报成绩:START_CHALLENGE → SUBMIT_REACTION(每轮毫秒)', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitReactionView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.reaction, maxLength: 3, durationSeconds: 400),
              enabled: true,
              onAction: actions.add,
            ),
            now: () => now,
            random: () => 0,
          ),
        ),
      );
      await tester.tap(find.byType(PlayKitReactionView));
      await tester.pump();
      expect(actions, hasLength(1));
      expect(actions.single.action, 'START_CHALLENGE');
      expect(actions.single.payload['game'], 'reaction');

      // 三轮:每轮先点一下进入等待(等待 1400ms,采样为 0),变绿后再按固定毫秒点。
      const List<int> times = <int>[240, 200, 300];
      for (int i = 0; i < times.length; i++) {
        await tester.pump(const Duration(milliseconds: 1400));
        now = now.add(Duration(milliseconds: times[i]));
        await tester.tap(find.byType(PlayKitReactionView));
        await tester.pump();
        if (i < times.length - 1) {
          await tester.tap(find.byType(PlayKitReactionView));
          await tester.pump();
        }
      }
      // 开表只发一次:服务端记的是这一局的起点。
      expect(actions.where((PlayKitAction a) => a.action == 'START_CHALLENGE'), hasLength(1));
      final PlayKitAction submit = actions.last;
      expect(submit.action, 'SUBMIT_REACTION');
      expect(submit.payload['times'], <int>[240, 200, 300]);
      expect(find.text('200'), findsOneWidget, reason: '三轮取最快');
    });

    testWidgets('抢跑不判整局输,但那一轮不算成绩', (WidgetTester tester) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitReactionView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.reaction, maxLength: 3),
              enabled: true,
              onAction: actions.add,
            ),
            random: () => 0,
          ),
        ),
      );
      await tester.tap(find.byType(PlayKitReactionView));
      await tester.pump();
      // 还没变绿就点 → 抢跑。
      await tester.tap(find.byType(PlayKitReactionView));
      await tester.pump();
      expect(find.text('抢跑'), findsOneWidget);
      expect(
        actions.where((PlayKitAction a) => a.action == 'SUBMIT_REACTION'),
        isEmpty,
        reason: '抢跑的那一轮不该进成绩',
      );
    });
  });

  group('ballshake', () {
    testWidgets('★ 校准→开表→撞满报 hits', (WidgetTester tester) async {
      final _FakeAccelerationSource acceleration = _FakeAccelerationSource();
      addTearDown(acceleration.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitBallShakeView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.ballShake, maxLength: 3),
              enabled: true,
              onAction: actions.add,
            ),
            accelerationSource: acceleration,
            random: math.Random(3),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(find.text('拿成你打算玩的姿势'), findsOneWidget, reason: '零点必须校准');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(actions.single.action, 'START_CHALLENGE');
      expect(actions.single.payload['game'], 'ballShake');

      acceleration.emit(x: 0, y: 0, z: 9.8, atMs: 0);
      await tester.pump();
      acceleration.emit(x: -60, y: 0, z: 9.8, atMs: 16);
      await tester.pump();
      for (int i = 0; i < 260; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(actions, hasLength(2));
      expect(actions.last.action, 'SUBMIT_BALL_SHAKE');
      expect(actions.last.payload['hits'], greaterThanOrEqualTo(3));
      expect(find.text('撞满了'), findsOneWidget);
    });

    testWidgets('限时:倒计时数与截止判定都在(3-2-1 也数)', (WidgetTester tester) async {
      final _FakeAccelerationSource acceleration = _FakeAccelerationSource();
      addTearDown(acceleration.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitBallShakeView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.ballShake,
                maxLength: 30,
                durationSeconds: 1,
              ),
              enabled: true,
              onAction: actions.add,
            ),
            accelerationSource: acceleration,
            random: math.Random(3),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('3'), findsOneWidget, reason: '限时玩法开跑前要数 3-2-1');
      await tester.pump(const Duration(milliseconds: 620));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 620));
      await tester.pump(const Duration(milliseconds: 620));
      expect(actions.single.action, 'START_CHALLENGE');
      expect(find.text('1s'), findsOneWidget, reason: '限时条读数');

      // 一个人都没撞够:时间到判负,**不提交**。小程序那一路是台面 fail(true)
      // 转出来的,`ballshake:verdict` 在 ACTION_OF 里没有条目 —— 报一个没撞满的
      // 成绩上去只会把这一格标成做过了,而这一关本来可重来。
      await tester.pump(const Duration(milliseconds: 1100));
      expect(actions, hasLength(1), reason: '超时只判负,不发 SUBMIT_BALL_SHAKE');
      expect(find.text('时间到，撞了 0 次'), findsOneWidget);
    });

    testWidgets('Reduce Motion:不数 3-2-1,校准完直接开跑', (WidgetTester tester) async {
      final _FakeAccelerationSource acceleration = _FakeAccelerationSource();
      addTearDown(acceleration.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitBallShakeView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.ballShake,
                maxLength: 30,
                durationSeconds: 12,
              ),
              enabled: true,
              onAction: actions.add,
            ),
            accelerationSource: acceleration,
            random: math.Random(3),
          ),
          reduceMotion: true,
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('3'), findsNothing, reason: '减动效:数字跳动本身就是动效,不数');
      expect(actions.single.action, 'START_CHALLENGE');
    });
  });

  group('quiethold', () {
    testWidgets('★ 麦克风拿不到就明说,不假装在听', (WidgetTester tester) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitQuietHoldView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.quietHold, durationSeconds: 15),
              enabled: true,
              onAction: actions.add,
            ),
            soundSource: _DeniedSoundSource(),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(actions, isEmpty, reason: '麦克风都没打开,不该开表');
      expect(find.textContaining('麦克风没打开'), findsOneWidget);
    });

    testWidgets('★ 校准→开表→安静满 N 秒报 heldSeconds(秒)', (WidgetTester tester) async {
      final _FakeSoundSource source = _FakeSoundSource();
      addTearDown(source.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitQuietHoldView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.quietHold, durationSeconds: 2),
              enabled: true,
              onAction: actions.add,
            ),
            soundSource: source,
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(find.text('先听一下这儿有多吵'), findsOneWidget);
      // 校准采样(80 分位从这里出)。
      source.emit(0.03);
      source.emit(0.05);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));
      expect(actions.single.action, 'START_CHALLENGE');
      expect(actions.single.payload['game'], 'quietHold');

      for (int i = 0; i < 20; i++) {
        now = now.add(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(actions.last.action, 'SUBMIT_QUIET_HOLD');
      expect(actions.last.payload['heldSeconds'], 2);
      expect(find.textContaining('一声没出'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(source.stopCount, greaterThan(0), reason: '录音用完即弃');
    });

    testWidgets('★ 过线判输:成绩照样报上去,不就地清零重来', (WidgetTester tester) async {
      final _FakeSoundSource source = _FakeSoundSource();
      addTearDown(source.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitQuietHoldView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.quietHold, durationSeconds: 15),
              enabled: true,
              onAction: actions.add,
            ),
            soundSource: source,
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      source.emit(0.05);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));

      now = now.add(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      source.emit(0.9);
      await tester.pump();
      now = now.add(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(actions.last.action, 'SUBMIT_QUIET_HOLD');
      expect(find.textContaining('出了一声'), findsOneWidget);
    });

    testWidgets('切走了这一局作废:不提交,也不接着算秒', (WidgetTester tester) async {
      // 先对齐绑定态(不置 resumed 的话这一跳会被当成冷启动直跳)。
      // ⚠️ 用 inactive 不用 paused:paused 会关掉整个 binding 的帧调度,
      //    界面根本不会再重建,断言就只能看内部状态而不是「屏幕上写了什么」。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final _FakeSoundSource source = _FakeSoundSource();
      addTearDown(source.close);
      final List<PlayKitAction> actions = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitQuietHoldView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.quietHold, durationSeconds: 15),
              enabled: true,
              onAction: actions.add,
            ),
            soundSource: source,
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      source.emit(0.05);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2100));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.textContaining('刚才切走了'), findsOneWidget);
      expect(
        actions.where((PlayKitAction a) => a.action == 'SUBMIT_QUIET_HOLD'),
        isEmpty,
        reason: '熄屏那几秒根本没在听,不能算成绩',
      );
    });
  });
}

class _FakeAccelerationSource implements PlayKitAccelerationSource {
  final StreamController<PlayKitAcceleration> _controller =
      StreamController<PlayKitAcceleration>.broadcast();

  @override
  Stream<PlayKitAcceleration> watch() => _controller.stream;

  void emit({
    required double x,
    required double y,
    required double z,
    int atMs = 0,
  }) {
    _controller.add(
      PlayKitAcceleration(
        x: x,
        y: y,
        z: z,
        at: Duration(milliseconds: atMs),
      ),
    );
  }

  Future<void> close() => _controller.close();
}

class _FakeSoundSource implements PlayKitSoundLevelSource {
  final StreamController<double> _controller =
      StreamController<double>.broadcast();
  int stopCount = 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Stream<double> watch() => _controller.stream;

  void emit(double level) => _controller.add(level);

  Future<void> close() => _controller.close();
}

class _DeniedSoundSource implements PlayKitSoundLevelSource {
  @override
  Future<void> start() async =>
      throw const PlayKitMicUnavailable('麦克风没打开');

  @override
  Future<void> stop() async {}

  @override
  Stream<double> watch() => const Stream<double>.empty();
}
