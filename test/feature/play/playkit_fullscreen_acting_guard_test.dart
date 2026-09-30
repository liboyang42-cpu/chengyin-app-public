import 'dart:async';

import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stickerbook_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_steps_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_walk_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/reaction_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter_test/flutter_test.dart';

/// 整屏 kit 的**在途守卫对账**(a4-playkit-acting-guard)。
///
/// 无主遗留登记的原始指控:「`reaction._onTap` 缺 acting 守卫,连点重复进判定」。
/// 逐 kit 对完真源后的结论是 **7 支全部判持平** —— 持平不是「读代码觉得没事」,
/// 这里把每支持平所依赖的那道闸钉成测试:
/// * reaction 真源(`playkit-reaction/index.js`)**没有** acting,靠 `phase` 状态机
///   + `_armed` 门防重复;App 1:1 照搬,且宿主在 acting 时把 `enabled` 掐成 false
///   (`advanced_game/index.js` 的 `acting||unknown` 双守卫在 App 侧就是 `canWrite`)。
/// * scan / bingo / timewindow 的在途闸已有负控(`playkit_misc_views_test.dart`、
///   `playkit_timewindow_view_test.dart`),此处不重复。
/// * 本文件补上真正缺的三条:reaction 的连点链路、walk 的 `syncing` 在途、
///   宿主缝的 acting 透传(字段存在但恒 false = 守卫形同虚设,必须实测)。
void main() {
  Widget host(Widget child) => MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 47, bottom: 34),
      ),
      child: Scaffold(body: child),
    ),
  );

  PlayKitCard card(
    PlayKitKind kind, {
    Map<String, Object?> kit = const <String, Object?>{},
    int? maxLength,
    int durationSeconds = 0,
  }) => PlayKitCard(
    kind: kind,
    title: '',
    detail: '',
    maxLength: maxLength,
    durationSeconds: durationSeconds,
    kit: kit,
  );

  group('reaction · 连点不重复进判定(上报原项结案)', () {
    // 走完开局 + 三轮的标准流,返回时成绩已提交、phase=done。
    Future<void> playThreeRounds(
      WidgetTester tester,
      List<PlayKitAction> actions,
    ) async {
      DateTime now = DateTime(2026, 9, 19, 12);
      await tester.pumpWidget(
        host(
          PlayKitReactionView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.reaction,
                maxLength: 3,
                durationSeconds: 400,
              ),
              enabled: true,
              onAction: actions.add,
            ),
            now: () => now,
            random: () => 0,
          ),
        ),
      );
      await tester.tap(
        find.byType(PlayKitReactionView),
      ); // 开局:发 START_CHALLENGE
      for (final int ms in <int>[240, 200, 300]) {
        await tester.pump(const Duration(milliseconds: 1400)); // 变绿
        now = now.add(Duration(milliseconds: ms));
        await tester.tap(find.byType(PlayKitReactionView)); // 落这一轮成绩
        await tester.pump();
        if (ms != 300) {
          await tester.tap(find.byType(PlayKitReactionView)); // 进下一轮
          await tester.pump();
        }
      }
    }

    int countOf(List<PlayKitAction> actions, String name) =>
        actions.where((PlayKitAction a) => a.action == name).length;

    testWidgets('★ 落定那一帧连点两下:SUBMIT_REACTION 恰一次(真源 phase 状态机等价)', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await playThreeRounds(tester, actions);
      expect(countOf(actions, 'START_CHALLENGE'), 1);
      expect(countOf(actions, 'SUBMIT_REACTION'), 1);
      final int before = actions.length;

      // 同一帧内的第二次点(tester.tap 之间不 pump,重建还没发生):
      // _measure 在调 onAction **之前**已把 _phase 置 done —— 与真源
      // `onTap` 的 `if (phase !== 'go') return` 同一条闸,重复点被状态机吞掉。
      await tester.tap(find.byType(PlayKitReactionView));
      await tester.tap(find.byType(PlayKitReactionView));
      await tester.pump();
      expect(actions.length, before, reason: 'done 相的连点不该再发任何动作');
      expect(countOf(actions, 'SUBMIT_REACTION'), 1);
    });

    testWidgets('★ 提交在途(宿主重建为 enabled=false+acting=true):连点五下零动作', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await playThreeRounds(tester, actions);
      final int before = actions.length;

      // 宿主链真值:controller 进 acting 后 playKitFullscreenContextFor 给的
      // enabled=false(= 真源 dispatcher 的 acting||unknown 双守卫)。
      await tester.pumpWidget(
        host(
          PlayKitReactionView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.reaction,
                maxLength: 3,
                durationSeconds: 400,
              ),
              enabled: false,
              acting: true,
              onAction: actions.add,
            ),
            now: () => DateTime(2026, 9, 19, 12),
            random: () => 0,
          ),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byType(PlayKitReactionView));
      }
      await tester.pump();
      expect(actions.length, before, reason: '在途期间 _onTap 首行的 enabled 闸必须吞掉一切');

      // 回执回来了(宿主回到 enabled),done 相也不再重复提交 —— 恢复的是下一局的机会,
      // 本局的判定已由服务端定。
      await tester.pumpWidget(
        host(
          PlayKitReactionView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.reaction,
                maxLength: 3,
                durationSeconds: 400,
              ),
              enabled: true,
              onAction: actions.add,
            ),
            now: () => DateTime(2026, 9, 19, 12),
            random: () => 0,
          ),
        ),
      );
      await tester.tap(find.byType(PlayKitReactionView));
      await tester.pump();
      expect(actions.length, before, reason: 'done 相恢复后同样不再发');
    });

    testWidgets('开局即被宿主挡(`!this.data.acting || unknown` 那两条回落):整屏零动作', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitReactionView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.reaction, maxLength: 3),
              enabled: false,
              acting: true,
              onAction: actions.add,
            ),
            random: () => 0,
          ),
        ),
      );
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byType(PlayKitReactionView));
        await tester.pump(const Duration(seconds: 5)); // 就算等到变绿也不放行
      }
      expect(actions, isEmpty);
    });
  });

  group('walk · 同步在途(syncing = 真源 properties.syncing)', () {
    testWidgets('同步中…连点两下:第二个同步意图发不出去', (WidgetTester tester) async {
      int syncs = 0;
      await tester.pumpWidget(
        host(
          PlayKitWalkView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.walk),
              enabled: true,
            ),
            syncAvailable: true,
            syncing: true,
            onSync: () => syncs += 1,
          ),
        ),
      );
      expect(find.text('同步中…'), findsOneWidget, reason: '真源 _paint 的同一条文案');
      // 在途那颗是置灰的(busy → onPressed=null),tap 落不上去正是结论本身。
      await tester.tap(find.text('同步中…'));
      await tester.tap(find.text('同步中…'));
      await tester.pump();
      expect(syncs, 0, reason: '真源 onCta 首行 if (this.data.syncing) return');
    });

    testWidgets('已达标但上一笔落章在途:落章也不重复发', (WidgetTester tester) async {
      int claims = 0;
      await tester.pumpWidget(
        host(
          PlayKitWalkView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.walk),
              enabled: true,
            ),
            steps: 6000,
            syncAvailable: true,
            syncing: true,
            onClaim: () => claims += 1,
          ),
        ),
      );
      await tester.tap(find.text('落章'));
      await tester.pump();
      expect(claims, 0, reason: 'busy 闸在 _cta 的 done 分支之前,和真源同序');
    });
  });

  group('stickerbook · 同分类不重发(真源 key===activeCategory 守卫)', () {
    testWidgets('点当前已选中的分类胶囊:回调零次', (WidgetTester tester) async {
      final List<String> categories = <String>[];
      await tester.pumpWidget(
        host(
          PlayKitStickerBookView(
            data: PlayKitFullscreenContext(
              card: card(PlayKitKind.stickerBook),
              enabled: true,
            ),
            activeCategory: 'all',
            categories: const <PlayKitStickerCategory>[
              PlayKitStickerCategory(key: 'all', label: '全部'),
              PlayKitStickerCategory(key: 'old', label: '老城'),
            ],
            onCategoryChanged: categories.add,
          ),
        ),
      );
      await tester.tap(find.text('全部'));
      await tester.pump();
      expect(categories, isEmpty, reason: '已选中的胶囊置灰(onPressed=null),不重发');
      await tester.tap(find.text('老城'));
      await tester.pump();
      expect(categories, <String>['old']);
    });
  });

  group('steps · 没有动作入口就没有在途窗口', () {
    testWidgets('整屏零可点控件:刷新按钮拆除后不存在可重复触发的动作', (WidgetTester tester) async {
      final List<PlayKitAction> actions = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitStepsView(
            data: PlayKitFullscreenContext(
              card: card(
                PlayKitKind.steps,
                kit: <String, Object?>{'todaySteps': 4286, 'goal': 6000},
              ),
              enabled: true,
              acting: true, // 在途与否都不该有任何区别:这一屏没有可点的东西
              onAction: actions.add,
            ),
          ),
        ),
      );
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is CupertinoButton || w is GestureDetector,
        ),
        findsNothing,
        reason:
            '真源 refreshing 守卫保护的那颗「刷新步数」在 App 是拆除的 —— '
            '再长出可点控件就是回归,这条测试是它的哨兵',
      );
      await tester.tap(find.text('/ 6,000 步'));
      await tester.pump();
      expect(actions, isEmpty);
    });
  });

  group('宿主链透传(有字段≠传得进来)', () {
    Map<String, dynamic> stateJson() => <String, dynamic>{
      'sessionId': 7,
      'activityId': 3,
      'topicId': 0,
      'nodeId': 11,
      'status': 'RUNNING',
      'version': 1,
      'score': 0,
      'readyForBase': false,
      'config': <String, dynamic>{
        'leaderboard': <String, dynamic>{'enabled': false},
        'multiplayer': <String, dynamic>{'enabled': false},
      },
      'draws': <dynamic>[],
      'playKit': <String, Object?>{},
      'multiplayer': <String, dynamic>{},
    };

    testWidgets(
      'controller 进 acting 的那一刻,缝里的 acting=true / enabled=false;回执后双双复位',
      (WidgetTester tester) async {
        final _HoldingGateway gateway = _HoldingGateway(stateJson());
        addTearDown(gateway.close);
        final AdvancedPlayController controller = AdvancedPlayController(
          gateway: gateway,
          activityId: 3,
          topicId: 0,
          nodeId: 11,
        );
        addTearDown(controller.dispose);
        await controller.start();
        expect(controller.phase, AdvancedPlayPhase.ready);

        final PlayKitCard reactCard = card(PlayKitKind.reaction, maxLength: 3);

        PlayKitFullscreenContext ctxAt(BuildContext context) =>
            playKitFullscreenContextFor(context, controller, reactCard);

        late BuildContext captured;
        await tester.pumpWidget(
          Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        );
        expect(ctxAt(captured).acting, isFalse);
        expect(ctxAt(captured).enabled, isTrue);

        // 提交在途:不 await —— gateway.action 悬着,controller 停在 acting。
        unawaited(
          controller.submit('SUBMIT_REACTION', <String, Object?>{
            'times': <int>[200],
          }),
        );
        expect(
          controller.phase,
          AdvancedPlayPhase.acting,
          reason: 'acting 是在 submit 的同步段里置上的,守卫窗口从这一帧就开始',
        );
        expect(
          ctxAt(captured).acting,
          isTrue,
          reason: '字段必须真的透传进来,不是恒 false 的摆设',
        );
        expect(
          ctxAt(captured).enabled,
          isFalse,
          reason: 'canWrite 与 acting 同生:在途即禁写',
        );

        gateway.release();
        await tester.pumpAndSettle();
        expect(controller.phase, AdvancedPlayPhase.ready);
        expect(ctxAt(captured).acting, isFalse, reason: '结束后可恢复');
        expect(ctxAt(captured).enabled, isTrue);
      },
    );
  });
}

/// 回执可手动放下的 gateway:把 controller 钉在 acting,模拟「提交在途」。
class _HoldingGateway implements AdvancedPlayGateway {
  _HoldingGateway(this.startState);

  final Map<String, dynamic> startState;
  bool _released = false;

  void release() => _released = true;
  void close() => _released = true;

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => AdvancedPlayState.fromJson(startState);

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    while (!_released) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return AdvancedPlayState.fromJson(startState);
  }

  @override
  Future<AdvancedPlayState> state(int sessionId) async =>
      AdvancedPlayState.fromJson(startState);

  @override
  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => const <AdvancedPlayLeaderboardRow>[];
}
