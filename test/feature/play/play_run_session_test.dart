// 进行中的游戏会话在游玩页的那一半(第二轮拍板 22 跨设备续玩)。
//
// 小程序 `utils/play-run-session.js` 的语义,这里只钉住 App 有控件的那一面
// (沉浸式跑表:开始/暂停),加本机快照:
//   · 开始(新起一局)→ 先清掉上一局的残留
//   · 暂停           → 本机 + 服务端各落一份
//   · 离页           → 同「暂停」落一份
//   · 重进           → 接回上次的用时,不算新起一局
//   · 通关(allDone)  → 停表 + 两份都作废

import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/api/play_run_session_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/data/models/play_run_session.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/play_run_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String activityKey = 'play_paused_run_v1:a41';
  const String topicKey = 'play_paused_run_v1:t71';

  Map<String, String> storage = <String, String>{};

  setUp(() {
    storage = <String, String>{};
  });

  Future<_RecordingRunSessionApi> pumpPlay(
    WidgetTester tester, {
    bool allDone = false,
    PlayRunSessionRead? serverRead,
  }) async {
    FlutterSecureStorage.setMockInitialValues(storage);
    final _RecordingRunSessionApi runApi = _RecordingRunSessionApi(
      serverRead: serverRead,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(_FakePlayApi(allDone: allDone)),
          aiNpcApiProvider.overrideWithValue(_EmptyAiNpcApi()),
          playRunSessionApiProvider.overrideWithValue(runApi),
        ],
        child: const MaterialApp(home: PlaySessionPage(activityId: 41)),
      ),
    );
    await tester.pumpAndSettle();
    return runApi;
  }

  testWidgets('暂停写服务端一份、本机一份;新起一局先清掉上一局的残留', (WidgetTester tester) async {
    final _RecordingRunSessionApi runApi = await pumpPlay(tester);

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    expect(runApi.calls, <String>[
      'read:a41',
      'clear:a41',
    ], reason: '重进时先读服务端那份(这里没有),新起一局再作废本机残留');

    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();

    expect(runApi.calls.last, 'save:a41:0');
    expect(
      storage.containsKey(activityKey),
      isTrue,
      reason: '本机那份也要落盘,服务端写失败还能本机恢复',
    );
    final Map<String, dynamic> local =
        jsonDecode(storage[activityKey]!) as Map<String, dynamic>;
    expect(local['elapsedSeconds'], 0);
    expect(local['savedAt'], greaterThan(0));
  });

  testWidgets('离页也落一份(小程序在 onHide/onUnload 落的是同一份)', (
    WidgetTester tester,
  ) async {
    final _RecordingRunSessionApi runApi = await pumpPlay(tester);

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(runApi.calls.where((String c) => c == 'save:a41:0').length, 1);
    expect(storage.containsKey(activityKey), isTrue);
  });

  testWidgets('重进接回上次暂停的行程:用时接着上次,不算新起一局', (WidgetTester tester) async {
    storage[activityKey] = jsonEncode(<String, dynamic>{
      'elapsedSeconds': 65,
      'savedAt': 1730000000000,
    });

    final _RecordingRunSessionApi runApi = await pumpPlay(tester);

    expect(find.textContaining('已恢复上次暂停的行程'), findsOneWidget);
    expect(find.textContaining('01:05'), findsOneWidget);

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();

    expect(
      runApi.calls.any((String c) => c.startsWith('clear:')),
      isFalse,
      reason: '恢复后按开始是「继续」,不是新起一局 —— 不能清掉这一局',
    );
    expect(
      runApi.calls.last,
      'save:a41:65',
      reason: '恢复的 65 秒 + 刚跑的这一段(测试里约 0 秒)',
    );

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('通关(服务端权威态 allDone)把这一局作废:本机与服务端都清', (WidgetTester tester) async {
    storage[activityKey] = jsonEncode(<String, dynamic>{
      'elapsedSeconds': 65,
      'savedAt': 1730000000000,
    });

    final _RecordingRunSessionApi runApi = await pumpPlay(
      tester,
      allDone: true,
    );

    expect(runApi.calls, hasLength(1));
    expect(runApi.calls.single, 'clear:a41');
    expect(storage.containsKey(activityKey), isFalse);
  });

  testWidgets('换了手机:本机没有快照时接服务端那一份', (WidgetTester tester) async {
    final _RecordingRunSessionApi runApi = await pumpPlay(
      tester,
      serverRead: PlayRunSessionRead(
        ok: true,
        record: const PlayPausedRun(
          elapsedSeconds: 305,
          savedAt: 1730000005000,
        ),
      ),
    );

    expect(find.textContaining('已恢复上次暂停的行程'), findsOneWidget);
    expect(find.textContaining('05:05'), findsOneWidget);
    expect(
      storage.containsKey(activityKey),
      isTrue,
      reason: '服务端那份要写回本机,下次进来先按本机的接',
    );

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    expect(
      runApi.calls.any((String c) => c.startsWith('clear:')),
      isFalse,
      reason: '从服务端接回来的那一局,按开始是继续,不是新起一局',
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('本机那份旧了:服务端更新时改用服务端的,并说明是同步来的', (WidgetTester tester) async {
    storage[activityKey] = jsonEncode(<String, dynamic>{
      'elapsedSeconds': 65,
      'savedAt': 1730000000000,
    });

    await pumpPlay(
      tester,
      serverRead: PlayRunSessionRead(
        ok: true,
        record: const PlayPausedRun(
          elapsedSeconds: 305,
          savedAt: 1730000009000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已同步另一台设备上的进度'), findsOneWidget);
    expect(find.textContaining('05:05'), findsOneWidget);
    expect(
      (jsonDecode(storage[activityKey]!)
          as Map<String, dynamic>)['elapsedSeconds'],
      305,
      reason: '本机那份要被服务端更新的那份覆盖',
    );
  });

  testWidgets('另一台设备已经结束这一局:本机那份作废,不能还魂', (WidgetTester tester) async {
    storage[activityKey] = jsonEncode(<String, dynamic>{
      'elapsedSeconds': 65,
      'savedAt': 1730000000000,
    });

    final _RecordingRunSessionApi runApi = await pumpPlay(
      tester,
      serverRead: const PlayRunSessionRead(ok: true, endedAt: 1730000009000),
    );
    await tester.pumpAndSettle();

    expect(runApi.calls.contains('clear:a41'), isTrue);
    expect(storage.containsKey(activityKey), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(
      storage.containsKey(activityKey),
      isFalse,
      reason: '离页也不能把已结束的一局又写回去(小程序 R1 同款)',
    );
  });

  group('本机快照', () {
    test('脏快照不当成可恢复的一局', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        topicKey: jsonEncode(<String, dynamic>{'elapsedSeconds': 12}),
        'play_paused_run_v1:t72': jsonEncode(<String, dynamic>{
          'elapsedSeconds': 60 * 60 * 24 * 8,
          'savedAt': 1730000000000,
        }),
        'play_paused_run_v1:t73': '不是 JSON',
      });
      const PlayRunSessionStore store = PlayRunSessionStore(
        FlutterSecureStorage(),
      );

      expect(await store.read(topicId: 71), isNull, reason: '没有落盘时刻,恢复不出真用时');
      expect(await store.read(topicId: 72), isNull, reason: '超过一周的用时只可能是脏数据');
      expect(await store.read(topicId: 73), isNull);
      expect(await store.read(topicId: 0), isNull, reason: '没有作用域就没有会话');
    });

    test('活动场次与自玩各存各的 key', () async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      const PlayRunSessionStore store = PlayRunSessionStore(
        FlutterSecureStorage(),
      );

      await store.write(
        activityId: 41,
        elapsedSeconds: 30,
        savedAt: 1730000000000,
      );
      await store.write(topicId: 71, elapsedSeconds: 9, savedAt: 1730000001000);

      expect((await store.read(activityId: 41))!.elapsedSeconds, 30);
      expect((await store.read(topicId: 71))!.elapsedSeconds, 9);

      await store.clear(activityId: 41);
      expect(await store.read(activityId: 41), isNull);
      expect((await store.read(topicId: 71))!.elapsedSeconds, 9);
    });
  });
}

class _RecordingRunSessionApi implements PlayRunSessionGateway {
  _RecordingRunSessionApi({this.serverRead});

  /// 服务端那份的读数;不给 = 没读到(断网),调用方沿用本机快照。
  final PlayRunSessionRead? serverRead;

  final List<String> calls = <String>[];

  @override
  Future<PlayRunSessionRead> read({int? activityId, int? topicId}) async {
    calls.add('read:${_scope(activityId, topicId)}');
    return serverRead ?? const PlayRunSessionRead(ok: false);
  }

  @override
  Future<List<PlayRunSession>> list() async => const <PlayRunSession>[];

  @override
  Future<void> save({
    int? activityId,
    int? topicId,
    required int elapsedSeconds,
    required int savedAt,
  }) async {
    calls.add('save:${_scope(activityId, topicId)}:$elapsedSeconds');
  }

  @override
  Future<void> clear({
    int? activityId,
    int? topicId,
    required int savedAt,
  }) async {
    calls.add('clear:${_scope(activityId, topicId)}');
  }

  String _scope(int? activityId, int? topicId) =>
      activityId != null ? 'a$activityId' : 't$topicId';
}

class _FakePlayApi extends PlayApi {
  _FakePlayApi({required this.allDone})
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  final bool allDone;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async => PlayNodesResult(
    topicId: 71,
    mode: 1,
    playable: true,
    total: 2,
    doneCount: allDone ? 2 : 0,
    chapters: const <PlayChapter>[PlayChapter(chapterId: 3, title: '第一章')],
    nodes: const <PlayNode>[
      PlayNode(
        nodeId: 7,
        name: '外滩源',
        address: '中山东一路',
        sortId: 1,
        done: false,
      ),
    ],
  );
}

class _EmptyAiNpcApi implements AiNpcApi {
  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
