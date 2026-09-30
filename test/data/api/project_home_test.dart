// 项目主页 / 玩家名单 / 发布工作台 / 推荐 / IP 世界,共五条。
//
// 两个下划线参数是这批的静默陷阱:
//   · `/recommendation/list` 的 **candidate_type** —— 写成驼峰绑不上,
//     后端回落成默认的 "topic":你以为在要活动,拿回来的是主题,而且不报错;
//   · `/world/home` 的 **city_code / world_id** 同理。
//
// 一条权限原则来自后端注释,前端必须**不做二次过滤**:
//   「联系方式给不给判在 service(主办方自办才给),前端不做二次过滤 ——
//     前端过滤等于把号码先发出去再假装没发」。
//   ⇒ 拿到就显示、没拿到就不显示;前端脱敏意味着明文已经到了客户端。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/my_project_api.dart';
import '../../support/source_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({MyProjectApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: MyProjectApi(c), sent: sent);
  }

  Map<String, String> form(RequestOptions o) => <String, String>{
    for (final MapEntry<String, String> e in (o.data as FormData).fields)
      e.key: e.value,
  };

  group('★★ 下划线参数名', () {
    test('recommendation 用 candidate_type', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.recommendations(candidateType: 'activity', limit: 5);
      expect(form(r.sent.single), <String, String>{
        'candidate_type': 'activity',
        'limit': '5',
      });
    });

    test('★ 写成驼峰的后果:后端回落成 topic 且不报错', () {
      // 这条盯的是代码里别出现驼峰写法。
      final String code = codeOf('lib/data/api/my_project_api.dart');
      expect(
        code.contains("'candidateType':"),
        isFalse,
        reason: '绑不上会静默回落成默认的 topic —— 你以为在要活动,拿回来的是主题',
      );
      expect(code.contains("'cityCode':"), isFalse);
      expect(code.contains("'worldId':"), isFalse);
    });

    test('world/home 用 city_code / world_id', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.worldHome(cityCode: '310000', worldId: 3);
      expect(form(r.sent.single), <String, String>{
        'city_code': '310000',
        'world_id': '3',
      });
    });

    test('都不传就发空表单', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.worldHome();
      expect(form(r.sent.single).isEmpty, isTrue);
    });
  });

  group('项目主页与名单', () {
    test('topicId 可空,不传就不发这个键', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.projectHome();
      expect((r.sent.single.data as Map).isEmpty, isTrue);
    });

    test('传了就带上', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.projectHome(topicId: 9);
      expect((r.sent.single.data as Map)['topicId'], 9);
    });

    test('★★ 名单原样返回,前端不做二次过滤/脱敏', () async {
      // 后端只对该看的人下发联系方式。前端再脱敏 =
      // 明文已经到了客户端,只是没显示 —— 那不叫保护。
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{'nickname': '小李', 'phone': '13800001111'},
            <String, dynamic>{'nickname': '小王'},
          ],
          'contactVisible': true,
        },
      });
      final List<Map<String, dynamic>> rows =
          ((await r.api.projectPlayers())['rows'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      expect(rows[0]['phone'], '13800001111', reason: '后端给了就说明这个人有权看;前端不该再动它');
      expect(
        rows[1].containsKey('phone'),
        isFalse,
        reason: '后端没给就是没给,前端不许补一个占位',
      );

      final String code = codeOf('lib/data/api/my_project_api.dart');
      for (final String masking in <String>[
        '****',
        'substring(0, 3)',
        'mask',
      ]) {
        expect(code.contains(masking), isFalse, reason: '前端脱敏 = 把号码先发出去再假装没发');
      }
    });

    test('★ 有聚合接口就别再拿那五条去拼', () {
      final String code = codeOf('lib/data/api/my_project_api.dart');
      expect(code.contains("'/api/project/home'"), isTrue);
      // 注释里记着那五条的名字,拼出来的与聚合口径必然漂。
      expect(code.contains("'/api/topic/info-to-merchant'"), isFalse);
    });

    test('★★ contactHint 必须能拿到 —— 只给一个 false 商家会以为是 bug', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[],
          'contactVisible': false,
          'contactHint': '这条路线由俱乐部带团,玩家联系方式请找俱乐部负责人',
        },
      });
      final Map<String, dynamic> d = await r.api.projectPlayers();
      expect(d['contactVisible'], isFalse);
      expect(
        d['contactHint'],
        contains('请找俱乐部负责人'),
        reason: '后端专门给了这句话说清为什么、以及该找谁',
      );
    });

    test('推荐列表:裸 List 或 data.rows 都收', () async {
      final r1 = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{'id': 1},
        ],
      });
      expect((await r1.api.recommendations()).length, 1);

      final r2 = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{'id': 2},
          ],
        },
      });
      expect((await r2.api.recommendations()).single['id'], 2);
    });
  });

  group('错误', () {
    test('未登录原文透传', () async {
      final r = build(<String, dynamic>{'code': 401, 'msg': '请先登录'});
      await expectLater(
        r.api.publishHome(),
        throwsA(predicate((Object e) => e.toString().contains('请先登录'))),
      );
    });

    test('★ world/home 不要求登录 —— 别在客户端加登录闸', () {
      // 后端没取 uid,游客也能看。
      final String code = codeOf('lib/data/api/my_project_api.dart');
      final int at = code.indexOf('Future<Map<String, dynamic>> worldHome(');
      expect(at, greaterThan(0));
      final String body = code.substring(at, code.indexOf('\n  }\n', at));
      expect(body.contains('请先登录'), isFalse);
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
