// 故事流内嵌 kit 段(契约 §1.5,真源 `pages/play/index.js` 的 `_inlineKit` +
// `openChapterFull` 的 kind:'kit' 段)。钉的是「present 决定铺不铺」这一整个面:
// · inline 命中 → 组件画在流里(不弹层),动作入口照常走宿主转发;
// · fullscreen / 缺字段 / 未知段 → 一行都不铺(真源「当它不存在」,不崩不报错);
// · 读条 / 失败 / 空三态齐,错误文案点名失败的玩法。
import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_views.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/free_explore/chapter_story_page.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const PlaySessionKey _key = (activityId: 77, topicId: null);
const int _topicId = 23;
const int _nodeId = 1;

/// 节点带高级玩法配置(`hasAdvanced` 认 `advancedConfigJson` 里的 enabled 旗标)。
class _Api implements PlayApi {
  _Api({this.advanced = true});

  final bool advanced;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    return PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': _topicId,
      'mode': 2,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      'nodes': <dynamic>[
        <String, dynamic>{
          'nodeId': _nodeId,
          'name': '长乐路旧物店',
          'address': '长乐路 139 号',
          'sortId': 1,
          'chapterId': 100,
          'done': false,
          'arrived': false,
          'selfReported': false,
          'gameTitle': '旧物寻踪',
          'hasGame': true,
          if (advanced)
            'advancedConfigJson': <String, dynamic>{
              'random': <String, dynamic>{'enabled': true},
            },
        },
      ],
      'chapters': <dynamic>[
        <String, dynamic>{
          'chapterId': 100,
          'name': '旧书与唱片',
          'description': '第一段\n\n第二段',
        },
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements AdvancedPlayGateway {
  _Gateway({this.startState, this.startError, this.gate});

  /// start 返回的权威会话视图(根层可带 present)。
  final Map<String, dynamic>? startState;
  final Object? startError;

  /// 非空时 start 挂在它上 —— 用来把页面按在读条态。
  final Completer<void>? gate;

  int startCalls = 0;
  final List<({String action, Map<String, Object?> payload})> actions =
      <({String action, Map<String, Object?> payload})>[];

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async {
    startCalls++;
    expect(activityId, 77);
    expect(topicId, _topicId);
    expect(nodeId, _nodeId);
    if (gate != null) await gate!.future;
    if (startError != null) throw startError!;
    return AdvancedPlayState.fromJson(startState!);
  }

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    actions.add((action: action, payload: payload));
    // 回执:版本前进、段落完成态 —— 与真源动作回包同形。
    final Map<String, dynamic> next = Map<String, dynamic>.of(
      startState!,
    );
    next['version'] = version + 1;
    final Map<String, Object?> kit = Map<String, Object?>.of(
      next['playKit'] as Map<String, Object?>,
    );
    if (kit['qa'] is Map) {
      kit['qa'] = <String, Object?>{
        ...(kit['qa'] as Map).cast<String, Object?>(),
        'finished': true,
        'feedback': '对了',
      };
    }
    next['playKit'] = kit;
    return AdvancedPlayState.fromJson(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> sessionJson({
  Object? present,
  Map<String, Object?> playKit = const <String, Object?>{
    'qa': <String, Object?>{
      'mode': 'PICK',
      'title': '这座桥建于哪一年?',
      'options': <Object?>[
        <String, Object?>{'id': 'a', 'label': '1908'},
        <String, Object?>{'id': 'b', 'label': '1912'},
      ],
    },
  },
}) => <String, dynamic>{
  'sessionId': 7,
  'activityId': 77,
  'topicId': _topicId,
  'nodeId': _nodeId,
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
  if (present != null) 'present': present,
};

Future<_Gateway> _pumpStory(
  WidgetTester t, {
  Map<String, dynamic>? startState,
  Object? startError,
  Completer<void>? gate,
  bool advanced = true,
}) async {
  final _Gateway gateway = _Gateway(
    startState: startState,
    startError: startError,
    gate: gate,
  );
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(_Api(advanced: advanced)),
        advancedPlayGatewayProvider.overrideWithValue(gateway),
      ].cast(),
      child: MaterialApp(
        navigatorKey: nav,
        home: const ColoredBox(color: Color(0xFF000000)),
      ),
    ),
  );
  await t.pump();
  unawaited(
    nav.currentState!.push(
      CupertinoPageRoute<void>(
        builder: (BuildContext _) =>
            ChapterStoryPage(sessionKey: _key, nodeId: _nodeId, onPrimary: (
              PlayNode _,
            ) {}),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 900));
  return gateway;
}

void main() {
  testWidgets('present=inline:kit 铺进故事流,不弹层', (WidgetTester t) async {
    final _Gateway g = await _pumpStory(
      t,
      startState: sessionJson(present: 'inline'),
    );
    expect(g.startCalls, 1, reason: 'hasAdvanced ⇒ 现取一份权威视图');
    expect(find.byType(PlayKitQaView), findsOneWidget);
    expect(find.text('这座桥建于哪一年?'), findsWidgets);
    expect(
      find.byType(PlayKitFullscreenSurface),
      findsNothing,
      reason: '真源 §1.5:inline ⇒ show=false,那一层根本不弹',
    );
    // 块高 = 视口 70%(`--pk-stage-height:70vh`),宽度铺满。
    final Element stage = t.element(find.byType(PlayKitQaView));
    final Size stageSize = t.getSize(
      find.byKey(const Key('story-kit-stage')),
    );
    final MediaQueryData mq = MediaQuery.of(stage);
    expect(stageSize.height, closeTo(mq.size.height * 0.7, 1));
    expect(stageSize.width, mq.size.width);
  });

  testWidgets('inline 的动作入口:点选项 → 宿主原样转 SUBMIT_QA,完成态回显', (
    WidgetTester t,
  ) async {
    final _Gateway g = await _pumpStory(
      t,
      startState: sessionJson(present: 'inline'),
    );
    // 内嵌段铺在两行正文之后,首屏装不下 —— 滚过去,与玩家的手一致。
    await t.dragUntilVisible(
      find.byType(PlayKitQaView),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await t.pump(const Duration(milliseconds: 900));
    await t.tap(find.text('1908'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 900));
    expect(g.actions, hasLength(1));
    expect(g.actions.single.action, 'SUBMIT_QA');
    expect(g.actions.single.payload['optionId'], 'a');
    // 回包 finished ⇒ 段还在流里,组件显示判定(不弹层、不消失)。
    expect(find.byType(PlayKitQaView), findsOneWidget);
    expect(find.byType(PlayKitFullscreenSurface), findsNothing);
  });

  testWidgets('present 缺字段:不铺内嵌段(默认 fullscreen,存量行为不变)', (
    WidgetTester t,
  ) async {
    final _Gateway g = await _pumpStory(t, startState: sessionJson());
    expect(g.startCalls, 1);
    expect(find.byType(PlayKitQaView), findsNothing);
    expect(find.text('这座桥建于哪一年?'), findsNothing);
  });

  testWidgets('present=fullscreen:不铺;present 是别的值也不崩、也不铺', (
    WidgetTester t,
  ) async {
    await _pumpStory(
      t,
      startState: sessionJson(present: 'fullscreen'),
    );
    expect(find.byType(PlayKitQaView), findsNothing);
    await _pumpStory(
      t,
      startState: sessionJson(present: 'sideways'),
    );
    expect(find.byType(PlayKitQaView), findsNothing);
  });

  testWidgets('inline 但没有玩法段 / 只有不认识的段:一行都不铺,不报错', (
    WidgetTester t,
  ) async {
    await _pumpStory(
      t,
      startState: sessionJson(present: 'inline', playKit: const <String, Object?>{}),
    );
    expect(find.textContaining('玩法没能加载'), findsNothing);
    expect(find.byType(PlayKitQaView), findsNothing);
    await _pumpStory(
      t,
      startState: sessionJson(
        present: 'inline',
        playKit: const <String, Object?>{
          'mystery': <String, Object?>{'title': '不认识这段'},
        },
      ),
    );
    expect(find.text('不认识这段'), findsNothing);
    expect(find.textContaining('玩法没能加载'), findsNothing);
  });

  testWidgets('读条态:会话视图在途给一句实话,回来即撤', (
    WidgetTester t,
  ) async {
    final Completer<void> gate = Completer<void>();
    await _pumpStory(t, startState: sessionJson(present: 'inline'), gate: gate);
    expect(find.text('正在装载这一站的玩法…'), findsOneWidget);
    gate.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('正在装载这一站的玩法…'), findsNothing);
    expect(find.byType(PlayKitQaView), findsOneWidget);
  });

  testWidgets('失败态:文案点名是哪站的玩法、重试真的重发 start', (
    WidgetTester t,
  ) async {
    final _Gateway g = await _pumpStory(
      t,
      startError: const AdvancedPlayBusinessException('服务端没给会话'),
    );
    expect(find.textContaining('「旧物寻踪」的玩法没能加载'), findsOneWidget);
    expect(find.textContaining('服务端没给会话'), findsOneWidget);
    await t.dragUntilVisible(
      find.byKey(const Key('story-kit-retry')),
      find.byType(Scrollable).first,
      const Offset(0, -80),
    );
    await t.pump(const Duration(milliseconds: 900));
    await t.tap(find.byKey(const Key('story-kit-retry')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(g.startCalls, 2);
  });

  testWidgets('节点没有高级玩法:一次会话都不起,流里没有 kit 痕迹', (
    WidgetTester t,
  ) async {
    final _Gateway g = await _pumpStory(t, advanced: false);
    expect(g.startCalls, 0);
    expect(find.text('正在装载这一站的玩法…'), findsNothing);
    expect(find.byType(PlayKitQaView), findsNothing);
  });

  testWidgets('内嵌段晚于首屏铺上:正文各行不许被打回未显形', (
    WidgetTester t,
  ) async {
    final Completer<void> gate = Completer<void>();
    await _pumpStory(
      t,
      startState: sessionJson(present: 'inline'),
      gate: gate,
    );
    // 首屏正文已显形后再让会话视图落地(真源「别把滚到一半的位置弹回开头」)。
    gate.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(find.byType(PlayKitQaView), findsOneWidget);
    final Opacity textOpacity = t.widgetList<Opacity>(
      find.ancestor(of: find.text('第一段'), matching: find.byType(Opacity)),
    ).last;
    expect(textOpacity.opacity, 1.0, reason: '已显形的行不许因为铺 kit 而重置');
  });
}
