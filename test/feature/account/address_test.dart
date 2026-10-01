// 收货地址 —— 与「参与人」是同一张表。
//
// ★★ 后端只有一组端点 `/api/user/address/*`、一张表 `ums_member_address`。
//   小程序的「收货地址」与「参与人」两页,存的是**同一批行**,
//   只是显示/提交的字段不同。三个后果:
//   ① 删一条地址 = 那个参与人也没了 ⇒ 确认文案必须说清;
//   ② 参与人保存时**不发省市区** ⇒ 发了会把已填的地址覆盖成空;
//   ③ 地址列表里会混着"只填了联系人"的行 ⇒ 别显示成空白。
//
// ★★ 实体上**没有 city / area 两栏** —— `province` 装的是"省市区"整串
//   (后端 @Parameter 原文)。我第一版按常见电商模型拆成三栏,那是猜的。
//   做成三级联动的话,有两栏后端根本不收、无处可存。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/participant_api.dart';
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

  Map<String, String> form(RequestOptions o) => <String, String>{
    for (final MapEntry<String, String> e in (o.data as FormData).fields)
      e.key: e.value,
  };

  group('★★ 字段与后端实体一致', () {
    test('提交键是 detailAddress,不是 address', () async {
      final s = stub(<String, dynamic>{'code': 200});
      await AddressApi(s.client).save(
        fullName: '小李',
        mobilePhone: '13800001111',
        province: '上海市 静安区',
        detailAddress: '南京西路 1266 号',
      );
      final Map<String, String> f = form(s.sent.single);
      expect(f['detailAddress'], '南京西路 1266 号');
      expect(f.containsKey('address'), isFalse);
    });

    test('★★ 不发 city / area —— 实体上没有这两栏', () async {
      final s = stub(<String, dynamic>{'code': 200});
      await AddressApi(
        s.client,
      ).save(fullName: '小李', mobilePhone: '13800001111', province: '上海市 静安区');
      final Map<String, String> f = form(s.sent.single);
      expect(f.containsKey('city'), isFalse);
      expect(f.containsKey('area'), isFalse);
      expect(f['province'], '上海市 静安区', reason: 'province 这一栏装的就是省市区整串');
    });

    test('★ 客户端也不该有三级联动的形状', () {
      final String code = codeOf('lib/data/api/address_api.dart');
      expect(code.contains('String? city'), isFalse);
      expect(code.contains('String? area'), isFalse);
      final String page = codeOf('lib/feature/account/address_edit_page.dart');
      expect(page.contains('cityPicker'), isFalse);
    });

    test('解析用 detailAddress 键', () {
      final MemberAddress a = MemberAddress.fromJson(<String, dynamic>{
        'id': 1,
        'fullName': '小李',
        'mobilePhone': '13800001111',
        'province': '上海市 静安区',
        'detailAddress': '南京西路 1266 号',
        'isDefault': 1,
      });
      expect(a.detailAddress, '南京西路 1266 号');
      expect(a.isDefault, isTrue);
      expect(a.oneLine, '上海市 静安区 南京西路 1266 号');
    });

    test('设默认只提交 id 和 isDefault，不覆盖地址正文', () async {
      final s = stub(<String, dynamic>{'code': 200});
      await AddressApi(s.client).setDefault(7);

      expect(s.sent.single.method, 'POST');
      expect(s.sent.single.path, '/api/user/address/setDefault');
      expect(form(s.sent.single), <String, String>{
        'id': '7',
        'isDefault': '1',
      });
    });

    test('设默认失败保留后端归属错误，不回退为保存整行', () async {
      final s = stub(<String, dynamic>{'code': 500, 'msg': '地址不可用'});

      await expectLater(
        AddressApi(s.client).setDefault(7),
        throwsA(predicate((Object e) => e.toString().contains('地址不可用'))),
      );
      expect(s.sent, hasLength(1));
      expect(s.sent.single.path, '/api/user/address/setDefault');
      expect(form(s.sent.single), <String, String>{
        'id': '7',
        'isDefault': '1',
      });
    });

    test('设默认响应缺少成功码时拒绝成功，不发后续写入', () async {
      final s = stub(<String, dynamic>{});

      await expectLater(AddressApi(s.client).setDefault(7), throwsException);
      expect(s.sent, hasLength(1));
    });
  });

  group('★★ 同一张表的三个后果', () {
    test('① 删除的确认文案说清参与人也会消失', () {
      final String page = codeOf('lib/feature/account/address_list_page.dart');
      expect(
        page.contains('accountDeleteParticipantWarning(row.fullName)'),
        isTrue,
        reason: '只说"删除地址"的话,用户不知道报名时那个人也没了',
      );
    });

    test('★★ ② 参与人保存**不发**省市区 —— 发了会覆盖成空', () async {
      final s = stub(<String, dynamic>{'code': 200});
      await ParticipantApi(
        s.client,
      ).save(fullName: '小李', mobilePhone: '13800001111');
      final Map<String, String> f = form(s.sent.single);
      expect(f.keys.toSet(), <String>{
        'fullName',
        'mobilePhone',
        'isDefault',
      }, reason: '参与人页多发一个空的 detailAddress,已填的地址就被清空了');
    });

    test('③ 只填了联系人的行说清楚,不显示空白', () {
      final MemberAddress p = MemberAddress.fromJson(<String, dynamic>{
        'id': 1,
        'fullName': '小李',
        'mobilePhone': '13800001111',
      });
      expect(p.hasAddress, isFalse);
      final String page = codeOf('lib/feature/account/address_list_page.dart');
      // 真源列表行显示姓名 + 手机号 + 「用于报名联系和到场核验」
      // (pages/address/address.wxml:17-21)——不再自造「没有地址」提示。
      expect(page.contains('accountParticipantPurpose'), isTrue);
    });

    test('★ 编辑页按小程序参与人真源限制可见字段', () {
      final String page = codeOf('lib/feature/account/address_edit_page.dart');
      expect(page.contains('accountParticipantFullPurpose'), isTrue);
      expect(page.contains("const Text('省市区')"), isFalse);
      expect(page.contains("const Text('设为默认')"), isFalse);
    });
  });

  test('★ 归属在后端查询里 —— 查别人的返回"不可用"', () async {
    final s = stub(<String, dynamic>{'code': 500, 'msg': '地址不可用'});
    await expectLater(
      AddressApi(s.client).info(7),
      throwsA(predicate((Object e) => e.toString().contains('地址不可用'))),
    );
  });

  test('列表在 data.rows', () async {
    final s = stub(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{
        'rows': <dynamic>[
          <String, dynamic>{'id': 1, 'fullName': '小李'},
        ],
      },
    });
    expect((await AddressApi(s.client).list()).single.fullName, '小李');
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
