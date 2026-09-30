// 商家主题报名六条。
//
// ★★ `/select`(我报过这个主题没有)的返回是**反的**,这是整批里最容易写错的一条:
//     · 已报名 → error("您已报名此主题，请勿重复报名")  ← code ≠ 200
//     · 未报名 → success("未报名")                      ← code == 200
//   按"非 200 即失败"处理 ⇒ 已报名显示成「出错了」;
//   按"200 即已报名"处理 ⇒ 含义整个反过来,没报过的被拦着不让报。
//
// ★ 而且它的参数名叫 id、Swagger 写「报名id」,后端却是
//   `setTopicId(Long.valueOf(id))` —— 要的是**主题 id**。文档是错的。
//
// 另外三种传输形态混在同一个 controller 里:
//   list/select/cancel 走**表单**、info 走 **query**(@RequestParam)、
//   create/update 走 **JSON**(@RequestBody)。发错不报错,只是参数变 null。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({MerchantApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: MerchantApi(c), sent: sent);
  }

  group('★★ select 的返回是反的', () {
    test('已报名走 error 分支 → true(不是抛异常)', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '您已报名此主题，请勿重复报名'});
      expect(
        await r.api.hasRegisteredTopic(9),
        isTrue,
        reason: '按"非 200 即失败"处理的话,已报名会显示成「出错了」',
      );
    });

    test('未报名走 success 分支 → false', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '未报名'});
      expect(
        await r.api.hasRegisteredTopic(9),
        isFalse,
        reason: '按"200 即已报名"处理的话,没报过的会被拦着不让报',
      );
    });

    test('★ 真的出错(未登录)仍然抛 —— 别把它也当成「已报名」', () async {
      final r = build(<String, dynamic>{'code': 401, 'msg': '请先登录'});
      await expectLater(
        r.api.hasRegisteredTopic(9),
        throwsA(predicate((Object e) => e.toString().contains('请先登录'))),
      );
    });

    test('★ 传的是**主题 id** —— Swagger 上那句「报名id」是错的', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '未报名'});
      await r.api.hasRegisteredTopic(77);
      final FormData f = r.sent.single.data as FormData;
      expect(f.fields.single.value, '77');
      expect(r.sent.single.path, '/api/registration/merchant/select');
    });
  });

  group('传输形态', () {
    test('★ list 走表单,且 status 是字符串数字', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'rows': <dynamic>[], 'total': 0},
      });
      await r.api.myTopicRegistrations(filter: RegistrationListFilter.rejected);
      expect(r.sent.single.data, isA<FormData>());
      final FormData f = r.sent.single.data as FormData;
      expect(f.fields.single.value, '3');
    });

    test('★★ info 走 **query**(后端 @RequestParam)', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.topicRegistrationDetail(5);
      expect(
        r.sent.single.queryParameters['id'],
        '5',
        reason: '发表单或 body 的话 @RequestParam 绑不上,id 变 null',
      );
    });

    test('★★ create / update 走 **JSON**(后端 @RequestBody)', () async {
      for (final Future<String> Function(MerchantApi) call
          in <Future<String> Function(MerchantApi)>[
            (a) => a.createTopicRegistration(<String, dynamic>{'topicId': 1}),
            (a) => a.updateTopicRegistration(<String, dynamic>{'id': 2}),
          ]) {
        final r = build(<String, dynamic>{'code': 200, 'msg': '已保存'});
        await call(r.api);
        expect(r.sent.single.data, isA<Map<String, dynamic>>());
      }
    });

    test('★ cancel 走表单', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '报名已取消'});
      expect(await r.api.cancelTopicRegistration(5), '报名已取消');
      expect(r.sent.single.data, isA<FormData>());
    });
  });

  group('列表形态与错误', () {
    test('★ 列表在 data.rows(getDataTable)—— 读 data 会拿到空且不报错', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'total': 1,
          'rows': <dynamic>[
            <String, dynamic>{'id': 1, 'addressName': '静安咖啡'},
          ],
        },
      });
      final rows = await r.api.myTopicRegistrations();
      expect(rows.single.addressName, '静安咖啡');
    });

    test('★ 已中标不能取消 —— 原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '已中标的报名不能取消'});
      await expectLater(
        r.api.cancelTopicRegistration(5),
        throwsA(predicate((Object e) => e.toString().contains('不能取消'))),
      );
    });

    test('★ 主题已开始时改不了 —— 原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '主题已开始,报名不能再修改'});
      await expectLater(
        r.api.updateTopicRegistration(<String, dynamic>{'id': 2}),
        throwsA(predicate((Object e) => e.toString().contains('不能再修改'))),
      );
    });

    test('★ 五个筛选值与后端注释里的编号一一对应', () {
      // 后端 @Parameter:0全部 1进行中 2审核中 3已驳回 4已结束
      expect(
        <RegistrationListFilter, String>{
          for (final RegistrationListFilter f in RegistrationListFilter.values)
            f: f.wire,
        },
        <RegistrationListFilter, String>{
          RegistrationListFilter.all: '0',
          RegistrationListFilter.ongoing: '1',
          RegistrationListFilter.reviewing: '2',
          RegistrationListFilter.rejected: '3',
          RegistrationListFilter.finished: '4',
        },
      );
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
