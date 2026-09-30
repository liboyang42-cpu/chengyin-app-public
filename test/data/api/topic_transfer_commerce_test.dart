// 主题移交 / 招商章节 / 商家增值购买 / 探店日完局面。
//
// ★★ `/topic/transfer-to-club` **不是"改个归属"**。后端 summary 原话:
//   「复制一份新草稿挂该俱乐部,**原主题下架**;发起人保留所有权」。
//   三件事同时发生。文案写成「已移交」会让人以为原主题还在、只是换了人管 ——
//   而它已经下架了。返回的 newTopicId 是**新那份**,不是原来那个。
//
// ★★ `/registration/explore-completion` 对非探索票是 **fail-closed** 的:
//   返「该订单没有探店日完局面」而不是空壳。后端注释说明了为什么:
//   「空壳会让 ①② 的订单详情也渲染出一块『图鉴 0/0』的假读面」。
//   ⇒ 前端**不能把这个错误吞成空态** —— 吞了等于把 fail-closed 又打开。
//
// ★ `/merchant/commerce/order` 先查**微信身份绑定**:没绑直接
//   「微信身份未绑定，无法发起支付」—— 那是去绑微信,不是重试下单。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({DioClient client, List<RequestOptions> sent}) stub(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (client: c, sent: sent);
  }

  group('主题移交', () {
    test('★★ 返回的是**新主题**的 id', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'newTopicId': 88},
      });
      expect(
        await TopicApi(s.client).transferToClub(topicId: 5, clubId: 3),
        88,
        reason: '拿原 topicId 当结果的话,用户会点回一个已经下架的主题',
      );
    });

    test('★ 没拿到新主题号就抛,别当移交成功', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await expectLater(
        TopicApi(s.client).transferToClub(topicId: 5, clubId: 3),
        throwsA(isA<Exception>()),
      );
    });

    test('★★ 注释里说清「原主题下架」—— 别只写「已移交」', () {
      // 这条要断言的正是**文档注释**的内容,所以读原文而不是 codeOf。
      final String raw = File('lib/data/api/topic_api.dart').readAsStringSync();
      final int rawAt = raw.indexOf('/// 移交主题给俱乐部承接');
      expect(rawAt, greaterThan(0));
      final String doc = raw.substring(
        rawAt,
        raw.indexOf('Future<int>', rawAt),
      );
      expect(doc.contains('原主题下架'), isTrue);
      expect(doc.contains('发起人保留所有权'), isTrue);
    });

    test('两道闸的话术原文透传', () async {
      for (final String msg in <String>[
        '无权移交该主题',
        '需为该俱乐部主理人,或先获得该俱乐部的合作邀约通过,才能移交承接',
      ]) {
        final s = stub(<String, dynamic>{'code': 500, 'msg': msg});
        await expectLater(
          TopicApi(s.client).transferToClub(topicId: 5, clubId: 3),
          throwsA(predicate((Object e) => e.toString().contains(msg))),
        );
      }
    });
  });

  group('探店日完局面', () {
    test('★★ 非探索票的错误必须抛出去,不许吞成空态', () async {
      final s = stub(<String, dynamic>{'code': 500, 'msg': '该订单没有探店日完局面'});
      await expectLater(
        RegistrationApi(s.client).exploreCompletion(7),
        throwsA(predicate((Object e) => e.toString().contains('没有探店日完局面'))),
        // 吞成空态 = 把后端的 fail-closed 又打开,
        // ①② 的订单详情会渲染出一块「图鉴 0/0」的假读面。
      );
    });

    test('越权查别人的报名 → 原文透传', () async {
      final s = stub(<String, dynamic>{'code': 500, 'msg': '无权查看该报名信息'});
      await expectLater(
        RegistrationApi(s.client).exploreCompletion(7),
        throwsA(predicate((Object e) => e.toString().contains('无权查看'))),
      );
    });

    test('正常返回完局面对象', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'collected': 3, 'total': 5},
      });
      expect(
        (await RegistrationApi(s.client).exploreCompletion(7))['total'],
        5,
      );
    });
  });

  group('商家增值', () {
    test('★★ 没绑微信的报错要原样透出 —— 那是去绑微信不是重试', () async {
      final s = stub(<String, dynamic>{'code': 500, 'msg': '微信身份未绑定，无法发起支付'});
      await expectLater(
        MerchantApi(
          s.client,
        ).createCommerceOrder(<String, dynamic>{'sku': 'a'}),
        throwsA(predicate((Object e) => e.toString().contains('微信身份未绑定'))),
      );
    });

    test('★ 「请先完成商家入驻」与「请先登录」是两件事', () async {
      for (final String msg in <String>['请先登录', '请先完成商家入驻']) {
        final s = stub(<String, dynamic>{'code': 500, 'msg': msg});
        await expectLater(
          MerchantApi(s.client).commerceCapabilities(),
          throwsA(predicate((Object e) => e.toString().contains(msg))),
        );
      }
    });

    test('★★ 订单终态走自己的路径,`orderSn` 走 JSON body', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'paymentStatus': 'success'},
      });
      expect(
        await MerchantApi(s.client).commerceOrderStatus('TPLTM_1'),
        'success',
      );
      expect(s.sent.single.path, '/api/merchant/commerce/order/status');
      expect((s.sent.single.data as Map)['orderSn'], 'TPLTM_1');
    });

    test('★★ 读不懂的状态一律 unknown —— 猜一个就是把不知道说成确定', () async {
      for (final Object? raw in <Object?>['refunding', '', null]) {
        final s = stub(<String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'paymentStatus': raw},
        });
        expect(await MerchantApi(s.client).commerceOrderStatus('T'), 'unknown');
      }
    });
  });

  test('招商章节走表单 id', () async {
    final s = stub(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
    await TopicApi(s.client).merchantRecruitmentChapters(9);
    final FormData f = s.sent.single.data as FormData;
    expect(f.fields.single.value, '9');
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
