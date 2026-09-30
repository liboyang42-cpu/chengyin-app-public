// 官方活动的白名单发布者侧七条。
//
// ★★ 这一组的共同点是**一道闸管全部**:后端 canPublish 读 sys_config 的
//   official_publish_whitelist(逗号分隔 memberId,**空 = 全部拒绝**),
//   非白名单一律 error("无官方发布权限")。
//   ⇒ 界面必须先问 can-publish 再决定露不露入口。直接摆出来的话,
//     绝大多数用户点下去必然撞权限错误 —— 点了必失败的按钮比没按钮更坏。
//
// 另外三条容易写成"骗人的成功":
//   · publish:文本同步过审,**封面图异步送检** ⇒ 不能说「封面已生效」;
//   · invites:订阅消息 best-effort(后端逐个 try/ignore)⇒ 不能说「已通知商家」;
//   · broadcast/click:是**埋点**,失败不该抛给用户 —— 用户要去的页面照样得开。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/official_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({OfficialApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: OfficialApi(c), sent: sent);
  }

  group('白名单闸', () {
    test('★ 非白名单 → canPublish false,不抛异常', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'canPublish': false},
      });
      expect(await r.api.canPublish(), isFalse);
    });

    test('★ 游客也安静地拿 false —— 这条不要求登录', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'canPublish': false},
      });
      expect(
        await r.api.canPublish(),
        isFalse,
        reason: '未登录时后端 uid()<=0,canPublish 直接 false,不该报错',
      );
    });

    test('白名单内 → true', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'canPublish': true},
      });
      expect(await r.api.canPublish(), isTrue);
    });

    test('★ 越闸调用发布 → 「无官方发布权限」原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '无官方发布权限'});
      await expectLater(
        r.api.publishEvent(<String, dynamic>{'title': 'x'}),
        throwsA(predicate((Object e) => e.toString().contains('无官方发布权限'))),
      );
    });
  });

  group('发布 / 邀约 / 通知', () {
    test('★ publish 的 data 是活动 id;没给就抛,别当成功', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '已发布', 'data': 77});
      expect(await r.api.publishEvent(<String, dynamic>{'title': 'x'}), 77);

      final r2 = build(<String, dynamic>{'code': 200, 'msg': '已发布'});
      await expectLater(
        r2.api.publishEvent(<String, dynamic>{'title': 'x'}),
        throwsA(isA<OfficialApiException>()),
      );
    });

    test('★ 文本违规同步拦下 —— 原文说清哪段有问题', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '故事包含违规内容'});
      await expectLater(
        r.api.publishEvent(<String, dynamic>{'story': 'x'}),
        throwsA(predicate((Object e) => e.toString().contains('故事包含违规内容'))),
      );
    });

    test('invites 返回新建的邀约 id 列表', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[11, 12, 13],
      });
      expect(
        await r.api.inviteMerchants(<String, dynamic>{
          'merchantIds': <int>[1, 2, 3],
        }),
        <int>[11, 12, 13],
      );
    });

    test('★ broadcast 返回通知编号;没给就抛', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'msg': '通知已提交',
        'data': 5,
      });
      expect(await r.api.broadcast(<String, dynamic>{'title': 't'}), 5);
    });

    test('★ 复盘查别人的通知 → 「通知不存在」是防互看,原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '通知不存在'});
      await expectLater(
        r.api.broadcastStats(9),
        throwsA(predicate((Object e) => e.toString().contains('通知不存在'))),
      );
    });

    test('★★ 点击回流失败必须被吞掉 —— 埋点不能挡住用户要去的页面', () async {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      c.dio.httpClientAdapter = _ThrowingAdapter();
      // 不抛就对了。抛出去的话,用户点通知会因为埋点失败而打不开目标页。
      await OfficialApi(c).reportBroadcastClick(1, channel: 'push');
    });

    test('点击回流带 channel 走 query', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.reportBroadcastClick(3, channel: 'push');
      expect(r.sent.single.path, '/api/official/broadcast/3/click');
      expect(r.sent.single.queryParameters['channel'], 'push');
    });
  });

  group('承接方处置邀约', () {
    test('★ action 走**路径**,不是 body', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.respondParty(42, OfficialPartyAction.accept);
      expect(r.sent.single.path, '/api/official/v2/parties/42/ACCEPT');
    });

    test('★★ OFFICIAL 主办邀约走 organizer-invites,动作在**路径**上', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.respondInvite(42, accept: true);
      expect(
        r.sent.single.path,
        '/api/official/v2/organizer-invites/42/accept',
      );

      final r2 = build(<String, dynamic>{'code': 200});
      await r2.api.respondInvite(42, accept: false);
      expect(
        r2.sent.single.path,
        '/api/official/v2/organizer-invites/42/decline',
        reason: 'OFFICIAL 走 parties 会撞「官方主办关系只能由专用受控命令处理」',
      );
    });

    test('reason 走 body', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.respondParty(
        42,
        OfficialPartyAction.decline,
        reason: '当天有别的局',
      );
      final Map<String, dynamic> sent = (r.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(sent['reason'], '当天有别的局');
      expect(r.sent.single.path, endsWith('/DECLINE'));
    });

    test('不填 reason 就不发这个键', () async {
      final r = build(<String, dynamic>{'code': 200});
      await r.api.respondParty(42, OfficialPartyAction.accept);
      expect((r.sent.single.data as Map).isEmpty, isTrue);
    });

    test('★★ 三个动作的 wire 值与后端 equalsIgnoreCase 比对的字面量一致', () {
      expect(
        OfficialPartyAction.values.map((a) => a.wire).toSet(),
        <String>{'ACCEPT', 'DECLINE', 'WITHDRAW'},
        reason: '拼错会走进「未知邀约动作」,不是 404 —— 看着像后端挂了',
      );
    });

    test('★★ 按状态只露可做的动作', () {
      // 后端前置状态:ACCEPT/DECLINE 只认 INVITED;WITHDRAW 只认 ACCEPTED/ACTIVE。
      expect(OfficialPartyAction.availableFor('INVITED'), <OfficialPartyAction>[
        OfficialPartyAction.accept,
        OfficialPartyAction.decline,
      ]);
      expect(
        OfficialPartyAction.availableFor('ACCEPTED'),
        <OfficialPartyAction>[OfficialPartyAction.withdraw],
      );
      expect(OfficialPartyAction.availableFor('ACTIVE'), <OfficialPartyAction>[
        OfficialPartyAction.withdraw,
      ]);
      // 终态什么都不能做 —— 三个按钮全摆出来的话,点哪个都报错。
      expect(OfficialPartyAction.availableFor('DECLINED'), isEmpty);
      expect(OfficialPartyAction.availableFor('WITHDRAWN'), isEmpty);
      expect(OfficialPartyAction.availableFor(null), isEmpty);
    });
  });

  group('活动到达', () {
    test('请求携带漫游会话、定位精度与幂等号', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'accepted': true, 'completed': true},
      });
      final OfficialArrivalResult result = await r.api.verifyArrival(
        eventId: 44,
        missionCode: 'ARRIVE_RIVER',
        latitude: 31.2304,
        longitude: 121.4737,
        accuracyM: 12,
        sessionId: 72,
        requestId: 'arrival-44-stable',
      );
      final Map<String, dynamic> body = (r.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(result.accepted, isTrue);
      expect(result.completed, isTrue);
      expect(body['sessionId'], 72);
      expect(body['accuracyM'], 12);
      expect(body['requestId'], 'arrival-44-stable');
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

/// 网络直接炸 —— 用来验证埋点失败不会冒泡给用户。
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, message: '断网');
  }

  @override
  void close({bool force = false}) {}
}
