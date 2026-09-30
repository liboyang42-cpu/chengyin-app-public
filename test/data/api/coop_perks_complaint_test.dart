// 合作权益模板 / 供给申报 / 入驻章节 / 互评 / 履约率 / 投诉,共十条。
//
// 三条是"写了也不生效、而用户以为生效了"的类别 —— 全部靠断言请求体来防:
//
//   ① `/coop/offer/enroll`:服务端把 id/topicId/merchantId/quotaUsed/status
//      **一律清掉**(防前端越权塞值)。客户端发它们不只是白发,
//      更会在界面上做出"可以选主题/改状态"的错觉。
//
//   ② `/coop/complaint/report`:后端**只信任 topicId + reason**,
//      过错方/垫付额/过错比例/扣划额/status/handler 全由客服后台设。
//      界面上出现"选择过错方""填写赔付金额"= 用户以为自己索赔了,其实什么都没发生。
//
//   ③ `/coop/perk-template/save`:后端 `body.setId(null)` —— **只新增不更新**。
//      做成"编辑"的话,改一次多一条模板,而用户以为改了原来那条。
//
// 另有一条商业机密闸:`/coop/perks/list` 对发起方主动把 unitCost 置 null。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
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

  ({CoopApi api, List<RequestOptions> sent}) build(Map<String, dynamic> reply) {
    final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
    final List<RequestOptions> sent = <RequestOptions>[];
    c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
      sent.add(o);
      return reply;
    });
    return (api: CoopApi(c), sent: sent);
  }

  Map<String, dynamic> body(RequestOptions o) =>
      (o.data as Map).cast<String, dynamic>();

  group('★★ 入驻章节:服务端接管的字段不许发', () {
    test('五个字段全被剔掉', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.enrollChapterOffer(<String, dynamic>{
        'id': 1,
        'topicId': 2,
        'merchantId': 3,
        'quotaUsed': 4,
        'status': 5,
        'termsMode': 'PERK',
        'quota': 20,
      });
      final Map<String, dynamic> b = body(r.sent.single);
      for (final String k in <String>[
        'id',
        'topicId',
        'merchantId',
        'quotaUsed',
        'status',
      ]) {
        expect(
          b.containsKey(k),
          isFalse,
          reason: '$k 由服务端接管;发它会在界面上做出"可以改"的错觉',
        );
      }
      // 真正该发的还在。
      expect(b['termsMode'], 'PERK');
      expect(b['quota'], 20);
    });

    test('★ 这条是 ③ 能不能卖票的前置 —— 路径别写错', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.enrollChapterOffer(<String, dynamic>{'quota': 1});
      expect(r.sent.single.path, '/api/coop/offer/enroll');
    });
  });

  group('★★ 投诉:只发 topicId + reason', () {
    test('请求体就这两个键', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.reportComplaint(topicId: 7, reason: '商家没按承诺提供权益');
      expect(body(r.sent.single).keys.toSet(), <String>{'topicId', 'reason'});
    });

    test('★ 界面上不许有"过错方/赔付额"这类输入', () {
      // 后端一律不取,填了也不生效 —— 而用户会以为自己已经索赔了。
      final String code = codeOf('lib/data/api/coop_api.dart');
      for (final String forbidden in <String>[
        'faultParty',
        'advanceAmount',
        'faultRatio',
        'deductAmount',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: '$forbidden 由客服后台设,客户端发它是在骗用户',
        );
      }
    });

    test('非参与者被拒 —— 原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '仅本主题已支付参与者可投诉'});
      await expectLater(
        r.api.reportComplaint(topicId: 7, reason: 'x'),
        throwsA(predicate((Object e) => e.toString().contains('已支付参与者'))),
      );
    });

    test('重复建单被拒 —— 原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '你对该主题已有处理中的投诉'});
      await expectLater(
        r.api.reportComplaint(topicId: 7, reason: 'x'),
        throwsA(predicate((Object e) => e.toString().contains('处理中的投诉'))),
      );
    });

    test('★★ 选择源必须是 complaint/topics,不能拿「我参与的」顶替', () {
      final String code = codeOf('lib/data/api/coop_api.dart');
      expect(
        code.contains("'/api/coop/complaint/topics'"),
        isTrue,
        reason:
            '换一个选择源必然与受理口漂:'
            '那条链路会砍掉结束超 7 天的主题,而投诉没有时间窗',
      );
    });
  });

  group('权益模板', () {
    test('★ 保存返回新模板 id;没给就抛', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'msg': '已保存',
        'data': <String, dynamic>{'id': 31},
      });
      expect(
        await r.api.savePerkTemplate(<String, dynamic>{'name': '一杯手冲'}),
        31,
      );

      final r2 = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await expectLater(
        r2.api.savePerkTemplate(<String, dynamic>{'name': 'x'}),
        throwsA(isA<Exception>()),
      );
    });

    test('★ 五道校验的原话都要透传 —— 它们本身就是修复指引', () async {
      for (final String msg in <String>[
        '请填写权益名称',
        '权益类型不合法',
        '权益零售价须为不超过99999999.99的正数，最多两位小数',
        '成本价须为0至99999999.99，最多两位小数',
        '请填写正整数可接待份数',
      ]) {
        final r = build(<String, dynamic>{'code': 500, 'msg': msg});
        await expectLater(
          r.api.savePerkTemplate(<String, dynamic>{}),
          throwsA(predicate((Object e) => e.toString().contains(msg))),
        );
      }
    });

    test('删除只发 id', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.deletePerkTemplate(9);
      expect(body(r.sent.single), <String, dynamic>{'id': 9});
    });
  });

  group('供给申报', () {
    test('attach 返回申报条数', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'count': 3},
      });
      expect(
        await r.api.attachPerks(inviteId: 5, templateIds: <int>[1, 2, 3]),
        3,
      );
    });

    test('★★ 发起方拿到的 unitCost 是 null —— 不许兜成 0', () async {
      // 后端对发起方主动 setUnitCost(null)。那是商业机密不是"没填",
      // 兜成 0 等于对发起方谎称对方的成本是零。
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <dynamic>[
          <String, dynamic>{'id': 1, 'name': '一杯手冲', 'retailValue': '28.00'},
        ],
      });
      final Map<String, dynamic> perk = (await r.api.perksOfInvite(5)).single;
      expect(perk.containsKey('unitCost'), isFalse);
      expect(perk['unitCost'], isNull);

      // 代码里也不许出现给 unitCost 兜零的写法。
      final String code = codeOf('lib/data/api/coop_api.dart');
      expect(code.contains("unitCost'] ?? 0"), isFalse);
      expect(code.contains("unitCost'] ?? '0"), isFalse);
    });

    test('★ 非合作双方 → 「无权查看」(防 IDOR),原文透传', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '无权查看'});
      await expectLater(
        r.api.perksOfInvite(5),
        throwsA(predicate((Object e) => e.toString().contains('无权查看'))),
      );
    });
  });

  group('互评与履约率', () {
    test('★ 评分越界与自评的报错原文透传', () async {
      for (final String msg in <String>['请打 1~5 分', '不能评价自己']) {
        final r = build(<String, dynamic>{'code': 500, 'msg': msg});
        await expectLater(
          r.api.saveReview(topicId: 1, toId: 2, rating: 9),
          throwsA(predicate((Object e) => e.toString().contains(msg))),
        );
      }
    });

    test('不填评价内容就不发这个键', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.saveReview(topicId: 1, toId: 2, rating: 5);
      expect(body(r.sent.single).keys.toSet(), <String>{
        'topicId',
        'toId',
        'rating',
      });
    });

    test('★ credit 不传 memberId = 查自己', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.creditSummary();
      expect(body(r.sent.single).isEmpty, isTrue);

      final r2 = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r2.api.creditSummary(memberId: 42);
      expect(body(r2.sent.single)['memberId'], 42);
    });

    test('★★ 暂停供给:路径 + body 只有 offerId', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.pauseCircleSupply(66);
      expect(r.sent.single.path, '/api/coop/offer/circle-supply/pause');
      expect(body(r.sent.single), <String, dynamic>{'offerId': 66});
    });

    test('★★ 重新确认:路径拼错就成"点了没反应",body 只有 offerId', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.reconfirmCircleSupply(66);
      expect(
        r.sent.single.path,
        '/api/coop/offer/circle-supply/reconfirm-current',
      );
      expect(body(r.sent.single), <String, dynamic>{'offerId': 66});
    });

    test('★ 暂停失败:后端原话透传,不吞成通用失败', () async {
      final r = build(<String, dynamic>{'code': 500, 'msg': '供给不存在或已暂停'});
      await expectLater(
        r.api.pauseCircleSupply(66),
        throwsA(predicate((Object e) => e.toString().contains('供给不存在或已暂停'))),
      );
    });

    test('review/summary 返回 summary + reviews 两段', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'summary': <String, dynamic>{'avg': 4.6, 'count': 12},
          'reviews': <dynamic>[],
        },
      });
      final Map<String, dynamic> d = await r.api.reviewSummary(9);
      expect((d['summary'] as Map)['count'], 12);
      expect(d['reviews'], isA<List<dynamic>>());
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
