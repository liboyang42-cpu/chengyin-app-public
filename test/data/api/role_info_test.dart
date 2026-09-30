// 身份/能力单一事实源 + 协作邀请处置。
//
// ★★ `/api/role/info` 是后端定的**单一事实源**(注释原话:
//   「下发三端能力位全集,前端 roleGuard 一律读这里」)。
//   客户端自己推能力 = 第二份判据,必然和后端漂。
//
// ★★ 更要紧的第二条:「**role 仅『默认视角』,能力由记录推断**;
//   前端据此同时显示玩家+主理人+商家身份并提供视角切换,
//   不再因 role=club 自动跳管理台」。
//   ⇒ 一个人可以**同时**是玩家、主理人、商家。
//     用 role 做 if/else 会把另外两个身份藏起来。
//
// ★★ 数值配额缺席返回 **null 不是 0**。0 是"一个都不许建"这个真实配置,
//   把"没下发"说成 0 会让界面把功能整个锁死,而且没人看得出为什么。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/data/models/role_info.dart';

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

  group('★★ 三个身份可以同时成立', () {
    test('role=player 但同时是主理人和商家', () {
      final RoleInfo r = RoleInfo.fromJson(<String, dynamic>{
        'role': 'player',
        'isClubLeader': true,
        'isMerchant': true,
        'permission': <String, dynamic>{},
        'usage': <String, dynamic>{},
      });
      expect(r.hasPlayerFace, isTrue);
      expect(r.hasLeaderFace, isTrue);
      expect(r.hasMerchantFace, isTrue, reason: '用 role 做 if/else 会把另外两个身份藏起来');
    });

    test('role=club 但不是商家', () {
      final RoleInfo r = RoleInfo.fromJson(<String, dynamic>{
        'role': 'club',
        'isClubLeader': true,
        'isMerchant': false,
        'permission': <String, dynamic>{},
        'usage': <String, dynamic>{},
      });
      expect(r.hasMerchantFace, isFalse);
      expect(r.hasPlayerFace, isTrue, reason: '主理人也还是玩家');
    });
  });

  group('★★ 配额缺席是 null,不是 0', () {
    test('maxThemes 没下发时 quota 返回 null', () {
      final RoleInfo r = RoleInfo.fromJson(<String, dynamic>{
        'role': 'player',
        'permission': <String, dynamic>{},
        'usage': <String, dynamic>{},
      });
      expect(
        r.quota('maxThemes'),
        isNull,
        reason: '说成 0 会让界面把发布功能整个锁死,而且看不出为什么',
      );
      expect(r.themesLeft, isNull);
    });

    test('maxThemes=0 是真实配置(一个都不许建)', () {
      final RoleInfo r = RoleInfo.fromJson(<String, dynamic>{
        'role': 'player',
        'permission': <String, dynamic>{'maxThemes': 0},
        'usage': <String, dynamic>{'themesOnline': 0},
      });
      expect(r.quota('maxThemes'), 0);
      expect(r.themesLeft, 0);
    });

    test('剩余额度按 themesOnline 算,且不为负', () {
      final RoleInfo r = RoleInfo.fromJson(<String, dynamic>{
        'role': 'player',
        'permission': <String, dynamic>{'maxThemes': 3},
        'usage': <String, dynamic>{'themes': 9, 'themesOnline': 5},
      });
      expect(r.themesLeft, 0, reason: '负数会显示成「还能建 -2 个」');
    });

    test('布尔能力位缺席 = false', () {
      final RoleInfo r = RoleInfo.fromJson(<String, dynamic>{
        'role': 'player',
        'permission': <String, dynamic>{'canCreateTheme': true},
        'usage': <String, dynamic>{},
      });
      expect(r.can('canCreateTheme'), isTrue);
      expect(r.can('canDesignMedal'), isFalse);
    });
  });

  group('协作邀请处置', () {
    test('★★ status 是**目标状态**:1接受 2拒绝 3取消', () {
      expect(
        <CoopHandleAction, int>{
          for (final CoopHandleAction a in CoopHandleAction.values) a: a.wire,
        },
        <CoopHandleAction, int>{
          CoopHandleAction.accept: 1,
          CoopHandleAction.reject: 2,
          CoopHandleAction.cancel: 3,
        },
      );
    });

    test('★★ 待确认:受邀方能接受/拒绝,发起方只能取消', () {
      expect(
        CoopHandleAction.availableFor(
          inviteStatus: 0,
          isFrom: false,
          isTo: true,
        ),
        <CoopHandleAction>[CoopHandleAction.accept, CoopHandleAction.reject],
      );
      expect(
        CoopHandleAction.availableFor(
          inviteStatus: 0,
          isFrom: true,
          isTo: false,
        ),
        <CoopHandleAction>[CoopHandleAction.cancel],
        reason: '发起方点「接受」会撞「仅受邀方可处理」',
      );
    });

    test('★★ 已接受:双方都只能取消', () {
      for (final bool from in <bool>[true, false]) {
        expect(
          CoopHandleAction.availableFor(
            inviteStatus: 1,
            isFrom: from,
            isTo: !from,
          ),
          <CoopHandleAction>[CoopHandleAction.cancel],
          reason: '已处理过的邀约再点接受会撞「该邀请已处理」',
        );
      }
    });

    test('★ 终态什么都不能做', () {
      for (final int st in <int>[2, 3]) {
        expect(
          CoopHandleAction.availableFor(
            inviteStatus: st,
            isFrom: true,
            isTo: true,
          ),
          isEmpty,
          reason: 'status=$st 时取消会撞「该邀请无法取消」',
        );
      }
    });

    test('★★ 只有取消已接受的合作要填理由', () {
      expect(CoopHandleAction.needsReason(CoopHandleAction.cancel, 1), isTrue);
      expect(
        CoopHandleAction.needsReason(CoopHandleAction.cancel, 0),
        isFalse,
        reason: '对所有取消都强制填理由,会让"撤回一个还没人理的邀请"变得很重',
      );
      expect(CoopHandleAction.needsReason(CoopHandleAction.accept, 0), isFalse);
    });

    test('请求体:id + status(+message)', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await CoopApi(s.client).handleInvite(
        inviteId: 5,
        action: CoopHandleAction.cancel,
        reason: '档期冲突',
      );
      final Map<String, dynamic> b = (s.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(b, <String, dynamic>{'id': 5, 'status': 3, 'message': '档期冲突'});
    });

    test('不填理由就不发 message', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await CoopApi(
        s.client,
      ).handleInvite(inviteId: 5, action: CoopHandleAction.accept);
      expect((s.sent.single.data as Map).keys.toSet(), <String>{
        'id',
        'status',
      });
    });

    test('★ 历史邀约被拒 —— 原文透传,别给重试', () async {
      final s = stub(<String, dynamic>{
        'code': 500,
        'msg': '历史商家节点邀约仅供查看，不能再处理',
      });
      await expectLater(
        CoopApi(
          s.client,
        ).handleInvite(inviteId: 5, action: CoopHandleAction.accept),
        throwsA(predicate((Object e) => e.toString().contains('仅供查看'))),
      );
    });
  });

  group('字典与积分', () {
    test('★ 字典空列表 = 没配项,不是错误', () async {
      final s = stub(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      expect(await RegistrationApi(s.client).dict('cy_topic_type'), isEmpty);
    });

    test('积分明细走 result_list', () async {
      final s = stub(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await RegistrationApi(s.client).pointsResultList();
      expect(s.sent.single.path, '/api/points/result_list');
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
