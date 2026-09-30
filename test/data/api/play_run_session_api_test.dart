// 进行中的游戏会话(`/api/play/run-session`,第二轮拍板 22 跨设备续玩)。
//
// 这条链有三条,各接一个真实时机:
//   · list  → 首页「继续游戏」卡(进行中的一局优先占「继续探索」那张卡)
//   · save  → 暂停/离页落盘
//   · clear → 通关/结束作废(服务端留 ENDED 墓碑)
//
// ⚠️ 作用域**二选一**:活动场次发 activityId、自玩发 topicId。两边都给或都不给
//   都被后端当参数有误 —— 那会让「暂停」这个动作静默丢一次落盘,所以这里逐条钉死。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/play_run_session_api.dart';
import 'package:chengyin_app/data/models/play_run_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({PlayRunSessionApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> Function(RequestOptions) reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return reply(options);
    });
    return (api: PlayRunSessionApi(client), sent: sent);
  }

  Map<String, String> fieldsOf(RequestOptions options) {
    final Object? data = options.data;
    if (data is! FormData) return <String, String>{};
    return <String, String>{
      for (final MapEntry<String, String> field in data.fields)
        field.key: field.value,
    };
  }

  group('list', () {
    test('走 GET /api/play/run-session/list，逐行解析服务端下发的那几个键', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <dynamic>[
            <String, dynamic>{
              'activityId': 27,
              'topicId': 71,
              'runState': 'PAUSED',
              'elapsedSeconds': 305,
              'savedAt': 1730000000000,
              'title': '外滩谜案',
              'cover': 'https://cdn.example/cover.jpg',
            },
          ],
        },
      );

      final List<PlayRunSession> rows = await r.api.list();

      expect(r.sent.single.method, 'GET');
      expect(r.sent.single.path, '/api/play/run-session/list');
      expect(rows, hasLength(1));
      expect(rows.single.activityId, 27);
      expect(rows.single.topicId, 71);
      expect(rows.single.elapsedSeconds, 305);
      expect(rows.single.title, '外滩谜案');
      expect(rows.single.continuable, isTrue);
    });

    test('没有作用域的行不算一局;用时缺失不丢整行(卡上少一行字)', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <dynamic>[
            <String, dynamic>{
              'activityId': 0,
              'topicId': 0,
              'elapsedSeconds': 9,
            },
            <String, dynamic>{'activityId': 0, 'topicId': 71, 'title': '自玩'},
          ],
        },
      );

      final List<PlayRunSession> rows = await r.api.list();

      expect(rows, hasLength(1), reason: '两样都是 0 的行没有去处,不该占一张卡');
      expect(rows.single.topicId, 71);
      expect(rows.single.elapsedSeconds, isNull, reason: '拿不到合法用时就只说「已暂停」');
    });

    test('code != 200 抛后端原文;data 不是数组算回执不完整', () async {
      final failed = build(
        (_) => <String, dynamic>{'code': 401, 'msg': '请先登录'},
      );
      await expectLater(
        failed.api.list(),
        throwsA(
          isA<PlayRunSessionException>().having(
            (PlayRunSessionException e) => e.message,
            'message',
            '请先登录',
          ),
        ),
      );

      final malformed = build(
        (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
      );
      await expectLater(
        malformed.api.list(),
        throwsA(isA<PlayRunSessionException>()),
      );
    });
  });

  group('read(服务端那一份)', () {
    test('走 GET /api/play/run-session，带作用域查那一场', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'runState': 'PAUSED',
            'elapsedSeconds': 305,
            'savedAt': 1730000000000,
          },
        },
      );

      final PlayRunSessionRead read = await r.api.read(activityId: 27);

      expect(r.sent.single.method, 'GET');
      expect(r.sent.single.path, '/api/play/run-session');
      expect(r.sent.single.queryParameters, <String, dynamic>{
        'activityId': '27',
      });
      expect(read.ok, isTrue);
      expect(read.record!.elapsedSeconds, 305);
      expect(read.endedAt, 0);
    });

    test('ENDED 是另一台设备留下的墓碑:只有 endedAt,没有可恢复的记录', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'runState': 'ENDED',
            'savedAt': 1730000009000,
          },
        },
      );

      final PlayRunSessionRead read = await r.api.read(topicId: 71);

      expect(read.ok, isTrue);
      expect(read.record, isNull);
      expect(read.endedAt, 1730000009000);
    });

    test('没读到(code != 200 / 空 data)不算报错,调用方沿用本机那份', () async {
      final failed = build(
        (_) => <String, dynamic>{'code': 401, 'msg': '请先登录'},
      );
      expect((await failed.api.read(activityId: 27)).ok, isFalse);

      final empty = build((_) => <String, dynamic>{'code': 200, 'data': null});
      final PlayRunSessionRead read = await empty.api.read(activityId: 27);
      expect(read.ok, isTrue);
      expect(read.record, isNull);
      expect(read.endedAt, 0);
    });

    test('形状不合法的那份不当成可恢复的记录(用时越界 / 没有落盘时刻)', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'runState': 'PAUSED',
            'elapsedSeconds': PlayPausedRun.maxSeconds + 1,
            'savedAt': 1730000000000,
          },
        },
      );

      final PlayRunSessionRead read = await r.api.read(activityId: 27);

      expect(read.ok, isTrue);
      expect(read.record, isNull, reason: '脏数据不能恢复成看起来正常的假会话');
    });
  });

  group('save', () {
    test('走 POST /api/play/run-session/save，活动场次只发 activityId', () async {
      final r = build((_) => <String, dynamic>{'code': 200, 'msg': 'ok'});

      await r.api.save(
        activityId: 27,
        elapsedSeconds: 305,
        savedAt: 1730000000000,
      );

      expect(r.sent.single.method, 'POST');
      expect(r.sent.single.path, '/api/play/run-session/save');
      expect(fieldsOf(r.sent.single), <String, String>{
        'activityId': '27',
        'elapsedSeconds': '305',
        'savedAt': '1730000000000',
      });
    });

    test('自玩只发 topicId —— 两个都给会被后端当参数有误', () async {
      final r = build((_) => <String, dynamic>{'code': 200});

      await r.api.save(topicId: 71, elapsedSeconds: 12, savedAt: 1730000000000);

      expect(fieldsOf(r.sent.single), <String, String>{
        'topicId': '71',
        'elapsedSeconds': '12',
        'savedAt': '1730000000000',
      });
    });

    test('作用域不全或用时越界时不发请求(宁可没落盘,不落一份假的)', () async {
      final r = build((_) => <String, dynamic>{'code': 200});

      await expectLater(
        r.api.save(elapsedSeconds: 3, savedAt: 1730000000000),
        throwsA(isA<PlayRunSessionException>()),
      );
      await expectLater(
        r.api.save(
          activityId: 27,
          topicId: 71,
          elapsedSeconds: 3,
          savedAt: 1730000000000,
        ),
        throwsA(isA<PlayRunSessionException>()),
      );
      await expectLater(
        r.api.save(
          activityId: 27,
          elapsedSeconds: PlayRunSessionApi.maxPlayRunSeconds + 1,
          savedAt: 1730000000000,
        ),
        throwsA(isA<PlayRunSessionException>()),
      );

      expect(r.sent, isEmpty);
    });

    test('save 失败时抛后端原文,不静默成功', () async {
      final r = build((_) => <String, dynamic>{'code': 500, 'msg': '用时无效'});

      await expectLater(
        r.api.save(activityId: 27, elapsedSeconds: 1, savedAt: 1730000000000),
        throwsA(
          isA<PlayRunSessionException>().having(
            (PlayRunSessionException e) => e.message,
            'message',
            '用时无效',
          ),
        ),
      );
    });
  });

  group('clear', () {
    test('走 POST /api/play/run-session/clear，带上作废时刻', () async {
      final r = build((_) => <String, dynamic>{'code': 200});

      await r.api.clear(activityId: 27, savedAt: 1730000000000);

      expect(r.sent.single.method, 'POST');
      expect(r.sent.single.path, '/api/play/run-session/clear');
      expect(fieldsOf(r.sent.single), <String, String>{
        'activityId': '27',
        'savedAt': '1730000000000',
      });
    });

    test('作废时刻非法时不发请求', () async {
      final r = build((_) => <String, dynamic>{'code': 200});

      await expectLater(
        r.api.clear(topicId: 71, savedAt: 0),
        throwsA(isA<PlayRunSessionException>()),
      );
      expect(r.sent, isEmpty);
    });
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
  ) async {
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
