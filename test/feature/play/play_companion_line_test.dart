import 'dart:async';
import 'dart:convert';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// ⚠️ 台词的出现/消失一律用 fakeAsync 推进虚拟时间，禁止改回
// `await Future.delayed(...)` / `await Future.delayed(Duration.zero)` 这类真实墙钟延时。
// 原因：台词过期由 Timer(playCompanionDisplayDurationProvider) 驱动。用真实时间时，
// 「台词还在」这条断言的真正前提变成了「这台机器能在 duration 毫秒内跑完中间那几行」——
// 而 CI 是自托管 Mac，并行 job 一忙，事件循环本身停顿几十毫秒很正常，
// 台词提前过期成 null，用例随机变红（2026-09-05 实测：把 duration 调到 300µs
// 就能稳定复现线上那条红，说明红不红只取决于机器快慢）。
// 把 duration 从 20ms 调大到 200ms 只是降低概率，不是修复：机器再忙一点照样红。
// fakeAsync 下时间只由 async.elapse() 推进，跑多快都得到同一个结论。

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

const PlayNode _target = PlayNode(
  nodeId: 7,
  name: '河畔书店',
  address: '苏州河北岸',
  sortId: 1,
  done: false,
  longitude: 0.01,
  latitude: 0,
  needGps: true,
);

class _FakePlayApi extends PlayApi {
  _FakePlayApi({List<String?>? lines})
    : lines = lines ?? <String?>['已经走一半了', '就快到了'],
      super(_client());

  final List<String?> lines;
  final List<PlaySessionKey> companionRequests = <PlaySessionKey>[];

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async =>
      const PlayNodesResult(
        topicId: 23,
        mode: 1,
        playable: true,
        total: 1,
        doneCount: 0,
        nodes: <PlayNode>[_target],
      );

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async =>
      const PlayNodesResult(
        topicId: 23,
        mode: 1,
        playable: true,
        total: 1,
        doneCount: 0,
        nodes: <PlayNode>[_target],
      );

  @override
  Future<String?> companionLine({int? activityId, int? topicId}) async {
    companionRequests.add((activityId: activityId, topicId: topicId));
    return lines.removeAt(0);
  }
}

class _FakeNavigationLocationSource implements PlayNavigationLocationSource {
  final StreamController<PlayNavigationPosition> _positions =
      StreamController<PlayNavigationPosition>.broadcast();

  @override
  Future<PlayNavigationPosition> current() async =>
      const PlayNavigationPosition(latitude: 0, longitude: 0);

  @override
  Stream<PlayNavigationPosition> watch() => _positions.stream;

  void emit(double longitude) =>
      _positions.add(PlayNavigationPosition(latitude: 0, longitude: longitude));

