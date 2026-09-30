// 章节承接 + 章节点位 + 城市据点,共十条。
//
// ★★ 这一批最容易错的是**传输形态**,而且错了**不报错**:
//   后端有两种签名混在同一个域里 ——
//     · 裸参数(`mine(Long topicId)`)⇒ 必须发**表单**;发 JSON 绑不上,
//       所有参数变 null、HTTP 200、返回全量或空,一句报错都没有;
//     · @RequestBody ⇒ 必须发 JSON。
//   所以每条都断言了它到底发的是 FormData 还是 JSON。
//
// ★ 另一条是权限边界:后端**刻意不收整个 CmsTopicNode**,原话
//   「那样客户端能连 merchantMemberId、nodeAuditStatus、topicId 一起传进来,
//     而这三样正是权限本身」。客户端也不该发这三个。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';

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

  Set<String> formKeys(RequestOptions o) =>
      (o.data as FormData).fields.map((e) => e.key).toSet();

  Map<String, dynamic> jsonBody(RequestOptions o) =>
      (o.data as Map).cast<String, dynamic>();

  group('可邀请商家', () {
    test('★ 没定位也照发 —— 后端明确「不当错误」', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.invitableMerchants(9);
      final Map<String, dynamic> b = jsonBody(r.sent.single);
      expect(b['topicId'], 9);
      expect(
        b.containsKey('latitude'),
        isFalse,
        reason: '拿不到定位不该拦住这个功能,也不该发 null 过去',
      );
    });

    test('给了定位就带上(按距离排序)', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.invitableMerchants(9, latitude: 31.2, longitude: 121.4);
      expect(jsonBody(r.sent.single)['latitude'], 31.2);
    });

    test('非主题发布者 → 原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '缺少主题'});
      await expectLater(
        r.api.invitableMerchants(0),
        throwsA(predicate((Object e) => e.toString().contains('缺少主题'))),
      );
    });
  });

  group('章节点位', () {
    test(
      '★★ submit 不许发 merchantMemberId / nodeAuditStatus / topicId',
      () async {
        final r = build(<String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{},
        });
        await r.api.submitChapterNode(
          chapterId: 3,
          name: '静安咖啡',
          businessTime: '10:00-22:00',
        );
        final Map<String, dynamic> b = jsonBody(r.sent.single);
        for (final String forbidden in <String>[
          'merchantMemberId',
          'nodeAuditStatus',
          'topicId',
        ]) {
          expect(
            b.containsKey(forbidden),
            isFalse,
            reason:
                '$forbidden 是权限本身,后端刻意不收 —— '
                '客户端发它等于在界面上做出"可以改归属/审核态"的错觉',
          );
        }
        expect(b['chapterId'], 3);
        expect(b['name'], '静安咖啡');
      },
    );

    test('没填的字段不出现在 body 里', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.submitChapterNode(chapterId: 3);
      expect(jsonBody(r.sent.single).keys.toSet(), <String>{'chapterId'});
    });

    test(
      '★★ mine / pending / poster-code / audit 走**表单** —— 发 JSON 绑不上',
      () async {
        for (final Future<Object?> Function(MerchantApi) call
            in <Future<Object?> Function(MerchantApi)>[
              (a) => a.myChapterNodes(topicId: 7),
              (a) => a.pendingChapterNodes(7),
              (a) => a.chapterNodePosterCode(5),
              (a) => a.auditChapterNode(nodeId: 5, approve: true),
            ]) {
          final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
          await call(r.api);
          expect(
            r.sent.single.data,
            isA<FormData>(),
            reason:
                '后端签名是裸参数;发 JSON 会让参数全变 null,'
                '而且 HTTP 200、一句报错都没有',
          );
        }
      },
    );

    test('audit 的布尔转成字符串发出去', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.auditChapterNode(nodeId: 5, approve: false, reason: '照片不清');
      final FormData f = r.sent.single.data as FormData;
      final Map<String, String> m = <String, String>{
        for (final MapEntry<String, String> e in f.fields) e.key: e.value,
      };
      expect(m['approve'], 'false');
      expect(m['reason'], '照片不清');
    });

    test('poster-code 返回码与二维码地址', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'code': 'CY123',
          'qrcodeUrl': 'https://x/q.png',
          'nodeId': 5,
        },
      });
      final Map<String, dynamic> d = await r.api.chapterNodePosterCode(5);
      expect(d['code'], 'CY123');
      expect(d['qrcodeUrl'], 'https://x/q.png');
    });
  });

  group('城市据点', () {
    test('★★ save 走表单,且必带 templateId', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.saveCityNode(templateId: 12);
      expect(r.sent.single.data, isA<FormData>());
      expect(formKeys(r.sent.single), contains('templateId'));
    });

    test('★ 不传坐标就不发 —— 后端会回落到商家档案里的店址', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.saveCityNode(templateId: 12);
      final Set<String> k = formKeys(r.sent.single);
      expect(k.contains('lat'), isFalse);
      expect(k.contains('lng'), isFalse);
      expect(k, <String>{'templateId'}, reason: '发空串会让后端以为"传了坐标",绕过回落逻辑');
    });

    test('★ 配额上限的报错要原文透传(它带着具体数字)', () async {
      final r = build(<String, dynamic>{
        'code': 500,
        'msg': '在架据点已达上限(3),请先下线其他据点',
      });
      await expectLater(
        r.api.saveCityNode(templateId: 12),
        throwsA(predicate((Object e) => e.toString().contains('上限(3)'))),
      );
    });

    test('★ 「已上线据点不能复用投放申请入口」也原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '已上线据点不能复用投放申请入口'});
      await expectLater(
        r.api.saveCityNode(templateId: 12),
        throwsA(predicate((Object e) => e.toString().contains('已上线据点'))),
      );
    });

    test('★★ template/submit 走 **JSON**(后端 @RequestBody)', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': 88});
      final int id = await r.api.submitNodeTemplate(<String, dynamic>{
        'title': '拍张照',
      });
      expect(
        r.sent.single.data,
        isA<Map<String, dynamic>>(),
        reason: '这条是 @RequestBody,发表单绑不上',
      );
      expect(id, 88);
    });

    test('★ 模板没返回 id 就抛 —— 别当保存成功', () async {
      final r = build(<String, dynamic>{'code': 200});
      await expectLater(
        r.api.submitNodeTemplate(<String, dynamic>{'title': 'x'}),
        throwsA(isA<MerchantApiException>()),
      );
    });

    test('★★ 验证方式配不全的报错必须原文显示 —— 它才说得清缺哪一项', () async {
      // 后端注释:配不全就落库的话,玩家侧只会表现成「怎么答都不对」,
      // 商家还看不出哪里错了。所以这条错误消息本身就是修复指引。
      final r = build(<String, dynamic>{'code': 500, 'msg': '选择「答题」时必须填写正确答案'});
      await expectLater(
        r.api.submitNodeTemplate(<String, dynamic>{'title': 'x'}),
        throwsA(predicate((Object e) => e.toString().contains('必须填写正确答案'))),
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
