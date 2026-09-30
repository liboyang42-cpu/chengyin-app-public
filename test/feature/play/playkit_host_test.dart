import 'dart:io';

import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_sheet.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;
import 'package:chengyin_app/feature/play/advanced/advanced_playkit_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/ball_shake_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/coin_flip_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/dice_roll_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_countdown_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_bingo_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_daily_sign_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_game_timer_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_predict_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_prefab_data.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_prefab_views.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_data.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_random_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_scan_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_silent_order_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_steps_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/quiet_hold_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/reaction_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_views.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stickerbook_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_stopwatch_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_timewindow_view.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_walk_view.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 玩法**呈现层**的门禁:三个批次做出来的组件靠这一层才到得了玩家手里。
///
/// 没有这一层时,组件在仓里零调用 —— 不报错、不崩,只是**永远弹不出来**。
/// 所以这里钉的是「什么时候走呈现层、用哪种壳、动作有没有原样转出去」,
/// 以及两个负控:未登记的 kind 必须继续回落,8 个 v5.1 半屏 kind 行为不变。
void main() {
  Map<String, dynamic> stateJson({
    Map<String, Object?> playKit = const <String, Object?>{},
  }) => <String, dynamic>{
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
    'playKit': playKit,
    'multiplayer': <String, dynamic>{},
  };

  AdvancedPlayController controllerFor(_FakeGateway gateway) {
    final AdvancedPlayController controller = AdvancedPlayController(
      gateway: gateway,
      activityId: 3,
      topicId: 0,
      nodeId: 11,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<AdvancedPlayController> started(Map<String, Object?> playKit) async {
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(playKit: playKit),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();
    return controller;
  }

  Widget host(AdvancedPlayController controller) => CupertinoApp(
    home: AdvancedPlaySheet(
      controller: controller,
      title: '玩法',
      onReadyForBase: () {},
      audio: _SilentAudio(),
    ),
  );

  const Map<String, Object?> qaSegment = <String, Object?>{
    'qa': <String, Object?>{
      'mode': 'PICK',
      'title': '这座桥建于哪一年?',
      'options': <Object?>[
        <String, Object?>{'id': 'a', 'label': '1908'},
        <String, Object?>{'id': 'b', 'label': '1912'},
      ],
    },
  };

  testWidgets('整屏族:进得去、动作原样转发、退得出来', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(playKit: qaSegment),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    // 呈现层不在 sheet 里内联画:那一格只给入口(整屏压在半屏里「判定区」就不成立)
    expect(
      find.byType(PlayKitQaView),
      findsNothing,
      reason: '没点之前不许把整屏组件塞进 sheet',
    );
    expect(find.text('进入玩法'), findsOneWidget);

    await tester.tap(find.text('进入玩法'));
    await tester.pumpAndSettle();
    expect(
      find.byType(PlayKitFullscreenSurface),
      findsOneWidget,
      reason: '整屏族占满屏',
    );
    expect(find.byType(PlayKitQaView), findsOneWidget);

    // 动作与载荷一个字段都不许改(改了服务端按 0 判,不报错、只是永远不通过)
    await tester.tap(find.byKey(const Key('playkit-qa-option-b')));
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.single.action, 'SUBMIT_QA');
    expect(gateway.actionCalls.single.payload, <String, Object?>{
      'optionId': 'b',
    });

    // 退出:真源里那枚由宿主提供(组件自己不带 chrome)
    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    await tester.pumpAndSettle();
    expect(find.byType(PlayKitFullscreenSurface), findsNothing);
    expect(find.text('进入玩法'), findsOneWidget, reason: '退出回到 sheet,不是退出整页');
  });

  testWidgets('负控:未登记的 kind 继续回落通用卡,不开呈现层、不崩', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 样本必须是**注册表里还没有、且也不走内联老视图**的那个:它一接线,
    // 这条负控就变成空转。timeWindow 原来是样本,本线把组件接上了;
    // blindTaste / musicCorner / slowTask 三个虽然也没进注册表,但它们在
    // `advanced_play_sheet.dart` 里被内联老视图截走,到不了这张通用卡 ——
    // 只剩 diyName 是真·兜底卡(它同时也不该出现「进入玩法」那颗钮)。
    expect(
      hasPlayKitComponent(PlayKitKind.diyName),
      isFalse,
      reason: 'diyName 也接线了?换一个没接的 kind 当样本',
    );
    final AdvancedPlayController controller = await started(<String, Object?>{
      'diyName': <String, Object?>{'title': '给它起个名字'},
    });

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('进入玩法'), findsNothing, reason: '注册表里没有它 = 没有组件可开');
    expect(find.byType(PlayKitFullscreenSurface), findsNothing);
    expect(find.text('给它起个名字'), findsOneWidget, reason: '通用卡那条老路还在');
  });

  testWidgets('负控:gameTimer / stickerBook 走底部弹层,不是全屏', (
    WidgetTester tester,
  ) async {
    // 它们是真源里的 cy-sheet(半屏),刻意不在「必须占满屏」那个集合里
    expect(playKitWantsFullscreen(PlayKitKind.stickerBook), isFalse);
    expect(playKitWantsFullscreen(PlayKitKind.gameTimer), isFalse);
    expect(playKitWantsFullscreen(PlayKitKind.qa), isTrue);
    expect(playKitWantsFullscreen(PlayKitKind.countdown), isTrue);

    final AdvancedPlayController controller = await started(
      <String, Object?>{},
    );
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showPlayKitOverlay(
              context: context,
              controller: controller,
              kind: PlayKitKind.stickerBook,
            ),
            child: const Text('打开玩法'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开玩法'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayKitStickerBookView), findsOneWidget);
    expect(
      find.byType(PlayKitFullscreenSurface),
      findsNothing,
      reason: 'cy-sheet 那两件压成整屏会变味,整屏那批压成半屏也一样',
    );
  });

  testWidgets('8 个 v5.1 半屏 kind 行为不变:三件走老视图,其余按接线与否分流', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 一个 kind 一场:真源 `pickPlayKit` 一场只呈现**一个**段(按优先级取第一个
    // 未完成的,`utils/playkit-view.js`),所以 8 个 kind 塞进一个 state 里根本
    // 到不了页面 —— 那样断言的是投影的取舍,不是呈现层有没有抢人。
    // steps(第 8 个)走它自己的 unsupported 门禁,单独钉在下面那条;
    // timeWindow(第 9 个)本批接了组件,它的壳与入口钉在下面单独那条。
    const List<(String, Map<String, Object?>)>
    fixtures = <(String, Map<String, Object?>)>[
      (
        'blindTaste',
        <String, Object?>{'title': '先尝再猜', 'hint': '选你尝到的', 'xp': 10},
      ),
      ('musicCorner', <String, Object?>{'title': '治愈音乐角', 'trackName': '雨声'}),
      ('slowTask', <String, Object?>{'title': '跨日慢任务', 'startHint': '现在开个头'}),
      ('silentOrder', <String, Object?>{'title': '沉默点单', 'rule': '用动作点单'}),
      ('diyName', <String, Object?>{'title': '给今天起个名字'}),
      ('dailySign', <String, Object?>{'claimed': false}),
    ];
    const Set<String> oldViews = <String>{
      'blindTaste',
      'musicCorner',
      'slowTask',
    };
    // 各自卡上的那个落点文案(通用卡那条路要看见标题才算真渲染出来)
    const Map<String, String> cardText = <String, String>{
      // 内联那件顺便钉奖励字样:逐字照抄真源那句,画在页脚右端
      'blindTaste': '答对 +10 XP',
      'silentOrder': '沉默点单',
      'diyName': '给今天起个名字',
      'dailySign': '今日城市签',
    };

    for (final (String name, Map<String, Object?> segment) in fixtures) {
      final PlayKitKind kind = PlayKitKind.values.byName(name);
      final AdvancedPlayController controller = await started(<String, Object?>{
        name: segment,
      });
      await tester.pumpWidget(host(controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      // 谁都不许被新呈现层抢走:**没接线**的连入口都没有(继续走下面那张通用卡);
      // 接线了的(#172 登记 dailySign / silentOrder)才给入口 ——
      // 壳是整屏还是半屏另钉在 `playkit_v51_sheets_test.dart` 与契约表那条。
      expect(
        find.text('进入玩法'),
        hasPlayKitComponent(kind) ? findsOneWidget : findsNothing,
        reason: name,
      );
      // 没点之前谁都不许把呈现层画在 sheet 里(整屏压半屏里「判定区」就不成立)
      expect(find.byType(PlayKitFullscreenSurface), findsNothing, reason: name);
      expect(
        find.byType(AdvancedPlayKitView),
        oldViews.contains(name) ? findsOneWidget : findsNothing,
        reason: '$name 的落点',
      );
      final String? expectedText = cardText[name];
      if (expectedText != null) {
        expect(find.text(expectedText), findsOneWidget, reason: name);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('负控:steps(低碳行动)照旧走它自己的 unsupported 门禁', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final AdvancedPlayController controller = await started(<String, Object?>{
      'steps': <String, Object?>{'goal': 8000, 'current': 900},
    });

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 步数要微信运动的受信回执,App 不伪造 —— 这一场直接进 unsupported,
    // 和呈现层没关系(这批一个字节都没动它)。
    expect(find.text('当前玩法暂不可用'), findsOneWidget);
    expect(find.text('低碳行动'), findsNothing);
    expect(find.text('进入玩法'), findsNothing);
  });

  testWidgets('开关没打开(canWrite=false)时进得去但动不了', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: <String, dynamic>{
        ...stateJson(playKit: qaSegment),
        'status': 'PENDING',
      },
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();
    expect(controller.canWrite, isFalse);

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入玩法'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayKitQaView), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('playkit-qa-option-b')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty, reason: 'enabled=false 时组件不许发动作');
  });

  testWidgets('qa:shoot 拦在 toUpperCase 之前:不发、不炸,只有 qa 组件是合法来源', (
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    // 这条控制器**没接上传口**:两步链缺第一步,宿主给的是实话
    // (「玩法未就绪」),而不是把临时路径当一步直发 —— 全链矩阵在
    // `playkit_qa_shoot_test.dart`,这里只钉门禁两侧。
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    final Map<String, Object?> shootPayload = PlayKitQaPhoto(
      path: '/tmp/only-on-this-phone.jpg',
      size: 2048,
    ).toPayload();
    final PlayKitFullscreenContext qaCard = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.qa, title: '', detail: ''),
    );
    qaCard.onAction!(
      PlayKitAction(label: '', action: kQaShootAction, payload: shootPayload),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 拦在 controller.submit 的 toUpperCase() 之前:出去的话这个名字会变成
    // 服务端不认的 `QA:SHOOT`,不报错、只是玩家拍完照什么也没发生。
    expect(gateway.actionCalls, isEmpty, reason: '拍照问答是两步,不许一步直发');
    expect(find.textContaining('玩法未就绪'), findsOneWidget);

    // 限定来源:别的 kit 抛 shoot 一律丢弃(真源 `pages/play/index.js`
    // 的注释:否则伪造一个 shoot 就能绕过类型门禁去走照片上传)。
    final PlayKitFullscreenContext coinCard = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.coinFlip, title: '', detail: ''),
    );
    coinCard.onAction!(
      PlayKitAction(label: '', action: kQaShootAction, payload: shootPayload),
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty, reason: '别的 kit 不是这条两步链的合法来源');
    expect(
      find.textContaining('没有发出去'),
      findsOneWidget,
      reason: '它一样不在册:静默丢弃会让这条错永远查不出来',
    );
  });

  testWidgets('不在册的动作一发不发:不报错,给一次原生提示;在册的过换算层', (WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();
    final PlayKitFullscreenContext data = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.coinFlip, title: '', detail: ''),
    );

    data.onAction!(const PlayKitAction(label: '', action: 'FLIP_THE_TABLE'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      gateway.actionCalls,
      isEmpty,
      reason: '不在册 = 不发,与真源 serverAction 同口径',
    );
    expect(find.textContaining('没有发出去'), findsOneWidget);

    // 正控:在册的动作名照发(名字一个字不改);载荷过一次服务端口径的翻译。
    // 抛硬币不带参数:结果服务端算,客户端塞的字段一个都不许漏出去
    // (真源 `serverPayload` 的 `coinflip:flip` 返回 `{}`)。
    data.onAction!(
      const PlayKitAction(
        label: '抛一次',
        action: 'FLIP_COIN',
        payload: <String, Object?>{'k': 1},
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, hasLength(1));
    expect(gateway.actionCalls.single.action, 'FLIP_COIN');
    expect(gateway.actionCalls.single.payload, isEmpty);
  });

  testWidgets('★ 挑战类:组件报的单位经宿主换成服务端口径(reaction / quietHold)', (
    WidgetTester tester,
  ) async {
    // 这一条钉的是「静态失败」:组件按玩家读得懂的单位报(times / heldSeconds),
    // 服务端按判定要的单位收(roundsMs / heldMs)。少了这一层换算,
    // 服务端读不到字段**按 0 判** —— 不报错,只是永远不通过。
    late BuildContext ctx;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    final PlayKitFullscreenContext reaction = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.reaction, title: '', detail: ''),
    );
    reaction.onAction!(
      const PlayKitAction(
        label: '',
        action: 'SUBMIT_REACTION',
        // 与 `reaction_view.dart:222-226` 抛出来的一模一样
        payload: <String, Object?>{
          'times': <int>[250, 210, 330],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.last.action, 'SUBMIT_REACTION');
    expect(gateway.actionCalls.last.payload, <String, Object?>{
      'roundsMs': <int>[250, 210, 330],
    });

    final PlayKitFullscreenContext quiet = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.quietHold, title: '', detail: ''),
    );
    quiet.onAction!(
      const PlayKitAction(
        label: '',
        action: 'SUBMIT_QUIET_HOLD',
        // 与 `quiet_hold_view.dart:297-301` 抛出来的一模一样
        payload: <String, Object?>{'heldSeconds': 7},
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.last.payload, <String, Object?>{'heldMs': 7000});

    final PlayKitFullscreenContext start = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.reaction, title: '', detail: ''),
    );
    start.onAction!(const PlayKitAction(label: '', action: 'START_CHALLENGE'));
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.last.payload, <String, Object?>{
      'game': 'reaction',
    });

    // 弹球本来就按服务端口径报 hits,这一层原样放行(不许"顺手"改成别的名字)
    final PlayKitFullscreenContext ball = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.ballShake, title: '', detail: ''),
    );
    ball.onAction!(
      const PlayKitAction(
        label: '',
        action: 'SUBMIT_BALL_SHAKE',
        payload: <String, Object?>{'hits': 7},
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.last.payload, <String, Object?>{'hits': 7});
  });

  testWidgets('silentOrder 认输:真源本来就不发的动作,经宿主走静默路径(停表 + medium 触感,零提示)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 触感留痕:真源 `playkit-silentorder/index.js` 的 onGiveUp 只有
    // 停表 + `motion.haptic(medium)`,没有 toast —— 停表钉在组件测试里,
    // 这条钉的是「经宿主之后」多出来的东西必须一样:零。
    final List<Object?> haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate')
          haptics.add(call.arguments);
        return null;
      },
    );
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        playKit: <String, Object?>{
          'silentOrder': <String, Object?>{'title': '沉默点单', 'rule': '用动作点单'},
        },
      ),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showPlayKitOverlay(
              context: context,
              controller: controller,
              kind: PlayKitKind.silentOrder,
            ),
            child: const Text('打开玩法'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开玩法'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PlayKitSilentOrderView), findsOneWidget);

    await tester.tap(find.byKey(const Key('playkit-silent-order-giveup')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 真源 `utils/playkit-view.js` 的 ACTION_OF 没有 `silentorder:giveup` 这一条,
    // `pages/play/index.js` 的 `_submitPlayKitAction` 查不到名字就 `if (!name) return`
    // —— 不发请求、不提示、不打日志。
    expect(gateway.actionCalls, isEmpty, reason: 'giveup 本就没有服务端动作');
    expect(
      find.textContaining('没有发出去'),
      findsNothing,
      reason: '这句是给接线错误准备的;真源本来就不发的动作被它一说,玩家以为 App 坏了',
    );
    expect(
      haptics,
      // 观测值:HapticFeedback.mediumImpact() 过平台通道的参数就是这个字符串
      // (枚举类型本身不在 services.dart 的公开面里)。
      contains('HapticFeedbackType.mediumImpact'),
      reason: '真源:认输这一下给 medium',
    );
  });

  test('动作名逐条对表:真源 ACTION_OF 的 26 条,加上源码里出现的都得在册', () {
    // 真源 `utils/playkit-view.js` 的 ACTION_OF 值,逐条抄。
    // 《预制人生》四段(2026-09-19 · feat/a4-playkit-journey4)在册四条:
    // `profile:submit` / `note:submit` / `typein:start` / `typein:submit`
    // (START_CHALLENGE 与五个挑战类共用);SUBMIT_PHOTO_CHECK **不在 ACTION_OF**
    // (那张表是「组件事件 → 动作名」,它的提交发生在页面上传完之后,
    // 名字直接对服务端 `AdvancedGameRuntimeServiceImpl` 的 case)。
    expect(kPlayKitServerActions, <String>{
      'SUBMIT_BLIND_TASTE',
      'SUBMIT_DIY_NAME',
      'SUBMIT_STEPS',
      'CLAIM_DAILY_SIGN',
      'START_SLOW_TASK',
      'CLAIM_SLOW_TASK',
      'FLIP_COIN',
      'ROLL_DICE',
      'SUBMIT_ESTIMATE',
      'SUBMIT_PRICE_PAIR',
      'SUBMIT_HIDDEN_OBJECT',
      'SUBMIT_PREDICT',
      'START_CHALLENGE',
      'SUBMIT_REACTION',
      'SUBMIT_BALL_SHAKE',
      'SUBMIT_QUIET_HOLD',
      'SUBMIT_COUNTDOWN',
      'SUBMIT_STOPWATCH',
      'DRAW',
      'CHOOSE',
      'SUBMIT_QA',
      'SUBMIT_SCAN',
      'SUBMIT_PROFILE',
      'SUBMIT_NOTE',
      'SUBMIT_TYPE_IN',
      'SUBMIT_PHOTO_CHECK',
    }, reason: '比真源少一条 = 那个玩法永远不通过;多一条 = 放行了服务端不认的名字');

    // 源码扫一遍:组件/paged 里出现的「像动作名」的字面量必须在册。
    // 漏一个的后果是玩家做完那一下**什么也没发生**,而且零报错 —— 只有扫源码拦得住。
    final RegExp looksLikeAction = RegExp(
      r"'((?:[a-z]{2,}:[a-z-]+)|(?:[A-Z][A-Z_]{2,}))'",
    );
    const Set<String> notKitActions = <String>{
      'SHOT',
      'PICK', // qa 的两种模式枚举,不是动作
      'RUNNING',
      'LEADER', // 会话状态 / 分派方式枚举
      'COMPLETE_UNIT',
      'ASSIGN_ROLE', // 多人协作:控制器直接发,不走组件动作表
      'HEADS', // 抛硬币的**结果**枚举(服务端给 side),玩家那边没有这两个动作
      'TAILS',
      'DAYS', // closeMode 的枚举值(第 N 天揭晓),同样不是动作名
    };
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory(
      'lib/feature/play/advanced',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final String line in f.readAsLinesSync()) {
        final String trimmed = line.trimLeft();
        if (trimmed.startsWith('//') ||
            trimmed.startsWith('*') ||
            trimmed.startsWith('import ')) {
          continue;
        }
        for (final RegExpMatch m in looksLikeAction.allMatches(line)) {
          final String name = m.group(1)!;
          if (kPlayKitServerActions.contains(name)) continue;
          if (name == kQaShootAction ||
              name == kPhotoCheckShootAction ||
              notKitActions.contains(name)) {
            continue;
          }
          offenders.add('${f.path}: $name');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('DIY 命名提交的字段名是 value(真源 triggerEvent 口径)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        playKit: <String, Object?>{
          'diyName': <String, Object?>{'title': '给今天起个名字'},
        },
      ),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('输入名字'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '海边的周三');
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    // 段数据里那格叫 name,但提交字段是 value —— 发错的后果不是报错,
    // 是服务端读不到、按 0 判,玩家永远不通过。
    expect(gateway.actionCalls.single.action, 'SUBMIT_DIY_NAME');
    expect(gateway.actionCalls.single.payload, <String, Object?>{
      'value': '海边的周三',
    });
  });

  testWidgets('DIY 命名的备选词:点选填进输入框,提交的仍是 value', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        playKit: <String, Object?>{
          'diyName': <String, Object?>{
            'title': '给今天起个名字',
            'suggestions': <Object?>['熬夜特调', '便利店之光'],
          },
        },
      ),
    );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('输入名字'));
    await tester.pumpAndSettle();

    // 商家配的备选词要看得见(真源 `buildDiyName` 的 suggestions)
    expect(find.text('「熬夜特调」'), findsOneWidget);
    expect(find.text('「便利店之光」'), findsOneWidget);

    // 点选 = 改值,不是直接提交(真源的 `onPickSuggestion` 发的也是 namechange)
    await tester.tap(find.text('「熬夜特调」'));
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty, reason: '点备选那一下还不是提交');
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .controller
          ?.text,
      '熬夜特调',
    );

    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.single.action, 'SUBMIT_DIY_NAME');
    expect(gateway.actionCalls.single.payload, <String, Object?>{
      'value': '熬夜特调',
    });
  });

  testWidgets('判定回来那一刻不空白:还拿得到本段自己的卡', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(playKit: qaSegment),
    );
    // 答对之后:本段 `finished`,投影会立刻改去「下一个未完成的段」
    // (真源 pickPlayKit 只返回一张卡)—— 那一下正是该显示判定的时刻。
    gateway.actionReply =
        (
          String action,
          Map<String, Object?> payload,
          int version,
          String key,
        ) => AdvancedPlayState.fromJson(
          stateJson(
            playKit: <String, Object?>{
              'qa': <String, Object?>{
                'mode': 'PICK',
                'title': '这座桥建于哪一年?',
                'finished': true,
                'options': <Object?>[
                  <String, Object?>{'id': 'a', 'label': '1908'},
                  <String, Object?>{'id': 'b', 'label': '1912'},
                ],
              },
              'countdown': <String, Object?>{'seconds': 30},
            },
          ),
        );
    final AdvancedPlayController controller = controllerFor(gateway);
    await controller.start();

    await tester.pumpWidget(host(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入玩法'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playkit-qa-option-b')));
    await tester.pumpAndSettle();

    // 收窄那一步的意义:不这么做,这里会拿一张空的最小卡,整屏当场变白。
    expect(gateway.actionCalls, hasLength(1));
    expect(find.byType(PlayKitQaView), findsOneWidget);
    expect(
      find.text('这座桥建于哪一年?'),
      findsOneWidget,
      reason: '题干还在 = 取到的还是本段那张卡,不是别人的',
    );
  });

  test('注册表里每个 kind 都在动作表里有行', () {
    final List<String> missing = <String>[
      for (final PlayKitKind kind in kPlayKitFullscreenBuilders.keys)
        if (!kPlayKitServerActionsOf.containsKey(kind)) kind.name,
    ];
    expect(
      missing,
      isEmpty,
      reason: '新登记一个 kind 却不给动作表加行 = 它的动作一发不发(而且没有任何报错)',
    );
  });

  // ── 注册表里每个 kind 都能真的弹出来(一件一条)────────────────────
  // 这一批的价值就在「接到页面上」:组件写得再对,宿主那格没接上就永远不出现。
  // 最小 state(不给段)钉的是「接上了」,不是「数据齐了」—— 数据是后续批次的事。
  const List<(PlayKitKind, Type)> registeredViews = <(PlayKitKind, Type)>[
    (PlayKitKind.qa, PlayKitQaView),
    (PlayKitKind.branch, PlayKitBranchView),
    (PlayKitKind.estimate, PlayKitEstimateView),
    (PlayKitKind.pricePair, PlayKitPricePairView),
    (PlayKitKind.hiddenObject, PlayKitHiddenView),
    (PlayKitKind.countdown, PlayKitCountdownView),
    (PlayKitKind.stopwatch, PlayKitStopwatchView),
    (PlayKitKind.walk, PlayKitWalkView),
    (PlayKitKind.gameTimer, PlayKitGameTimerView),
    (PlayKitKind.stickerBook, PlayKitStickerBookView),
    // ── 整屏决定类五件套(#86 登记进 kPlayKitFullscreenBuilders,清单漏了)──
    (PlayKitKind.coinFlip, PlayKitCoinFlipView),
    (PlayKitKind.diceRoll, PlayKitDiceRollView),
    (PlayKitKind.reaction, PlayKitReactionView),
    (PlayKitKind.ballShake, PlayKitBallShakeView),
    (PlayKitKind.quietHold, PlayKitQuietHoldView),
    // ── 节点玩法模板族最后四件(feat/playkit-misc)──
    (PlayKitKind.predict, PlayKitPredictView),
    (PlayKitKind.random, PlayKitRandomView),
    (PlayKitKind.scan, PlayKitScanView),
    (PlayKitKind.bingo, PlayKitBingoView),
    // ── v5.1 半屏壳剩下的三件(#172 登记进 kPlayKitFullscreenBuilders)──
    // 壳按真源分:dailySign 自带页头是整屏,另两件是 cy-sheet(宿主走底部弹层)。
    (PlayKitKind.dailySign, PlayKitDailySignView),
    (PlayKitKind.silentOrder, PlayKitSilentOrderView),
    (PlayKitKind.steps, PlayKitStepsView),
    // ── 时段限定(本线收口 #159/#204 的重叠):真源是 cy-sheet,所以半屏那格 ──
    (PlayKitKind.timeWindow, PlayKitTimeWindowView),
    // ── 《预制人生》四段(2026-09-19 · feat/a4-playkit-journey4)──
    // 真源四屏全在 `cy-play-stage skin="qadark"` 整屏台面上,壳一并钉住。
    (PlayKitKind.profile, PlayKitProfileView),
    (PlayKitKind.photoCheck, PlayKitPhotoCheckView),
    (PlayKitKind.note, PlayKitNoteView),
    (PlayKitKind.typeIn, PlayKitTypeInView),
  ];

  test('这一批就是注册表那一批,不多不少', () {
    expect(
      registeredViews.map(((PlayKitKind, Type) row) => row.$1).toSet(),
      kPlayKitFullscreenBuilders.keys.toSet(),
      reason: '注册表加了 kind、这里没加 = 新组件又变成「永远弹不出来」',
    );
  });

  for (final (PlayKitKind kind, Type view) in registeredViews) {
    testWidgets('${kind.name}:开呈现层就看得见组件', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final _FakeGateway gateway = _FakeGateway(startState: stateJson());
      final AdvancedPlayController controller = controllerFor(gateway);
      await controller.start();

      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (BuildContext context) => CupertinoButton(
              onPressed: () => showPlayKitOverlay(
                context: context,
                controller: controller,
                kind: kind,
              ),
              child: const Text('打开玩法'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开玩法'));
      // 不用 pumpAndSettle:倒计时那两件自带节拍器,settle 会被自己的 tick 顶住。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: kind.name);
      expect(find.byType(view), findsOneWidget, reason: '${kind.name} 没弹出来');
      expect(
        find.byType(PlayKitFullscreenSurface),
        playKitWantsFullscreen(kind) ? findsOneWidget : findsNothing,
        reason: '整屏 / 半屏的壳也一并钉住',
      );
    });
  }
}

class _FakeGateway implements AdvancedPlayGateway {
  _FakeGateway({required this.startState});

  final Map<String, dynamic> startState;
  AdvancedPlayState Function(String, Map<String, Object?>, int, String)?
  actionReply;
  final List<({String action, Map<String, Object?> payload})> actionCalls =
      <({String action, Map<String, Object?> payload})>[];

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
    actionCalls.add((action: action, payload: payload));
    final AdvancedPlayState Function(String, Map<String, Object?>, int, String)?
    reply = actionReply;
    return reply == null
        ? AdvancedPlayState.fromJson(startState)
        : reply(action, payload, version, idempotencyKey);
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

/// 测试里不碰 just_audio(平台通道在 widget 测试里没有实现)。
class _SilentAudio implements AdvancedPlayAudio {
  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<Duration> get positionChanged => const Stream<Duration>.empty();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url, {MediaItem? mediaItem}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> dispose() async {}
}
