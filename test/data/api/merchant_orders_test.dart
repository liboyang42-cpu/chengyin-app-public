@Tags(<String>['needs-local-env'])
// ★★ 2026-09-05 补标 needs-local-env(此前漏标):本文件读 backendRepoPath() ——
//   仓库**外**的兄弟后端仓。dart_test.yaml 对该 tag 的定义就是「依赖本机的兄弟仓
//   (后端 / 小程序)、本机脚本或注入的密钥」,同类的 endpoint_reachability /
//   page_parity 一直是标着的,这三个是漏网。
//
//   ⚠️ 漏标的真实代价不是「多跑几条」:自托管 runner 与开发机是**同一台**,
//   所以 CI 上这些文件不会 skip,它们会去读 ~/Downloads/chengyin —— 那个仓有 16 个
//   worktree、内容随开发者切分支而变。CI 的绿因此取决于「此刻那个仓在哪个分支」,
//   而这既不可复现也没人会想到去查。2026-09-05 实测:CI 里 flutter test 跑完
//   2915 条后进程不退出、静默到 30 分钟超时,而同一条命令在同一个 workspace
//   手动跑 2 分 01 秒全过 —— 未报结果的正是这三个文件(23 条,与差额逐条吻合)。
//
//   本地仍照跑(开发机有那个兄弟仓),CI 上按 tag 排除。
library;

// 商家订单列表 + 核销台账。
//
// ★ 这一批最容易出的不是异常,是**静默失效**:
//   请求体里的字段名和后端 `OmsOrder` 的属性名对不上时,
//   Jackson **直接忽略**那个键 —— 不报错、HTTP 200、返回全量订单,
//   而界面还标着「只看售后」。
//   第一版我就写成了 `afterSaleStatus`(后端是 `aftersaleStatus`),
//   四个测试全绿,是靠去读 Java 域类才抓到的。所以第一条测试**去比对真实字段名**。

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
import '../../support/backend_repo.dart';

final String _kBackend = backendRepoPath();

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

  test('★ 筛选字段名必须和后端 OmsOrder 的属性名逐字相同', () {
    // 对不上 = Jackson 静默忽略 = 筛选条件消失,而界面还说在筛。
    final File domain = File(
      '$_kBackend/chengyinhub-system/src/main/java/'
      'com/chengyinhub/business/domain/OmsOrder.java',
    );
    if (!domain.existsSync()) {
      markTestSkipped('后端仓库不在预期路径,跳过字段名核对');
      return;
    }
    final Set<String> javaFields = RegExp(r'private\s+\w+(?:<[^>]*>)?\s+(\w+);')
        .allMatches(domain.readAsStringSync())
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
    expect(javaFields, contains('status'), reason: '正则失效了 —— 一个字段都没解析到');

    final String api = File(
      'lib/data/api/merchant_api.dart',
    ).readAsStringSync();
    final int at = api.indexOf(
      'Future<List<Map<String, dynamic>>> merchantOrders(',
    );
    expect(at, greaterThan(0));
    // ⚠️ 收尾锚点必须是 '\n  }\n' —— 用 '\n  }' 会被参数表的 `  })` 提前截断,
    //   切出来的只有参数列表,一个键都扫不到(第一版就这样,靠下面的 isNotEmpty 兜住)。
    final String body = api.substring(at, api.indexOf('\n  }\n', at));

    final Set<String> keysSent = RegExp(
      r"'(\w+)':\s",
    ).allMatches(body).map((RegExpMatch m) => m.group(1)!).toSet();
    expect(keysSent, isNotEmpty, reason: '没解析到请求体的键 —— 断言写法失效了');
    expect(
      keysSent.difference(javaFields),
      isEmpty,
      reason:
          '这些键 OmsOrder 上不存在,后端会静默忽略:'
          '${keysSent.difference(javaFields)}',
    );
  });

  test('★ 不许发 mmsMerchantId —— 卖家维度由后端锁定', () async {
    // ApiMerchantController:1009 `query.setMmsMerchantId(memberId)` 无条件覆盖。
    // 前端传了不会生效,但会让读代码的人以为这里能查别人的订单。
    final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
    await r.api.merchantOrders(status: 1);
    final Map<String, dynamic> sent = (r.sent.single.data as Map)
        .cast<String, dynamic>();
    expect(sent.containsKey('mmsMerchantId'), isFalse);
    expect(sent.keys.toSet(), <String>{'status'}, reason: '没传的筛选条件不该出现在请求体里');
  });

  test('不传筛选就发空 body —— 后端 required=false,会当全量查', () async {
    final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
    await r.api.merchantOrders();
    expect((r.sent.single.data as Map), isEmpty);
  });

  test('★ data 直接是数组(后端 success(list),不是 getDataTable)', () async {
    final r = build(<String, dynamic>{
      'code': 200,
      'data': <dynamic>[
        <String, dynamic>{'id': 7, 'status': 1},
      ],
    });
    expect(
      (await r.api.merchantOrders()).single['id'],
      7,
      reason: '只认 data.rows 的话这里会是空 —— 商家看到「暂无订单」而其实有',
    );
  });

  test('未登录抛 —— 别渲成「暂无订单」', () async {
    final r = build(<String, dynamic>{'code': 500, 'msg': '请先登录'});
    await expectLater(
      r.api.merchantOrders(),
      throwsA(predicate((Object e) => e.toString().contains('请先登录'))),
    );
  });

  test('核销台账走自己的路径,且同样收数组形态', () async {
    final r = build(<String, dynamic>{
      'code': 200,
      'data': <dynamic>[
        <String, dynamic>{'id': 3, 'memberId': 100096},
      ],
    });
    final List<Map<String, dynamic>> rows = await r.api.verificationRecords();
    expect(r.sent.single.path, '/api/merchant/verification-records');
    expect(rows.single['id'], 3);
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
