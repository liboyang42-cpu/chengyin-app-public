// 屏④ 店铺分身对话的基准图。两张:①开场态(还没开口)②对话中(含等待名条)。
//
// ⚠️ **一律用定量 `pump(Duration)`,不用 `pumpAndSettle`**:`NpcFigure` 的呼吸浮动
//   与外圈地环是无限 ticker(批 4-3),挂着它就永远有帧被排上,`pumpAndSettle`
//   必然 timeout。也**不包 `TickerMode(enabled:false)`** —— 上一批实测它会把该测的
//   动画一起冻住(见 `page_free_explore_story_golden_test.dart` 顶注)。
//
// ⚠️ 人形是按帧算的(`sin((now-t0)/1400)`),所以**每一次 pump 的时长都参与构图**。
//   改这里的 pump 序列 = 换一张基准图,不要顺手调。
//
// ⚠️ 问候语用 fixture 里**作者写好**的那句,不走时段合成 ——
//   `greetingFor` 吃 `DateTime.now()`,让它合成的话基准图早上拍是「早上好…」、
//   晚上重出就红,而代码一行没改(与 `no_clock_dependent_goldens_test` 同一类腐烂)。
//
// ⚠️ 第二张必须停在「正在输入…」那一拍:`kThinkPhaseDelay` 是 1200ms,
//   总 pump 时长跨过它就会换成「正在回答」。
//
// 更新基准图:flutter test --update-goldens test/golden/page_free_explore_npc_golden_test.dart
import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/shop_npc_models.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_page.dart';
import 'package:chengyin_app/feature/play/free_explore/shop_npc_voice.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

const PlaySessionKey _key = (activityId: 56, topicId: null);

/// ★ fixture 喂 `/api/play/nodes` 的**原始 JSON**,整条走 `PlayNodesResult.fromJson`
/// —— 分身那块尤其要走解析层(`PlayNpcBrief.fromJson` 会把没名字的判成 null)。
/// 用构造函数直接造模型对象会绕过它,键名错配完全隐形。
const Map<String, dynamic> _payload = <String, dynamic>{
  'topicId': 9,
  'mode': 2,
  'playable': true,
  'total': 1,
  'doneCount': 0,
  'chapters': <dynamic>[
    <String, dynamic>{'chapterId': 200, 'name': '旧书与唱片'},
  ],
  'nodes': <dynamic>[
    <String, dynamic>{
      'nodeId': 12,
      'name': '长乐路旧物店',
      'address': '长乐路 88 号',
      'sortId': 1,
      'done': false,
      'arrived': false,
      'selfReported': false,
      'chapterId': 200,
      // 后端 `npc` 只下发 name / greeting 两项(persona 是提示词永不下发,
      // avatar 后端已确认不下发 —— 这一屏中央是程序化 3D 形象,没有头像槽位)。
      'npc': <String, dynamic>{
        'name': '阿旧',
        'greeting': '随便挑挑，看上哪张唱片问我就行',
      },
    },
  ],
};

class _PlayApi implements PlayApi {
  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      PlayNodesResult.fromJson(_payload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NpcApi implements AiNpcApi {
  String reply = '';

  /// 挂住这次请求,好把画面停在「还在等回答」那一刻。
  Completer<void>? gate;

  @override
  Future<ShopNpcReply> shopChat({
    required String requestId,
    required int nodeId,
    required String message,
  }) async {
    if (gate != null) await gate!.future;
    return ShopNpcReply.fromJson(<String, dynamic>{'text': reply});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 录音器替身:基准图不该去碰真麦克风。
class _NoVoice implements ShopNpcVoice {
  @override
  bool get recording => false;

  @override
  Future<void> start({
    required void Function(String path) onClip,
    required void Function(String message) onNotice,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _NpcApi api) async {
  // ★ 走 `tester.view` 而不是 `setSurfaceSize`:后者只改渲染面,**不改 MediaQuery**,
  //   而本页的舞台/消息流/安全区全按 `mq` 排 —— 基准图会把 800×600 的错排固化。
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        playApiProvider.overrideWithValue(_PlayApi()),
        aiNpcApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: ShopNpcPage(sessionKey: _key, nodeId: 12, voice: _NoVoice()),
      ),
    ),
  );
  await tester.pump(); // 取数落地
  // ★ 两步不能并成一步:开页那颗 30ms 定时器要先落地、把 `_open` 翻上去,
  //   `AnimatedOpacity` 才**开始**渐显。并成一次 `pump(400ms)` 的话,那一帧同时
  //   是「定时器到点」和「动画第 0 帧」——拍出来是整屏纯黑(已实拍到)。
  await tester.pump(const Duration(milliseconds: 50)); // 开页 30ms 落地
  await tester.pump(const Duration(milliseconds: 300)); // 整屏渐显 260ms 跑完
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(CupertinoTextField), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('npc-input-send')));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260)); // 滚到底 200ms
}

void main() {
  testWidgets('★ 开场态:人形站定,居中大字是作者写的那句问候', (WidgetTester tester) async {
    await _pump(tester, _NpcApi());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_npc.png'),
    );
  });

  testWidgets('★ 对话中:我方胶囊 / 对方裸正文 + 两个文字操作 / 等待名条', (
    WidgetTester tester,
  ) async {
    final _NpcApi api = _NpcApi()..reply = '九点关门，下雨天有时候提前一点。';
    await _pump(tester, api);
    await _say(tester, '你们几点关门');

    // 第二句挂在半空 —— 等待名条要能被拍到,它是这一屏的等待相位。
    api.gate = Completer<void>();
    await _say(tester, '有停车位吗');
    // 只走 400ms:`kThinkPhaseDelay` 是 1200ms,跨过去名条就换成「正在回答」了。
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/page_free_explore_npc_chat.png'),
    );
    api.gate!.complete();
    await tester.pump();
    await tester.pump();
  });
}
