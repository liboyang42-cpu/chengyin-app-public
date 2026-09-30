// 核销端(商家侧)。
//
// ★ 此前 App 接了三个 `issue`(出码)、**零个 `redeem`(核销)** ——
//   玩家能出示码、商家扫不了,整条核销链路是断的。
//
// 这组测试盯的是同一件事:**后端写好的具体失败原因不许被吞成笼统的「核销失败」**。
// 后端把越权、幂等、库存三类都写成了可执行的话:
//   ·「您不是商家,无法核销」/「无权核销该据点」 → 告诉商家这不是他的据点
//   ·「玩家未到店打卡,或该券已核销」            → 那是**保护**,不是故障
//   · 库存耗尽会整体事务回滚,允许补货后重扫
// 换成「核销失败,请重试」,商家会在店里对着手机反复扫同一张码。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/group_code_api.dart';
import 'package:chengyin_app/data/api/roam_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  DioClient clientWith(Map<String, dynamic> reply, List<RequestOptions> sent) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return c;
  }

  Map<String, String> formOf(RequestOptions o) {
    final FormData f = o.data as FormData;
    return <String, String>{
      for (final MapEntry<String, String> e in f.fields) e.key: e.value,
    };
  }

  group('据点核销', () {
    test('打到 /api/verify/citynode/redeem,原样带上扫到的码', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final api = RoamApi(
        clientWith(<String, dynamic>{'code': 200, 'msg': '核销成功'}, sent),
      );
      await api.redeemCityNodeCode('CN-abc-123');
      expect(sent.single.path, '/api/verify/citynode/redeem');
      expect(formOf(sent.single)['code'], 'CN-abc-123');
    });

    test('★ 越权提示原样透传 —— 商家要知道「这不是我的据点」', () async {
      final api = RoamApi(
        clientWith(<String, dynamic>{
          'code': 500,
          'msg': '无权核销该据点',
        }, <RequestOptions>[]),
      );
      await expectLater(
        api.redeemCityNodeCode('x'),
        throwsA(predicate((Object e) => e.toString().contains('无权核销该据点'))),
      );
    });

    test('★ 「玩家未到店打卡,或该券已核销」原样透传 —— 那是保护不是故障', () async {
      // 后端用 status 0→1 的条件更新做幂等,翻转失败就回这句。
      // 吞成「网络错误请重试」,商家会在店里对着同一张码反复扫。
      final api = RoamApi(
        clientWith(<String, dynamic>{
          'code': 500,
          'msg': '玩家未到店打卡，或该券已核销',
        }, <RequestOptions>[]),
      );
      await expectLater(
        api.redeemCityNodeCode('x'),
        throwsA(predicate((Object e) => e.toString().contains('已核销'))),
      );
    });

    test('成功时返回后端原话', () async {
      final api = RoamApi(
        clientWith(<String, dynamic>{
          'code': 200,
          'msg': '核销成功,已发券',
        }, <RequestOptions>[]),
      );
      expect(await api.redeemCityNodeCode('x'), '核销成功,已发券');
    });
  });

  group('团码核销', () {
    test('打到 /api/verify/groupcode/redeem', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final api = GroupCodeApi(
        clientWith(<String, dynamic>{'code': 200, 'msg': '核销成功'}, sent),
      );
      await api.redeem('G-777');
      expect(sent.single.path, '/api/verify/groupcode/redeem');
      expect(formOf(sent.single)['code'], 'G-777');
    });

    test('★ 失败原因原样透传', () async {
      final api = GroupCodeApi(
        clientWith(<String, dynamic>{
          'code': 500,
          'msg': '该团码已核销',
        }, <RequestOptions>[]),
      );
      await expectLater(
        api.redeem('x'),
        throwsA(predicate((Object e) => e.toString().contains('该团码已核销'))),
      );
    });
  });

  test('★ issue 与 redeem 是两条不同的路径 —— 别指到同一个', () async {
    final List<RequestOptions> sent = <RequestOptions>[];
    final DioClient c = clientWith(<String, dynamic>{
      'code': 200,
      'msg': 'ok',
      'data': <String, dynamic>{},
    }, sent);
    await RoamApi(c).redeemCityNodeCode('x');
    await GroupCodeApi(c).redeem('y');
    expect(sent.map((RequestOptions o) => o.path).toSet().length, 2);
    expect(
      sent.every((RequestOptions o) => o.path.endsWith('/redeem')),
      isTrue,
      reason: '核销端点必须以 /redeem 结尾;指到 /issue 会变成"扫码反而又发了一张码"',
    );
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
