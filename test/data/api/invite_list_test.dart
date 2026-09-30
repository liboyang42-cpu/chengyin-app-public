// 邀请列表的下发形态。
//
// ★ 后端用 `getDataTable(list)` 包了一层 —— 列表在 **data.rows** 不是 data。
//   直接读 data 会拿到**空列表且不报错**:界面显示「你还没邀请过人」,
//   而其实邀请了一堆。这类错**不会抛异常**,只会让功能悄悄变成空的。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/points_statistics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  RegistrationApi apiWith(Map<String, dynamic> reply) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    c.dio.httpClientAdapter = _StubAdapter((_) => reply);
    return RegistrationApi(c);
  }

  test('★ data.rows 形态(后端 getDataTable 的真实下发)', () async {
    final api = apiWith(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'total': 2,
        'rows': <dynamic>[
          <String, dynamic>{'id': 1, 'nickname': '小李'},
          <String, dynamic>{'id': 2, 'nickname': '小王'},
        ],
      },
    });
    final List<InvitedMember> rows = (await api.invitePage()).rows;
    expect(
      rows.length,
      2,
      reason:
          '只读 data 不读 data.rows 的话,这里会是 0 —— '
          '界面说「你还没邀请过人」,而其实邀请了两个',
    );
    expect(rows.first.displayName, '小李');
  });

  test('data 直接是数组也收 —— 后端两种形态都出现过', () async {
    final api = apiWith(<String, dynamic>{
      'code': 200,
      'data': <dynamic>[
        <String, dynamic>{'id': 1, 'nickname': '小李'},
      ],
    });
    expect((await api.invitePage()).rows.single.displayName, '小李');
  });

  test('真的没有邀请过 → 空列表,不是异常', () async {
    final api = apiWith(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'total': 0, 'rows': <dynamic>[]},
    });
    expect((await api.invitePage()).rows, isEmpty);
  });

  test('未登录仍然抛 —— 别把「请先登录」渲成「还没邀请过人」', () async {
    final api = apiWith(<String, dynamic>{'code': 401, 'msg': '请先登录'});
    await expectLater(
      api.invitePage(),
      throwsA(predicate((Object e) => e.toString().contains('请先登录'))),
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
