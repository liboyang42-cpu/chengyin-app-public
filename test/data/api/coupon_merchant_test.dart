// 商家侧优惠券:发布 / 核销 / 我发过的。
//
// 此前 App 只有**玩家侧**(领券、出示动态码),商家发不了券、核销不了、
// 也看不到自己发过什么 —— 后端三条接口一直都在。
//
// 下面测的都是「接错了会让一张能核销的券被挡在门外」或
// 「把保护提示说成失败」这类语义,不是覆盖率填空。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coupon_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({CouponApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: CouponApi(client), sent: sent);
  }

  Map<String, String> formOf(RequestOptions o) {
    final FormData f = o.data as FormData;
    return <String, String>{
      for (final MapEntry<String, String> e in f.fields) e.key: e.value,
    };
  }

  group('核销', () {
    test('★ 扫到什么就原样传什么 —— 前端不判断「像 token 还是像 code」', () async {
      // 后端优先当 token 解析,失败再当 code(ApiCouponController:283-300)。
      // 前端自作聪明分类,判错就会把一张能核销的券挡在门外。
      final r = build(<String, dynamic>{'code': 200, 'msg': '核销成功'});
      await r.api.verify('eyJhbGciOi.looks.like.token');
      expect(formOf(r.sent.single)['code'], 'eyJhbGciOi.looks.like.token');

      final r2 = build(<String, dynamic>{'code': 200, 'msg': '核销成功'});
      await r2.api.verify('OLD-STATIC-CODE-123');
      expect(formOf(r2.sent.single)['code'], 'OLD-STATIC-CODE-123');
    });

    test('★ 「二维码已过期」原样透传 —— 那是让用户刷新,不是核销失败', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '二维码已过期，请刷新后重试'});
      await expectLater(
        r.api.verify('t'),
        throwsA(predicate((Object e) => e.toString().contains('二维码已过期'))),
      );
    });

    test('成功时返回后端原话', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '核销成功,已抵扣'});
      expect(await r.api.verify('t'), '核销成功,已抵扣');
    });
  });

  group('发布', () {
    test('★ 配额被拒时原因要能看见 —— 用户得知道去下架旧券', () async {
      final r = build(<String, dynamic>{
        'code': 500,
        'msg': '当前角色最多同时存在 3 张券,请先下架一张',
      });
      await expectLater(
        r.api.publish(
          name: '五折券',
          startTime: DateTime(2026, 8, 20),
          endTime: DateTime(2026, 9, 20),
          publishCount: 100,
          couponType: 1,
        ),
        throwsA(predicate((Object e) => e.toString().contains('请先下架一张'))),
      );
    });

    test('★ 「发券太频繁」是保护不是错误 —— 提示别引导用户去改表单', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '发券太频繁，请稍后再试'});
      await expectLater(
        r.api.publish(
          name: '五折券',
          startTime: DateTime(2026, 8, 20),
          endTime: DateTime(2026, 9, 20),
          publishCount: 100,
          couponType: 1,
        ),
        throwsA(predicate((Object e) => e.toString().contains('发券太频繁'))),
      );
    });

    test('走 JSON body,时间是 ISO8601', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '已发布'});
      await r.api.publish(
        name: '五折券',
        startTime: DateTime(2026, 8, 20, 10),
        endTime: DateTime(2026, 9, 20, 22),
        publishCount: 100,
        couponType: 1,
      );
      final Map<String, dynamic> sent = (r.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(sent['name'], '五折券');
      expect(sent['publishCount'], 100);
      expect('${sent['startTime']}', startsWith('2026-08-20T10:00'));
    });

    test('描述为空时不传该字段 —— 别给后端塞一个空串', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '已发布'});
      await r.api.publish(
        name: 'x',
        startTime: DateTime(2026, 8, 20),
        endTime: DateTime(2026, 9, 20),
        publishCount: 1,
        couponType: 1,
        description: '',
      );
      expect((r.sent.single.data as Map).containsKey('description'), isFalse);
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
