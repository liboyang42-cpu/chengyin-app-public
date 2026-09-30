import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/prefab/prefab_life_page.dart';
import 'package:chengyin_app/feature/prefab/prefab_story_engine.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

DioClient _dummyClient() => DioClient(TokenStore(const FlutterSecureStorage()));

/// 现场链三件套的记录仪:节点、到馆、照片各留调用痕迹,失败可注入。
class _FakePlayApi extends PlayApi {
  _FakePlayApi({this.refetchNodes, this.fetchError}) : super(_dummyClient());

  /// `_syncCompletion` 重读节点时改用这份(回验语义:done/imgUrl 才算数)。
  final PlayNodesResult? refetchNodes;
  Object? fetchError;

  final List<(int, int, double, double)> arrives =
      <(int, int, double, double)>[];
  int photoCalls = 0;
  String? lastPhotoUrl;
  int fetchCalls = 0;

  static PlayNodesResult _default() => const PlayNodesResult(
    topicId: 7,
    mode: 1,
    playable: true,
    total: 1,
    doneCount: 0,
    nodes: <PlayNode>[
      PlayNode(
        nodeId: 21,
        name: '上海城市规划展示馆',
        address: '人民大道 100 号',
        sortId: 1,
        done: false,
      ),
    ],
  );

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    fetchCalls++;
    if (fetchError case final Object e) throw e;
    return fetchCalls > 1 && refetchNodes != null ? refetchNodes! : _default();
  }

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) => fetchNodes(topicId);

  @override
  Future<CheckinReward> submitArrive({
    required int activityId,
    required int nodeId,
    required double longitude,
    required double latitude,
    RouteAdvanceToken? routeAdvance,
  }) async {
    arrives.add((activityId, nodeId, longitude, latitude));
    return const CheckinReward(
      nodeId: 21,
      firstTime: true,
      doneCount: 1,
      total: 1,
      completed: false,
      newBadges: <PlayBadge>[],
    );
  }

  @override
  Future<CheckinReward> submitPhoto({
    required int activityId,
    required int nodeId,
    required String picUrl,
    RouteAdvanceToken? routeAdvance,
  }) async {
    photoCalls++;
    lastPhotoUrl = picUrl;
    return const CheckinReward(
      nodeId: 21,
      firstTime: false,
      doneCount: 1,
      total: 1,
      completed: true,
      newBadges: <PlayBadge>[],
    );
  }
}

class _Harness {
  _Harness({Map<String, String>? bag}) : bag = bag ?? <String, String>{};

  final Map<String, String> bag;

  Widget wrap(Widget page) => ProviderScope(
    overrides: [
      prefabSaveStoreProvider.overrideWithValue(
        PrefabSaveStore(
          read: (String key) async => bag[key],
          write: (String key, String value) async => bag[key] = value,
          clear: (String key) async => bag.remove(key),
        ),
      ),
      prefabPhotoPickerProvider.overrideWithValue(
        () async => 'https://oss/h.jpg',
      ),
      prefabLocationProvider.overrideWithValue(
        () async => const MapCoordinate(longitude: 121.475, latitude: 31.230),
      ),
    ],
    child: CupertinoApp(home: page),
  );

  PrefabState saved() => PrefabState.restore(bag[_storageKey]);

  static const String _storageKey = 'prefab_life_v1_preview';
}

/// advance 到目标幕(引擎按 [kPrefabScenes] 推进,step 归零)。
PrefabState _stateAt(String scene, {int step = 0}) {
  PrefabState s = const PrefabState();
  for (int i = 0; i < kPrefabScenes.indexOf(scene); i++) {
    s = s.advance();
  }
  return step == 0 ? s : s.withStep(step);
}

Future<void> _settle(WidgetTester tester, [int frames = 4]) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _scrollTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _expectVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  expect(finder, findsOneWidget);
}

/// 按秒表逐拍 [ticks] 次,直到 [finder] 出现(每次 90ms,给 80ms 周期表留余量)。
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int ticks = 60,
  String? timeoutHint,
}) async {
  for (int i = 0; i < ticks; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 90));
  }
  expect(finder, findsOneWidget, reason: timeoutHint);
}

