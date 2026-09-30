// 漫游据点 / 到店 / 集邮 七条接口。
//
// 这一批的坑集中在**「成功了但没发生」**:后端一律 success,
// 真实结果藏在 data 的布尔里,只判 code 会把没发生的事庆祝一遍。
//   · discover:discovered=false 表示以前就发现过,**这次不发 XP**;
//   · shop/visit:recorded=false 表示这家店本次会话已打过;
//   · stamp/create:idempotent=true 表示重放命中原票,**没有入册第二枚**;
//   · badge/shop-streak 与 nearby-exploreday 的 data 可能是 null,那是正常态。
//
// 另有一条只在真机上才会暴露的:BigDecimal 坐标可能以**字符串**下发,
// 只认 num 会静默变 0 —— 所有据点堆到几内亚湾,而且一个异常都不抛。

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

  ({RoamApi api, List<RequestOptions> sent}) build(Map<String, dynamic> reply) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: RoamApi(c), sent: sent);
  }

  group('附近据点', () {
    test('★ 是 GET + query,不是 POST 表单', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.pois(lat: 31.2, lng: 121.4, radiusM: 5000);
      expect(r.sent.single.method, 'GET', reason: '发 POST 会 405');
      expect(r.sent.single.queryParameters['radius'], 5000);
    });

    test('★★ 坐标以字符串下发时也要解析出来 —— 只认 num 会全变 0', () async {
      // BigDecimal 经 Jackson 可能是数字也可能是字符串。变成 0 的话
      // 所有据点会堆在几内亚湾(0,0),而且不抛任何异常。
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{
            'id': 5,
            'name': '静安寺',
            'lat': '31.2231',
            'lng': '121.4450',
            'type': 2,
          },
        ],
      });
      final RoamPoi p = (await r.api.pois(lat: 31.2, lng: 121.4)).single;
      expect(p.lat, closeTo(31.2231, 1e-6));
      expect(p.lng, closeTo(121.4450, 1e-6));
      expect(p.type, 2, reason: 'type=2 必须分流到 shop/visit，不能走普通发现');
    });

    test('不传 radius 就不发这个参数(后端默认 3000)', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.pois(lat: 1, lng: 2);
      expect(r.sent.single.queryParameters.containsKey('radius'), isFalse);
    });
  });

  group('发现据点', () {
    test('★ discovered=false 是「以前就发现过」,不是失败', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'msg': '已发现过',
        'data': <String, dynamic>{'discovered': false, 'poiId': 5, 'xp': 20},
      });
      final RoamPoiDiscovered d = await r.api.discoverPoi(
        sessionId: 1,
        poiId: 5,
        lat: 31.2,
        lng: 121.4,
      );
      expect(d.discovered, isFalse);
      expect(d.message, '已发现过', reason: '后端原话要透出去 —— 「发现新地点」和「已发现过」是两种庆祝');
    });

    test('★ 到点校验没过要抛出去 —— 吞掉的话 finish 时那份 XP 凭空消失', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '还没到该地点附近'});
      await expectLater(
        r.api.discoverPoi(sessionId: 1, poiId: 5, lat: 0, lng: 0),
        throwsA(predicate((Object e) => e.toString().contains('还没到该地点附近'))),
      );
    });

    test('反作弊拒绝也原样透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '移动过快,疑似伪造定位'});
      await expectLater(
        r.api.discoverPoi(sessionId: 1, poiId: 5, lat: 0, lng: 0),
        throwsA(predicate((Object e) => e.toString().contains('移动过快'))),
      );
    });

    test('meaning 缺席不影响发现结果', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'msg': '发现新地点',
        'data': <String, dynamic>{'discovered': true, 'poiId': 5, 'xp': 20},
      });
      final d = await r.api.discoverPoi(
        sessionId: 1,
        poiId: 5,
        lat: 31.2,
        lng: 121.4,
      );
      expect(d.discovered, isTrue);
      expect(d.meaning, isNull);
    });
  });

  group('到店打卡', () {
    test('★ shops 是本次会话的**不同店铺**数 —— 三店连亮看它', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'recorded': true, 'shops': 3},
      });
      final RoamShopVisit v = await r.api.shopVisit(
        sessionId: 1,
        sourceType: 1,
        sourceId: 9,
        lat: 1,
        lng: 2,
      );
      expect(v.recorded, isTrue);
      expect(v.shops, 3);
    });

    test('★ 未中标商家被拒 —— 原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '该商家未参与漫游'});
      await expectLater(
        r.api.shopVisit(
          sessionId: 1,
          sourceType: 2,
          sourceId: 9,
          lat: 1,
          lng: 2,
        ),
        throwsA(predicate((Object e) => e.toString().contains('该商家未参与漫游'))),
      );
    });

    test('★ 不给后端发店名 —— 后端从来源表读,前端传了也不采信', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'recorded': true, 'shops': 1},
      });
      await r.api.shopVisit(
        sessionId: 1,
        sourceType: 1,
        sourceId: 9,
        lat: 1,
        lng: 2,
      );
      final FormData f = r.sent.single.data as FormData;
      final Set<String> keys = f.fields.map((e) => e.key).toSet();
      expect(keys.contains('name'), isFalse, reason: '传店名只会造出一个改了不生效的输入框');
      expect(keys, <String>{
        'sessionId',
        'sourceType',
        'sourceId',
        'lat',
        'lng',
      });
    });
  });

  group('集邮', () {
    test('★★ 必须发 idempotencyKey —— 否则重试会真的入册第二枚', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'id': 11},
      });
      await r.api.createStamp(picUrl: 'https://x/a.png', idempotencyKey: 'k1');
      final FormData f = r.sent.single.data as FormData;
      expect(f.fields.map((e) => e.key), contains('idempotencyKey'));
    });

    test('★★ 同键重放 → idempotent=true,提示不能说「又收藏了一枚」', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'id': 11, 'idempotent': true},
      });
      final RoamStampCreated c = await r.api.createStamp(
        picUrl: 'https://x/a.png',
        idempotencyKey: 'k1',
      );
      expect(c.idempotent, isTrue);
      expect(c.id, 11, reason: '重放要拿回**原来那枚**的 id');
    });

    test('★ checkState=0(未送检)照样显示 —— 机审关闭时那是诚实值', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'list': <dynamic>[
            <String, dynamic>{'id': 1, 'picUrl': 'a', 'checkState': 0},
            <String, dynamic>{'id': 2, 'picUrl': 'b', 'checkState': 1},
            <String, dynamic>{'id': 3, 'picUrl': 'c', 'checkState': 2},
          ],
          'total': 3,
          'pageNum': 1,
          'pageSize': 20,
        },
      });
      final RoamStampPage page = await r.api.stampList();
      expect(
        page.list.where((s) => s.visible).length,
        2,
        reason: '只有 checkState=2(违规)该隐藏;把 0 也藏掉会让册子在机审关闭时整个空掉',
      );
    });

    test('分页:还有下一页', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'list': <dynamic>[],
          'total': 45,
          'pageNum': 1,
          'pageSize': 20,
        },
      });
      expect((await r.api.stampList()).hasMore, isTrue);
    });

    test('末页 hasMore 为 false', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'list': <dynamic>[],
          'total': 40,
          'pageNum': 2,
          'pageSize': 20,
        },
      });
      expect((await r.api.stampList()).hasMore, isFalse);
    });
  });

  group('可空 data 的两条', () {
    test('★ 勋章停用 → data 为 null → 返回 null,不抛也不弹卡', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': null});
      expect(await r.api.shopStreakBadge(), isNull);
    });

    test('勋章启用时解析出门槛', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'code': 'SHOP_STREAK',
          'name': '三店连亮',
          'threshold': 3,
        },
      });
      expect((await r.api.shopStreakBadge())!.threshold, 3);
    });

    test('★ 附近没探索日活动 → null,是正常态不是错误', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': null});
      expect(await r.api.nearbyExploreDay(lat: 31.2, lng: 121.4), isNull);
    });

    test('缺少定位时后端报错,照抛', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '缺少定位'});
      await expectLater(
        r.api.nearbyExploreDay(lat: 0, lng: 0),
        throwsA(predicate((Object e) => e.toString().contains('缺少定位'))),
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
