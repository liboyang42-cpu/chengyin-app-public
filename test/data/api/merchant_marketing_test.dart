// 商家营销 / 档案 / 订阅六条。
//
// ★★ `/public-home` 是**失败关闭**的:必须**恰好给一个** id 或 memberId。
//   后端原话:「都给会让两条查询路径的可见性判定含糊,都不给等于全表公开入口」。
//   ⇒ 客户端用两个命名方法强制二选一,不做成"两个都可空"的参数 ——
//     那种签名迟早会有人两个都传或都不传。
//
// ★★ `/coop-profile/save` 后端**只 set 六个字段**,传别的静默忽略。
//   界面把不可改的字段做成可编辑 = 骗用户。
//
// ★ `/merchant/events` 的时间**已按 MM-dd HH:mm 格式化好**。
//   前端再解析再格式化必然按当前年/本地时区猜 —— 那串里没有年份和时区,跨年就错。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
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

  Map<String, dynamic> body(RequestOptions o) =>
      (o.data as Map).cast<String, dynamic>();

  group('★★ 公开主页:恰好给一个 ID', () {
    test('按商家 ID 查时只发 id', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.merchantPublicHomeById(7);
      expect(body(r.sent.single), <String, dynamic>{'id': 7});
    });

    test('按会员 ID 查时只发 memberId', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.merchantPublicHomeByMember(100096);
      expect(body(r.sent.single), <String, dynamic>{'memberId': 100096});
    });

    test('★★ 客户端没有"两个都可空"的签名 —— 那种迟早两个都传/都不传', () {
      final String code = codeOf('lib/data/api/merchant_api.dart');
      // 两个命名方法各自只带一个必填参数。
      expect(code.contains('merchantPublicHomeById(int id)'), isTrue);
      expect(code.contains('merchantPublicHomeByMember(int memberId)'), isTrue);
      expect(
        code.contains('merchantPublicHome({int? id, int? memberId})'),
        isFalse,
        reason: '失败关闭的闸不该让客户端有机会同时传两个或一个都不传',
      );
    });

    test('★ 不可见时统一回「商家不存在或未开放」—— 不区分是有意的', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '商家不存在或未开放'});
      await expectLater(
        r.api.merchantPublicHomeById(999),
        throwsA(predicate((Object e) => e.toString().contains('不存在或未开放'))),
      );
    });
  });

  group('★★ 承接档案只认六个字段', () {
    test('客户端参数不超出后端白名单', () {
      // 后端 saveCoopProfile 只 set 这六个。
      const Set<String> backend = <String>{
        'capacity',
        'availableTime',
        'suitActivityTypes',
        'chargeType',
        'demand',
        'coopOpen',
      };
      final String code = codeOf('lib/data/api/merchant_api.dart');
      final int at = code.indexOf('Future<String> saveCoopProfile(');
      expect(at, greaterThan(0));
      final String seg = code.substring(at, code.indexOf('\n  }\n', at));
      final Set<String> sent = RegExp(
        r"'(\w+)': \?",
      ).allMatches(seg).map((RegExpMatch m) => m.group(1)!).toSet();
      expect(sent, isNotEmpty, reason: '没解析到请求体的键 —— 断言写法失效了');
      expect(
        sent.difference(backend),
        isEmpty,
        reason: '这些字段后端不 set,传了会被静默忽略:${sent.difference(backend)}',
      );
    });

    test('没填的字段不出现在 body 里', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '已保存'});
      await r.api.saveCoopProfile(capacity: 20, coopOpen: 1);
      expect(body(r.sent.single).keys.toSet(), <String>{
        'capacity',
        'coopOpen',
      });
    });

    test('★ demand 违规时原文透传 —— 它说得清哪段有问题', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '合作需求包含违规内容'});
      await expectLater(
        r.api.saveCoopProfile(demand: 'x'),
        throwsA(predicate((Object e) => e.toString().contains('违规内容'))),
      );
    });

    test('成功用后端原话', () async {
      final r = build(<String, dynamic>{'code': 200, 'msg': '已保存'});
      expect(await r.api.saveCoopProfile(capacity: 1), '已保存');
    });
  });

  group('列表三条', () {
    test('★ subscription 空列表 = 没有生效权益,不是加载失败', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      expect(await r.api.mySubscriptions(), isEmpty);
    });

    test('upcoming-runs 的 topicId 可空', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.upcomingRuns();
      expect(body(r.sent.single).isEmpty, isTrue);

      final r2 = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r2.api.upcomingRuns(topicId: 3);
      expect(body(r2.sent.single)['topicId'], 3);
    });

    test('★★ events 的时间原样用,不再解析格式化', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{'time': '08-19 14:30', 'text': '收入到账 ¥128.00'},
        ],
      });
      expect((await r.api.merchantEvents()).single['time'], '08-19 14:30');

      // 代码里不许出现对它再解析的写法 —— 那串没有年份和时区,跨年就错。
      final String code = codeOf('lib/data/api/merchant_api.dart');
      final int at = code.indexOf('merchantEvents()');
      final String seg = code.substring(at, at + 300);
      expect(seg.contains('DateTime.parse'), isFalse);
      expect(seg.contains('DateFormat'), isFalse);
    });

    test('clubs 后端强制 status=1,前端不传它', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.clubsForInvite(name: '夜骑');
      expect(body(r.sent.single), <String, dynamic>{'name': '夜骑'});
      expect(body(r.sent.single).containsKey('status'), isFalse);
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