void main() {
  testWidgets('缺场次参数:报「场次信息缺失」而不是故障,重试仍是同一句', (tester) async {
    final api = _FakePlayApi();
    final h = _Harness();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage()),
      ),
    );
    await _settle(tester);
    expect(find.text('这一段人生没有加载出来'), findsOneWidget);
    expect(find.text('场次信息缺失，请从票夹重新进入'), findsOneWidget);
    expect(api.fetchCalls, 0, reason: '缺参数不该发请求');

    await tester.tap(find.byKey(const Key('prefab-retry')));
    await _settle(tester);
    expect(find.text('场次信息缺失，请从票夹重新进入'), findsOneWidget);
  });

  testWidgets('加载失败:业务文案直出', (tester) async {
    final h = _Harness();
    final throwing = _FakePlayApi(fetchError: PlayException('本场活动已结束，去不了'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(throwing),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage(activityId: 9)),
      ),
    );
    await _settle(tester);
    expect(find.text('本场活动已结束，去不了'), findsOneWidget);
  });

  testWidgets('加载故障(非业务文案):回落到「路线没加载出来，请稍后重试」', (tester) async {
    final h = _Harness();
    final crashed = _FakePlayApi(fetchError: Exception('boom'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(crashed),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage(topicId: 7)),
      ),
    );
    await _settle(tester);
    expect(find.text('路线没加载出来，请稍后重试'), findsOneWidget);
  });

  testWidgets('mock 预览票:零请求走到登记表,存档落盘,重进续读同一幕', (tester) async {
    final api = _FakePlayApi();
    final h = _Harness();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage(mock: true)),
      ),
    );
    await _settle(tester);

    expect(find.text('宇宙 · 无'), findsOneWidget);
    await _scrollTap(tester, find.text('开始（建议戴耳机）'));
    expect(api.fetchCalls, 0, reason: '预览票不发任何现场请求');
    expect(find.text('你叫什么名字？'), findsOneWidget);
    expect(h.bag['prefab_life_v1_preview'], isNotNull);

    // 同一份存储重进:还停在登记表,而不是回到序章。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(
          home: PrefabLifePage(key: ValueKey('remount'), mock: true),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('你叫什么名字？'), findsOneWidget);
    expect(find.text('开始（建议戴耳机）'), findsNothing);
  });

  testWidgets('登记表:名字必填有话术,逐题作答→密封→回应那个声音进启动幕', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.wrap(const PrefabLifePage(mock: true)));
    await _settle(tester);
    await _scrollTap(tester, find.byKey(const Key('prefab-cta')));

    await _scrollTap(tester, find.byKey(const Key('register-next')));
    expect(find.text('先写下你的名字'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('register-name')), '阿澄');
    await _settle(tester);
    await _scrollTap(tester, find.byKey(const Key('register-next')));
    await _scrollTap(tester, find.byKey(const Key('place-chip-上海')));
    await _scrollTap(tester, find.byKey(const Key('gender-chip-女孩')));
    await _scrollTap(tester, find.byKey(const Key('dream-chip-宇航员')));
    expect(find.byKey(const Key('register-avatar')), findsOneWidget);
    await _scrollTap(tester, find.byKey(const Key('avatar-skip')));
    expect(find.text('各项指标在范围内'), findsOneWidget);
    expect(find.text('“阿澄，各项指标都在范围内。挺好的。”'), findsOneWidget);

    await _scrollTap(tester, find.byKey(const Key('register-submit')));
    expect(find.byKey(const Key('boot-input')), findsOneWidget);
    final saved = h.saved();
    expect(saved.scene, 'boot');
    expect(saved.profile.name, '阿澄');
    expect(saved.profile.place, '上海');
  });

  testWidgets('启动幕:限时逐字敲 hello world,手快 precision+1 并自动进步行幕', (tester) async {
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_preview': _stateAt('boot').save()},
    );
    await tester.pumpWidget(h.wrap(const PrefabLifePage(mock: true)));
    await _settle(tester);
    expect(find.text('＞ 请输入：hello world'), findsOneWidget);

    for (final String ch in kPrefabBootTarget.split('')) {
      await tester.tap(find.byKey(Key('boot-key-$ch')));
      await tester.pump();
    }
    expect(find.text('输入完成 · 很快'), findsOneWidget);

    await _pumpUntil(tester, find.byKey(const Key('walk-route-card')));
    final saved = h.saved();
    expect(saved.scene, 'walk');
    expect(saved.skills['precision'], 2, reason: '6 秒内敲完 +1');
  });

  testWidgets('步行:50% 偏航弹层选「继续这条路」幸运+1,74% 招牌弹层可跳过,100% 到馆', (tester) async {
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_preview': _stateAt('walk').save()},
    );
    await tester.pumpWidget(h.wrap(const PrefabLifePage(mock: true)));
    await _settle(tester);

    await _scrollTap(tester, find.text('开始步行'));
    await _pumpUntil(
      tester,
      find.text('你已偏离推荐路线，是否重新规划？'),
      timeoutHint: '50% 该弹「地图 · 现在」',
    );
    expect(find.text('地图 · 现在'), findsOneWidget);
    await tester.tap(find.text('继续这条路'));
    await _settle(tester);
    expect(find.textContaining('✦ 幸运 3'), findsOneWidget);

    await _pumpUntil(
      tester,
      find.text('路边有一块带“新”字的招牌吗？'),
      timeoutHint: '74% 该弹「路上 · 可选」',
    );
    await tester.tap(find.text('没看到，继续走'));
    await _pumpUntil(
      tester,
      find.text('拍下展示馆的招牌'),
      timeoutHint: '100% 该进「在现场」',
    );
    expect(h.saved().scene, 'hall');
  });

  testWidgets('现场签到链:定位→submitArrive(活动票带节点)→拍招牌落档→进下一幕', (tester) async {
    final api = _FakePlayApi();
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_9': _stateAt('hall').save()},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
          prefabPhotoPickerProvider.overrideWithValue(
            () async => 'https://oss/h.jpg',
          ),
          prefabLocationProvider.overrideWithValue(
            () async =>
                const MapCoordinate(longitude: 121.475, latitude: 31.230),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage(activityId: 9)),
      ),
    );
    await _settle(tester);

    await _scrollTap(tester, find.byKey(const Key('hall-photo')));
    expect(api.arrives, <(int, int, double, double)>[(9, 21, 121.475, 31.230)]);
    await _expectVisible(tester, find.textContaining('我出生在'));
    final saved = PrefabState.restore(h.bag['prefab_life_v1_9']);
    expect(saved.scene, 'birth');
    expect(saved.photos['hall'], 'https://oss/h.jpg');
  });

  testWidgets('定位失败挡在现场任务前:提示要定位,不发签到请求', (tester) async {
    final api = _FakePlayApi();
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_9': _stateAt('hall').save()},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
          prefabLocationProvider.overrideWithValue(() async {
            throw Exception('定位被拒绝');
          }),
        ],
        child: const CupertinoApp(home: PrefabLifePage(activityId: 9)),
      ),
    );
    await _settle(tester);
    await _scrollTap(tester, find.byKey(const Key('hall-photo')));
    expect(find.text('需要定位才能在现场签到'), findsOneWidget);
    expect(api.arrives, isEmpty);
    expect(PrefabState.restore(h.bag['prefab_life_v1_9']).scene, 'hall');
  });

  testWidgets('终章同步:服务器没读回照片就不算数,「再试一次」挂着', (tester) async {
    final api = _FakePlayApi();
    final seeded = _stateAt('flow').withPhoto('hall', 'https://oss/h.jpg');
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_9': seeded.save()},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage(activityId: 9)),
      ),
    );
    await _settle(tester);

    await _scrollTap(tester, find.text('全剧结局'));
    expect(api.photoCalls, 1);
    expect(api.lastPhotoUrl, 'https://oss/h.jpg');
    expect(api.fetchCalls, 2, reason: 'POST 之后要重读节点回验');
    await _expectVisible(tester, find.textContaining('服务器已接收，但还没读回这张现场照片'));
    expect(find.byKey(const Key('endings-panel')), findsNothing);
  });

  testWidgets('终章同步成功(读回 done)才开结局面板,关掉回故事', (tester) async {
    const done = PlayNodesResult(
      topicId: 7,
      mode: 1,
      playable: true,
      total: 1,
      doneCount: 1,
      nodes: <PlayNode>[
        PlayNode(
          nodeId: 21,
          name: '上海城市规划展示馆',
          address: '人民大道 100 号',
          sortId: 1,
          done: true,
        ),
      ],
    );
    final api = _FakePlayApi(refetchNodes: done);
    final seeded = _stateAt('flow').withPhoto('hall', 'https://oss/h.jpg');
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_9': seeded.save()},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playApiProvider.overrideWithValue(api),
          prefabSaveStoreProvider.overrideWithValue(
            PrefabSaveStore(
              read: (String key) async => h.bag[key],
              write: (String key, String value) async => h.bag[key] = value,
              clear: (String key) async => h.bag.remove(key),
            ),
          ),
        ],
        child: const CupertinoApp(home: PrefabLifePage(activityId: 9)),
      ),
    );
    await _settle(tester);

    await _scrollTap(tester, find.text('全剧结局'));
    expect(find.byKey(const Key('endings-panel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('endings-close')));
    await _settle(tester);
    expect(find.byKey(const Key('endings-panel')), findsNothing);
    final saved = PrefabState.restore(h.bag['prefab_life_v1_9']);
    expect(saved.synced, isTrue);
  });

  testWidgets('mock 票直接开结局面板;「重新开始」清档回到序章', (tester) async {
    final h = _Harness(
      bag: <String, String>{'prefab_life_v1_preview': _stateAt('flow').save()},
    );
    await tester.pumpWidget(h.wrap(const PrefabLifePage(mock: true)));
    await _settle(tester);

    await _scrollTap(tester, find.text('全剧结局'));
    expect(find.byKey(const Key('endings-panel')), findsOneWidget);
    expect(find.textContaining(' 的人'), findsWidgets);

    await tester.tap(find.byKey(const Key('endings-reset')));
    await _settle(tester);
    expect(find.byKey(const Key('endings-panel')), findsNothing);
    expect(h.saved().scene, 'prologue');
    await _scrollTap(tester, find.text('开始（建议戴耳机）'));
  });
}
