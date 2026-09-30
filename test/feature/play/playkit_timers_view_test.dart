import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_countdown_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_game_timer_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stickerbook_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stopwatch_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_timer_logic.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_walk_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 计时/传感器族五件的**行为**门禁。
///
/// 这里钉的是「少一条不会报错、只是玩家做完那一下什么也没发生」的那类东西:
/// 动作名、载荷字段、发没发、发的顺序、以及**负控**(不该发的时候一条都不许发)。
///
/// 时钟一律注入(`now:`),不依赖真实时间 —— 设备时钟玩家改得动,而判定在服务端,
/// 所以客户端这边能测的只有「读数怎么走」和「什么时候把动作抛给宿主」。
void main() {
  final List<MethodCall> platformCalls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    platformCalls.clear();
  });

  int haptics() => platformCalls
      .where((call) => call.method == 'HapticFeedback.vibrate')
      .length;

  Widget host(Widget child, {bool disableAnimations = false}) {
    return CupertinoApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 780),
          disableAnimations: disableAnimations,
        ),
        child: child,
      ),
    );
  }

  PlayKitCard card(
    PlayKitKind kind, {
    String title = '',
    String detail = '',
    String eyebrow = '',
    String hint = '',
    int durationSeconds = 0,
    int? maxLength,
    bool started = false,
    bool complete = false,
    PlayKitAction? primaryAction,
    Map<String, Object?> kit = const <String, Object?>{},
  }) {
    return PlayKitCard(
      kind: kind,
      title: title,
      detail: detail,
      eyebrow: eyebrow,
      hint: hint,
      durationSeconds: durationSeconds,
      maxLength: maxLength,
      started: started,
      complete: complete,
      primaryAction: primaryAction,
      kit: kit,
    );
  }

  PlayKitFullscreenContext context(
    PlayKitCard value,
    List<PlayKitAction> log, {
    bool enabled = true,
  }) {
    return PlayKitFullscreenContext(
      card: value,
      enabled: enabled,
      onAction: log.add,
    );
  }

  group('countdown', () {
    testWidgets('开始发 START_CHALLENGE{game:countdown},到点发 SUBMIT_COUNTDOWN{}', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitCountdownView(
            data: context(
              card(
                PlayKitKind.countdown,
                title: '倒计时',
                durationSeconds: 90,
                hint: '到点了',
              ),
              log,
            ),
            now: () => now,
          ),
        ),
      );
      expect(log, isEmpty, reason: '没点开始之前,一条动作都不许发');

      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(log.map((PlayKitAction a) => a.action).toList(), <String>[
        'START_CHALLENGE',
      ]);
      // 服务端只认这个驼峰名;少了它,提交会被判成「还没开始」
      expect(log.single.payload, <String, Object?>{'game': 'countdown'});
      expect(find.text('走着呢'), findsOneWidget);

      await tester.pump(kCountdownTickInterval);
      expect(log.length, 1, reason: '没到点不许提前提交');

      now = now.add(const Duration(seconds: 90));
      await tester.pump(kCountdownTickInterval);
      expect(log.map((PlayKitAction a) => a.action).toList(), <String>[
        'START_CHALLENGE',
        'SUBMIT_COUNTDOWN',
      ]);
      // 结果服务端算,客户端不带参数
      expect(log.last.payload, isEmpty);
      // 墨层 + 油面层是同一份文字画两遍(真源 mix-blend-mode: difference 的等价做法)
      expect(find.text('到点了'), findsNWidgets(2));
      expect(find.text('再来一次'), findsOneWidget);
    });

    testWidgets('每拍重新对时,不做 seconds 累加', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitCountdownView(
            data: context(
              card(PlayKitKind.countdown, durationSeconds: 90),
              log,
            ),
            now: () => now,
          ),
        ),
      );
      expect(
        find.text('01:30'),
        findsNWidgets(2), // 墨层 + 油面层两层文字,值是同一份
        reason: '准备时显示总时长',
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      // 只走一拍,但真实时间已经过去 30 秒:读数必须按**对时**走,不是 89
      now = now.add(const Duration(seconds: 30));
      await tester.pump(kCountdownTickInterval);
      expect(
        find.text('01:00'),
        findsNWidgets(2),
        reason: '按对时走(不是 89 秒的累减);两层是同一份文字的重绘',
      );
    });

    testWidgets('到点那一下有触感', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitCountdownView(
            data: context(card(PlayKitKind.countdown, durationSeconds: 5), log),
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(haptics(), 0, reason: '开跑那一下不震 —— 真源只在到点震');
      now = now.add(const Duration(seconds: 5));
      await tester.pump(kCountdownTickInterval);
      expect(haptics(), 1);
    });

    testWidgets('负控:开了减弱动态效果,到点不震(触感也是动效)', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitCountdownView(
            data: context(card(PlayKitKind.countdown, durationSeconds: 5), log),
            now: () => now,
          ),
          disableAnimations: true,
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      now = now.add(const Duration(seconds: 5));
      await tester.pump(kCountdownTickInterval);
      expect(log.last.action, 'SUBMIT_COUNTDOWN', reason: '功能照走');
      expect(haptics(), 0, reason: '减动效下不震(真源 motion.haptic 同口径)');
    });

    testWidgets('负控:enabled=false 时点不动,也不发开始', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitCountdownView(
            data: context(
              card(PlayKitKind.countdown, durationSeconds: 30),
              log,
              enabled: false,
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(log, isEmpty);
    });
  });

  group('stopwatch', () {
    PlayKitCard stopwatchCard({
      int target = 10,
      int toleranceMs = 300,
      int? tries,
    }) => card(
      PlayKitKind.stopwatch,
      title: '精准停表',
      durationSeconds: target,
      maxLength: toleranceMs,
      kit: tries == null
          ? const <String, Object?>{}
          : <String, Object?>{'tries': tries},
    );

    Future<void> countIn(WidgetTester tester) async {
      await tester.pump(kCountInTickInterval);
      await tester.pump(kCountInTickInterval);
      await tester.pump(kCountInTickInterval);
    }

    testWidgets('先数 3-2-1 再开表;开表发 START_CHALLENGE{game:stopwatch}', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(PlayKitStopwatchView(data: context(stopwatchCard(), log))),
      );
      expect(find.text('目标'), findsOneWidget);
      expect(find.text('10.00'), findsOneWidget);
      expect(find.text('±0.30'), findsOneWidget);

      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(log, isEmpty, reason: '数完才开表:数之前不许发 START_CHALLENGE');

      await countIn(tester);
      expect(log.map((PlayKitAction a) => a.action).toList(), <String>[
        'START_CHALLENGE',
      ]);
      expect(log.single.payload, <String, Object?>{'game': 'stopwatch'});
      expect(find.text('第 1 局'), findsOneWidget);
    });

    testWidgets('负控:开了减弱动态效果就不数,直接开跑', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitStopwatchView(data: context(stopwatchCard(), log)),
          disableAnimations: true,
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(log.single.action, 'START_CHALLENGE');
      expect(find.text('第 1 局'), findsOneWidget);
    });

    testWidgets('开跑 1 秒后藏数字;停表发 SUBMIT_STOPWATCH{stoppedMs}', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitStopwatchView(
            data: context(stopwatchCard(), log),
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      await countIn(tester);
      now = now.add(const Duration(milliseconds: 1234));
      await tester.pump(kStopwatchTickInterval);
      expect(find.text('—— · ——'), findsOneWidget, reason: '盲停:走动的数字要藏起来');

      await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
      await tester.pump();
      expect(log.last.action, 'SUBMIT_STOPWATCH');
      expect(log.last.payload, <String, Object?>{'stoppedMs': 1234});
      expect(haptics(), 1, reason: '「做成了」= 按下停那一刻');
    });

    testWidgets('负控:没开表 / 暂停中,点屏幕都不提交', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitStopwatchView(
            data: context(stopwatchCard(), log),
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      await countIn(tester);
      expect(log.length, 1);
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill));
      await tester.pump();
      expect(find.text('已暂停'), findsOneWidget);
      await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
      await tester.pump();
      expect(
        log.where((PlayKitAction a) => a.action == 'SUBMIT_STOPWATCH').length,
        0,
        reason: '暂停中不接受停 —— 那等于把表停在自己挑的一刻',
      );
    });

    testWidgets('忘停:超目标 30 秒这一局作废(不发提交,回准备屏)', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitStopwatchView(
            data: context(stopwatchCard(), log),
            now: () => now,
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pump();
      await countIn(tester);
      now = now.add(const Duration(seconds: 41));
      await tester.pump(kStopwatchTickInterval);
      expect(find.text('开始'), findsOneWidget, reason: '回到准备屏');
      expect(
        log.where((PlayKitAction a) => a.action == 'SUBMIT_STOPWATCH').length,
        0,
      );
    });

    testWidgets('tries:错满就收摊 —— 次数看得见,用尽后点屏幕不再开下一局', (
      WidgetTester tester,
    ) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitStopwatchView(
            data: context(stopwatchCard(tries: 2), log),
            now: () => now,
          ),
        ),
      );
      expect(
        find.text('可以错 2 次'),
        findsOneWidget,
        reason: '开跑前就该知道自己能错几次(真源页眉那两颗圆点)',
      );

      await tester.tap(find.text('开始'));
      await tester.pump();
      await countIn(tester);
      // 读数在 AnimatedSwitcher 里换场:同一 key 的新旧两半会短暂并存,
      // 每一拍之后先把换场放完,否则第二局起就撞成「Duplicate keys」。
      Future<void> flush() => tester.pump(CyMotion.fadeSwap);
      Future<void> stopOnce() async {
        await flush();
        now = now.add(const Duration(milliseconds: 1234));
        await tester.pump(kStopwatchTickInterval);
        // 差 8.77 秒 = 一次没停准
        await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
        await flush();
      }

      await stopOnce();
      expect(find.text('还能错 1 次'), findsOneWidget);
      expect(find.text('失败'), findsNothing, reason: '还剩一次就还没输');
      // 再点一下 = 开下一局(真源 `over` 相那一下)
      await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
      await tester.pump();
      expect(
        log.where((PlayKitAction a) => a.action == 'START_CHALLENGE').length,
        2,
      );

      await stopOnce();
      expect(find.text('还能错 0 次'), findsNothing);
      expect(find.text('次数用完了'), findsOneWidget);
      expect(find.text('失败'), findsOneWidget);
      final int sent = log.length;

      await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
      await tester.pump();
      expect(log.length, sent, reason: '用尽后再发一条会被服务端判成「这一局已经交过了」');
    });

    testWidgets('负控:没配 tries = 不限次,屏上一个次数痕迹都不许有', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      DateTime now = DateTime(2026, 9, 17, 12);
      await tester.pumpWidget(
        host(
          PlayKitStopwatchView(
            data: context(stopwatchCard(), log),
            now: () => now,
          ),
        ),
      );
      expect(find.textContaining('次'), findsNothing);

      await tester.tap(find.text('开始'));
      await tester.pump();
      await countIn(tester);
      now = now.add(const Duration(milliseconds: 1234));
      await tester.pump(kStopwatchTickInterval);
      await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
      await tester.pump(CyMotion.fadeSwap);
      expect(find.textContaining('还能错'), findsNothing);
      expect(find.textContaining('点屏幕再来一局'), findsOneWidget);

      await tester.tap(find.text('目标 10.00 秒 · 容差 ±0.30'));
      await tester.pump();
      expect(
        log.where((PlayKitAction a) => a.action == 'START_CHALLENGE').length,
        2,
        reason: '不限次的老模板一局都不该被挡',
      );
    });
  });

  group('walk', () {
    testWidgets('负控:没有步数来源时 CTA 禁用,点了不发同步', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      int syncs = 0;
      await tester.pumpWidget(
        host(
          PlayKitWalkView(
            data: context(card(PlayKitKind.walk, title: '低碳行动'), log),
            onSync: () => syncs += 1,
          ),
        ),
      );
      expect(find.text('同步微信运动'), findsOneWidget, reason: '文案与真源逐字一致');
      expect(find.textContaining('App 端没有微信运动这条链路'), findsOneWidget);
      await tester.tap(find.text('同步微信运动'));
      await tester.pump();
      expect(syncs, 0, reason: '没有来源就不许假装同步');
      expect(log, isEmpty);
    });

    testWidgets('有来源时同步发得出去;归零落章', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      int syncs = 0;
      int claims = 0;
      await tester.pumpWidget(
        host(
          PlayKitWalkView(
            data: context(card(PlayKitKind.walk), log),
            steps: 0,
            syncAvailable: true,
            onSync: () => syncs += 1,
            onClaim: () => claims += 1,
          ),
        ),
      );
      await tester.tap(find.text('同步微信运动'));
      await tester.pump();
      expect(syncs, 1);

      await tester.pumpWidget(
        host(
          PlayKitWalkView(
            data: context(card(PlayKitKind.walk), log),
            steps: 6000,
            syncAvailable: true,
            onSync: () => syncs += 1,
            onClaim: () => claims += 1,
          ),
        ),
      );
      expect(find.text('6,000'), findsWidgets);
      expect(find.text('0.48 kg'), findsOneWidget, reason: '6000 步 → 0.48 kg');
      await tester.tap(find.text('落章'));
      await tester.pump();
      expect(claims, 1);
    });

    testWidgets('每格 500 步、目标对齐到整格;减动效下不震', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      final List<int> goals = <int>[];
      await tester.pumpWidget(
        host(
          PlayKitWalkView(
            data: context(card(PlayKitKind.walk, maxLength: 6000), log),
            onGoalChanged: goals.add,
          ),
          disableAnimations: true,
        ),
      );
      await tester.tap(find.byIcon(CupertinoIcons.plus));
      await tester.pump();
      expect(goals, <int>[6500]);
      expect(haptics(), 0, reason: '减动效下不震');
      await tester.tap(find.byIcon(CupertinoIcons.plus));
      await tester.pump();
      expect(goals, <int>[6500, 7000]);
    });
  });

  group('gameTimer', () {
    testWidgets('剩余秒由宿主推,组件不自己跑秒;CTA 回调带 state', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      final List<PlayKitGameTimerState> taps = <PlayKitGameTimerState>[];
      await tester.pumpWidget(
        host(
          PlayKitGameTimerView(
            data: context(
              card(
                PlayKitKind.gameTimer,
                title: '第 3 题',
                detail: '选出店主最推荐的一支',
                eyebrow: '限时挑战',
                durationSeconds: 60,
                primaryAction: const PlayKitAction(
                  label: '提交答案',
                  action: 'SUBMIT_QA',
                  payload: <String, Object?>{'optionId': 'a'},
                ),
              ),
              log,
            ),
            state: PlayKitGameTimerState.critical,
            remainingSeconds: 42,
            statusLabel: '还剩 42 秒',
            chips: const <String>['第 3 题', '单选'],
            onCta: taps.add,
          ),
        ),
      );
      expect(find.text('00:42'), findsOneWidget);
      expect(find.text('还剩 42 秒'), findsOneWidget);
      expect(find.text('单选'), findsOneWidget);

      // 组件不自己跑秒:时间过去 5 秒,屏上读数还是服务端给的 42
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('00:42'), findsOneWidget);

      await tester.tap(find.text('提交答案'));
      await tester.pump();
      expect(taps, <PlayKitGameTimerState>[PlayKitGameTimerState.critical]);
      expect(log, isEmpty, reason: '宿主给了 onCta 就不该再走卡片动作');
    });

    testWidgets('没给回调时,把卡片自带的主动作原样转发', (WidgetTester tester) async {
      final List<PlayKitAction> log = <PlayKitAction>[];
      await tester.pumpWidget(
        host(
          PlayKitGameTimerView(
            data: context(
              card(
                PlayKitKind.gameTimer,
                title: '第 4 题',
                durationSeconds: 30,
                primaryAction: const PlayKitAction(
                  label: '提交答案',
                  action: 'SUBMIT_QA',
                  payload: <String, Object?>{'input': 'x'},
                ),
              ),
              log,
            ),
            remainingSeconds: 10,
          ),
        ),
      );
      await tester.tap(find.text('提交答案'));
      await tester.pump();
      expect(log.single.action, 'SUBMIT_QA');
      expect(log.single.payload['input'], 'x');
    });
  });

  group('stickerBook', () {
    testWidgets('空槽点不动也不震;已收集点得动;切分类不震', (WidgetTester tester) async {
      final List<int> tapped = <int>[];
      final List<String> categories = <String>[];
      await tester.pumpWidget(
        host(
          PlayKitStickerBookView(
            data: context(
              card(PlayKitKind.stickerBook, title: '我的城市贴纸'),
              <PlayKitAction>[],
            ),
            total: 3,
            categories: const <PlayKitStickerCategory>[
              PlayKitStickerCategory(key: 'all', label: '全部'),
              PlayKitStickerCategory(key: 'old', label: '老城'),
            ],
            activeCategory: 'all',
            stickers: const <PlayKitSticker>[
              PlayKitSticker(id: 7, label: '晨光', isNew: true),
            ],
            lockedCount: 2,
            hint: '拍下这座城市,就会长出一张贴纸。',
            onStickerTap: tapped.add,
            onCategoryChanged: categories.add,
          ),
        ),
      );
      expect(find.text('?'), findsNWidgets(2));
      expect(find.text('新!'), findsOneWidget);
      await tester.tap(find.text('?').first);
      await tester.pump();
      expect(tapped, isEmpty, reason: '未解锁的格子没有 id,点了不该有任何反馈');
      expect(haptics(), 0);

      await tester.tap(find.text('晨光'));
      await tester.pump();
      expect(tapped, <int>[7]);
      expect(haptics(), 1);

      await tester.tap(find.text('老城'));
      await tester.pump();
      expect(
        categories,
        <String>['old'], // 回调给分类 key,与 activeCategory 同一套
        reason: '切分类要把 key 交回宿主,不能把展示用的 label 当标识',
      );
      expect(haptics(), 1, reason: '切分类是浏览,不震');
    });
  });

  group('注册表与投影', () {
    test('五件 kind 都登记进整屏族注册表;sheet 那两件不进 kFullscreenPlayKinds', () {
      const List<PlayKitKind> mine = <PlayKitKind>[
        PlayKitKind.countdown,
        PlayKitKind.stopwatch,
        PlayKitKind.walk,
        PlayKitKind.gameTimer,
        PlayKitKind.stickerBook,
      ];
      for (final PlayKitKind kind in mine) {
        expect(
          kPlayKitFullscreenBuilders.containsKey(kind),
          isTrue,
          reason: '$kind 没登记 —— 宿主会当「App 还没有这个玩法」,不崩但也不出现',
        );
      }
      // 真源是 cy-play-stage(整屏)的三件
      expect(
        kFullscreenPlayKinds,
        containsAll(<PlayKitKind>[
          PlayKitKind.countdown,
          PlayKitKind.stopwatch,
          PlayKitKind.walk,
        ]),
      );
      // 真源是 cy-sheet(半屏)的两件:**不许**混进「必须占满屏」那一集合
      expect(
        kFullscreenPlayKinds.contains(PlayKitKind.gameTimer),
        isFalse,
        reason: 'game-timer 的 usingComponents 是 cy-sheet',
      );
      expect(
        kFullscreenPlayKinds.contains(PlayKitKind.stickerBook),
        isFalse,
        reason: 'playkit-stickerbook 的 usingComponents 是 cy-sheet',
      );
    });

    testWidgets('注册表里五件都能 build 出东西(不返回 null)', (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (BuildContext inner) {
              ctx = inner;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      const List<PlayKitKind> mine = <PlayKitKind>[
        PlayKitKind.countdown,
        PlayKitKind.stopwatch,
        PlayKitKind.walk,
        PlayKitKind.gameTimer,
        PlayKitKind.stickerBook,
      ];
      for (final PlayKitKind kind in mine) {
        final Widget? built = buildPlayKitFullscreen(
          ctx,
          PlayKitFullscreenContext(
            card: card(kind, title: 'x', durationSeconds: 30),
            enabled: true,
          ),
        );
        expect(built, isNotNull, reason: '$kind 应该能 build');
      }
    });

    test('投影:countdown / stopwatch 两个段名落进卡片,槽位与组件读的一致', () {
      final List<PlayKitCard> countdown = projectPlayKit(<String, Object?>{
        'countdown': <String, Object?>{
          'kicker': '醒酒',
          'seconds': 90,
          'doneText': '到点了,慢慢来',
        },
      });
      expect(countdown.single.kind, PlayKitKind.countdown);
      expect(countdown.single.eyebrow, '醒酒');
      expect(countdown.single.durationSeconds, 90);
      expect(countdown.single.hint, '到点了,慢慢来');

      final List<PlayKitCard> stopwatch = projectPlayKit(<String, Object?>{
        'stopwatch': <String, Object?>{
          'kicker': '',
          'targetSeconds': 10,
          'toleranceMs': 300,
          'tries': 3,
        },
      });
      expect(stopwatch.single.kind, PlayKitKind.stopwatch);
      expect(stopwatch.single.title, '精准停表', reason: '商家没填就落到原型那句');
      expect(stopwatch.single.durationSeconds, 10);
      expect(stopwatch.single.maxLength, 300, reason: '容差毫秒走通用数值槽');
    });

    test('负控:本地 kind 不造服务端段名', () {
      expect(kPlayKitSegmentKinds.containsKey('walk'), isFalse);
      expect(kPlayKitSegmentKinds.containsKey('stickerBook'), isFalse);
      expect(kPlayKitSegmentKinds.containsKey('gameTimer'), isFalse);
      // 就算有人把本地 kind 塞进段数据,也不该被投影成卡片
      expect(
        projectPlayKit(<String, Object?>{
          'walk': <String, Object?>{'goal': 6000},
          'stickerBook': <String, Object?>{'total': 3},
          'gameTimer': <String, Object?>{'seconds': 30},
        }),
        isEmpty,
      );
    });
  });
}
