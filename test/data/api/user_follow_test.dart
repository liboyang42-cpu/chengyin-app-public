// 关注(切换式) / 公开会员列表 / 收件地址详情。
//
// ★★ `/user/follow/action` 后端**没有"关注"和"取关"两个接口** ——
//   一个动作:有记录就删、没记录就加。
//   ⇒ 客户端不能自己维护"我现在是不是关注着"再决定调哪个,
//     只能调一次然后**按后端返回的话**更新界面。
//
// ★★ 而结果**只能从 msg 文案区分**(后端没给布尔)。
//   文案一改这里就会静默判反 —— 所以两种都不匹配时**抛异常**,不猜。
//   猜错的话按钮显示成反的,用户再点一次就真的反了。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/registration_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({RegistrationApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> reply,
  ) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: RegistrationApi(c), sent: sent);
  }

  group('★★ 关注是切换式', () {
    test('「关注成功」→ true', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '关注成功'});
      expect(await r.api.toggleFollow(9), isTrue);
    });

    test('★★ 「取消关注成功」→ false(它里面也含「关注成功」四个字)', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '取消关注成功'});
      expect(
        await r.api.toggleFollow(9),
        isFalse,
        reason: '先判「关注成功」的话,取关会被判成关注 —— 按钮显示成反的',
      );
    });

    test('★★ 两种都不匹配时抛,不猜', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '操作已完成'});
      await expectLater(
        r.api.toggleFollow(9),
        throwsA(predicate((Object e) => e.toString().contains('没确认下来'))),
        // 猜一个的话:猜错 → 按钮反了 → 用户再点一次就真的反了。
      );
    });

    test('★ 参数名是 follow_member_id(下划线)', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '关注成功'});
      await r.api.toggleFollow(42);
      final FormData f = r.sent.single.data as FormData;
      expect(f.fields.single.key, 'follow_member_id');
      expect(f.fields.single.value, '42');
    });

    test('失败原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '取消关注失败'});
      await expectLater(
        r.api.toggleFollow(9),
        throwsA(predicate((Object e) => e.toString().contains('取消关注失败'))),
      );
    });
  });

  group('会员列表与地址', () {
    test('★ user_type 是下划线,列表在 data.rows', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <dynamic>[
            <String, dynamic>{'id': 1, 'nickname': '小李'},
          ],
        },
      });
      final rows = await r.api.publicMemberList(userType: '2', keyword: '咖啡');
      final FormData f = r.sent.single.data as FormData;
      final Map<String, String> m = <String, String>{
        for (final MapEntry<String, String> e in f.fields) e.key: e.value,
      };
      expect(m, <String, String>{'user_type': '2', 'keyword': '咖啡'});
      expect(rows.single['nickname'], '小李');
    });

    test('★ 地址归属在后端查询里 —— 查别人的返回"不可用"不是别人的地址', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '地址不可用'});
      await expectLater(
        r.api.addressInfo(7),
        throwsA(predicate((Object e) => e.toString().contains('地址不可用'))),
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
