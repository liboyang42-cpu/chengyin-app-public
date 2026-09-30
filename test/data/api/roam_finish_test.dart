// 漫游上报与结算。
//
// ★ 这块此前**整块没接**:App 的漫游全程只存在手机本地(roam_session_store),
//   `/api/roam/reveal` 和 `/api/roam/finish` 一次都没调过 ——
//   也就是说走再多路也不涨探索值、拿不到勋章。后端两条接口一直都在。
//
// 下面每条测的都是「接错了会静默出错」的语义,不是覆盖率填空。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/roam_api.dart';
import 'package:chengyin_app/data/models/roam.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({RoamApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> Function(RequestOptions) reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply(o);
    });
    return (api: RoamApi(client), sent: sent);
  }

  Map<String, dynamic> formOf(RequestOptions o) {
    final FormData f = o.data as FormData;
    return <String, dynamic>{
      for (final MapEntry<String, String> e in f.fields) e.key: e.value,
    };
  }

  test('历史迷雾格走 GET + query，与后端契约一致', () async {
    final r = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <dynamic>['w123'],
      },
    );
    expect((await r.api.tiles(limit: 80)).single.key, 'w123');
    expect(r.sent.single.method, 'GET');
    expect(r.sent.single.queryParameters['limit'], '80');
  });

  group('reveal', () {
    test('★ tiles 用逗号拼成字符串 —— 后端不认数组', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'sessionId': 7, 'newlyRevealed': 2},
        },
      );
      await r.api.revealTiles(sessionId: 's1', tiles: <String>['a', 'b', 'c']);
      expect(formOf(r.sent.single)['tiles'], 'a,b,c');
    });

    test('★ 新点亮数以**返回值**为准,不是发出去的条数', () async {
      // 后端是 INSERT IGNORE 幂等的:重发时发了 3 条、真正新增可能只有 1 条。
      // 按发出条数算,重试一次就会把探索值算多。
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'sessionId': 7, 'newlyRevealed': 1},
        },
      );
      final RoamRevealResult result = await r.api.revealTiles(
        sessionId: 's1',
        tiles: <String>['a', 'b', 'c'],
      );
      expect(result.newlyRevealed, 1);
      expect(result.sessionId, '7');
    });

    test('空列表不发请求 —— 别为 0 个格子打一次网络', () async {
      final r = build((_) => <String, dynamic>{'code': 200});
      final result = await r.api.revealTiles(sessionId: '7', tiles: <String>[]);
      expect(result.newlyRevealed, 0);
      expect(result.sessionId, '7');
      expect(r.sent, isEmpty);
    });
  });

  group('finish', () {
    test('结算数值全部来自服务端返回', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'tileXp': 30,
            'poiXp': 40,
            'totalXp': 70,
            'newTiles': 30,
            'newPois': 2,
            'tilesEver': 412,
            'medal': '城市漫游者',
            'sessionShops': 1,
            'shopMedal': <String, dynamic>{
              'code': 'ROAM_SHOP_STREAK',
              'name': '三店连亮',
            },
          },
        },
      );
      final RoamFinishResult res = await r.api.finishSession(
        sessionId: 's1',
        poiIds: <int>[7],
        distanceM: 3200,
      );
      expect(res.totalXp, 70);
      expect(res.tilesEver, 412);
      expect(res.medal, '城市漫游者');
      expect(res.shopMedal?.name, '三店连亮');
    });

    test('★ 没拿到勋章 → medal 是 null,不是空字符串', () async {
      // 空串会让结束屏渲出一个**没有名字的勋章位**。
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'totalXp': 10, 'medal': ''},
        },
      );
      final RoamFinishResult res = await r.api.finishSession(
        sessionId: 's1',
        poiIds: <int>[],
        distanceM: 100,
      );
      expect(res.medal, isNull);
    });

    test('★ 「本次漫游已结算」原样抛出 —— 那是重试保护不是失败', () async {
      // 后端用 CAS 抢结算权防重复发 XP。调用方要能分辨这条,
      // 把它当普通失败弹红字会让用户以为白走了。
      final r = build((_) => <String, dynamic>{'code': 500, 'msg': '本次漫游已结算'});
      await expectLater(
        r.api.finishSession(sessionId: 's1', poiIds: <int>[], distanceM: 1),
        throwsA(predicate((Object e) => e.toString().contains('本次漫游已结算'))),
      );
    });

    test('poiIds 也走逗号拼接', () async {
      final r = build(
        (_) => <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
      );
      await r.api.finishSession(
        sessionId: 's1',
        poiIds: <int>[3, 9],
        distanceM: 500,
      );
      expect(formOf(r.sent.single)['poiIds'], '3,9');
      expect(formOf(r.sent.single)['distanceM'], '500');
    });
  });

  group('sessionFact', () {
    test('★ 核对走 GET + query,两个标识二选一', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'state': 'ACTIVE', 'sessionId': 72},
        },
      );
      await r.api.sessionFact(sessionId: 72);
      expect(r.sent.single.method, 'GET');
      expect(r.sent.single.path, '/api/roam/session');
      expect(r.sent.single.queryParameters['sessionId'], '72');

      final r2 = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'state': 'ACTIVE'},
        },
      );
      await r2.api.sessionFact(clientSessionKey: 'a' * 32);
      expect(r2.sent.single.queryParameters['clientSessionKey'], 'a' * 32);
    });

    test('★★ 只认三态:新 state 按失败处理,不兜成「没记录」', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'state': 'ARCHIVED'},
        },
      );
      await expectLater(
        r.api.sessionFact(sessionId: 1),
        throwsA(isA<RoamApiException>()),
      );
    });

    test('★ FINISHED 才带结算结果,解析成 RoamFinishResult', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'state': 'FINISHED',
            'sessionId': 72,
            'resultComplete': true,
            'result': <String, dynamic>{'totalXp': 88, 'newTiles': 3},
          },
        },
      );
      final RoamSessionFact fact = await r.api.sessionFact(sessionId: 72);
      expect(fact.state, RoamSessionState.finished);
      expect(fact.result?.totalXp, 88);
      expect(fact.resultComplete, isTrue);
    });

    test('★ 进行中/没记录不带结果 —— 别把 null 当 0 画出来', () async {
      final r = build(
        (_) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'state': 'ACTIVE', 'sessionId': 72},
        },
      );
      final RoamSessionFact fact = await r.api.sessionFact(sessionId: 72);
      expect(fact.state, RoamSessionState.active);
      expect(fact.result, isNull);
      expect(fact.resultComplete, isFalse);
    });

    test('没有标识就不发请求', () async {
      final r = build((_) => <String, dynamic>{'code': 200});
      await expectLater(
        r.api.sessionFact(),
        throwsA(isA<RoamApiException>()),
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