  Future<void> close() => _positions.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('进度首次跨过 50% 和 90% 各请求一次，重复定位不重发', () {
    fakeAsync((FakeAsync async) {
      final _FakePlayApi api = _FakePlayApi();
      final _FakeNavigationLocationSource locations =
          _FakeNavigationLocationSource();
      final ProviderContainer container = ProviderContainer(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(api),
          playNavigationLocationSourceProvider.overrideWithValue(locations),
        ].cast(),
      );
      final PlaySessionKey key = (activityId: 77, topicId: null);
      final subscription = container.listen(
        playNavigationProvider(key),
        (_, _) {},
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await locations.close();
      });

      unawaited(
        container.read(playNavigationProvider(key).notifier).start(_target),
      );
      async.flushMicrotasks();

      locations.emit(0.0051);
      async.flushMicrotasks();
      expect(api.companionRequests, <PlaySessionKey>[key]);
      expect(container.read(playNavigationProvider(key)).line, '已经走一半了');

      locations.emit(0.0051);
      async.flushMicrotasks();
      expect(api.companionRequests, hasLength(1));

      locations.emit(0.0091);
      async.flushMicrotasks();
      expect(api.companionRequests, <PlaySessionKey>[key, key]);
      expect(container.read(playNavigationProvider(key)).line, '就快到了');

      locations.emit(0.0095);
      async.flushMicrotasks();
      expect(api.companionRequests, hasLength(2));
    });
  });

  test('空回应不显示，可读台词按小程序节奏自动消失', () {
    fakeAsync((FakeAsync async) {
      final _FakePlayApi api = _FakePlayApi(lines: <String?>[null, '再走几步']);
      final _FakeNavigationLocationSource locations =
          _FakeNavigationLocationSource();
      final ProviderContainer container = ProviderContainer(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(api),
          playNavigationLocationSourceProvider.overrideWithValue(locations),
          playCompanionDisplayDurationProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ].cast(),
      );
      final PlaySessionKey key = (activityId: null, topicId: 23);
      final subscription = container.listen(
        playNavigationProvider(key),
        (_, _) {},
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await locations.close();
      });

      unawaited(
        container.read(playNavigationProvider(key).notifier).start(_target),
      );
      async.flushMicrotasks();

      locations.emit(0.0051);
      async.flushMicrotasks();
      expect(container.read(playNavigationProvider(key)).line, isNull);

      locations.emit(0.0091);
      async.flushMicrotasks();
      expect(container.read(playNavigationProvider(key)).line, '再走几步');

      // 只差 1ms 到期：台词必须还在，证明它是被计时器清掉的，不是被机器慢清掉的。
      async.elapse(const Duration(milliseconds: 19));
      expect(container.read(playNavigationProvider(key)).line, '再走几步');

      async.elapse(const Duration(milliseconds: 1));
      expect(container.read(playNavigationProvider(key)).line, isNull);
      expect(api.companionRequests, <PlaySessionKey>[
        (activityId: null, topicId: 23),
        (activityId: null, topicId: 23),
      ]);
    });
  });

  test('后一次空回应不覆盖前一句，也不阻止前一句按时消失', () {
    fakeAsync((FakeAsync async) {
      final _FakePlayApi api = _FakePlayApi(lines: <String?>['先显示这一句', null]);
      final _FakeNavigationLocationSource locations =
          _FakeNavigationLocationSource();
      final ProviderContainer container = ProviderContainer(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(api),
          playNavigationLocationSourceProvider.overrideWithValue(locations),
          playCompanionDisplayDurationProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
        ].cast(),
      );
      final PlaySessionKey key = (activityId: 77, topicId: null);
      final subscription = container.listen(
        playNavigationProvider(key),
        (_, _) {},
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await locations.close();
      });

      unawaited(
        container.read(playNavigationProvider(key).notifier).start(_target),
      );
      async.flushMicrotasks();

      locations.emit(0.0051);
      async.flushMicrotasks();
      expect(container.read(playNavigationProvider(key)).line, '先显示这一句');

      // 故意让第二次空回应发生在第一句显示 10ms 之后：若实现把 null 也当成新台词
      // 去重启 bubbleTimer，到期就会被顺延到 30ms，下面 20ms 那条断言就会红。
      // 虚拟时间才能精确摆出这个时序——真实延时下两次 emit 的间隔全看机器心情。
      async.elapse(const Duration(milliseconds: 10));

      locations.emit(0.0091);
      async.flushMicrotasks();
      expect(container.read(playNavigationProvider(key)).line, '先显示这一句');

      // 仍按第一句自己的 20ms 到期，不因中间那个 null 顺延。
      async.elapse(const Duration(milliseconds: 9));
      expect(container.read(playNavigationProvider(key)).line, '先显示这一句');

      async.elapse(const Duration(milliseconds: 1));
      expect(container.read(playNavigationProvider(key)).line, isNull);
    });
  });

  // testWidgets 自带 fake async：tester.pump() 推的也是虚拟时间，同样不看机器快慢。
  testWidgets('节点前往后展示可读途中台词，后一句替换前一句', (WidgetTester tester) async {
    final _FakePlayApi api = _FakePlayApi();
    final _FakeNavigationLocationSource locations =
        _FakeNavigationLocationSource();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          playApiProvider.overrideWithValue(api),
          playNavigationLocationSourceProvider.overrideWithValue(locations),
        ].cast(),
        child: const MaterialApp(home: PlaySessionPage(activityId: 77)),
      ),
    );
    addTearDown(locations.close);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('play-navigate-7')));
    await tester.pumpAndSettle();
    expect(find.text('开启前往导航'), findsOneWidget);
    await tester.tap(find.text('同意并开始'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play-navigation-status')), findsOneWidget);

    locations.emit(0.0051);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('play-companion-line')), findsOneWidget);
    expect(find.text('已经走一半了'), findsOneWidget);

    locations.emit(0.0091);
    await tester.pump();
    await tester.pump();
    expect(find.text('就快到了'), findsOneWidget);
    expect(find.text('已经走一半了'), findsNothing);
  });

  test('companionLine 只发当前游玩会话参数并透传 line', () async {
    final DioClient client = _client();
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions request) {
      sent.add(request);
      return <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'line': '  跟上来  '},
      };
    });

    final PlayApi api = PlayApi(client);
    expect(await api.companionLine(activityId: 77), '跟上来');
    expect(await api.companionLine(topicId: 23), '跟上来');
    expect(sent, hasLength(2));
    expect(sent[0].path, '/api/play/companionLine');
    expect(sent[0].queryParameters, <String, dynamic>{'activityId': 77});
    expect(sent[1].queryParameters, <String, dynamic>{'topicId': 23});
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);

  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(onRequest(options)),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
