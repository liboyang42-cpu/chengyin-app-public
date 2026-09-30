// NPC 事件冒泡队列:进得去,也必须出得来。
//
// ★★ 为什么单独钉这一条:UI 渲染的是 `bubbleQueue.first`,而 `popBubble()`
//   在接线完成时**零调用方** —— 队列只进不出,第一条冒泡会永远停在屏幕上,
//   之后所有事件的话术用户一条都看不到。构建不报错、接口全通、埋点照发,
//   只有「用户看到的是同一句」这一个症状,靠读代码很难发现。
//
// ⚠️ 断言分两条写(进 / 出),不合并成一条:只断言最终为空的话,
//   「onEvent 压根没往队列里放东西」也会绿。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/npc/npc_controller.dart';

class _FakeAiNpcApi implements AiNpcApi {
  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async =>
      const <NpcProfile>[
        NpcProfile(profileId: 7, name: '阿岩', scopeType: 1, greeting: '走吧'),
      ];

  @override
  Future<NpcLine> fetchEventLine({
    required int profileId,
    required String eventType,
    int? nodeId,
  }) async =>
      NpcLine(profileId: profileId, name: '阿岩', line: '到了,$eventType');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('冒泡入队后会自动出队 —— 不会卡住第一条', (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <dynamic>[
        aiNpcApiProvider.overrideWithValue(_FakeAiNpcApi()),
      ].cast(),
    );
    addTearDown(container.dispose);

    final notifier = container.read(npcSessionProvider(1).notifier);
    await notifier.loadProfiles();
    await notifier.onEvent(NpcEventType.enter);

    // ① 进得去
    expect(container.read(npcSessionProvider(1)).bubbleQueue, hasLength(1),
        reason: 'onEvent 应把话术压进队列');

    // ② 出得来(TTL 5s,给到 6s)
    await tester.pump(const Duration(seconds: 6));
    expect(container.read(npcSessionProvider(1)).bubbleQueue, isEmpty,
        reason: '冒泡到期必须自动出队,否则后续事件的话术永远显示不出来');

    // ③ 出队只动队列,不动历史 —— 追问 Sheet 靠 history 回看
    expect(container.read(npcSessionProvider(1)).history, hasLength(1),
        reason: 'popBubble 不该把历史一起清掉');
  });
}
