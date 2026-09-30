// 章节点位的两条码 + 点位 AI 角色(7 条)+ 门店声音状态(1 条)。
//
// ★★ 这一批的风险**不在"没接",而在"接到了隔壁端点"** —— 全都是
//   HTTP 200、一句报错都没有,只是数据没落在该落的地方:
//     · 章节点位的角色(`/chapter-node/npc/*`)与门店形象(`/npc/*`)是两套,
//       后端明写「节点 NPC 不得复用门店形象端点」;
//     · 节点侧录音收的是**一段** `voiceSample`,门店侧收的是五段 `sampleUrls`,
//       发错名字后端绑不上,表现只是"提交成功但永远没声音";
//     · 签名是裸参数 ⇒ 必须发**表单**;发 JSON 参数全变 null 且 HTTP 200。
//
// ★ 真源:`~/城瘾app/xcx-ref`(master@90e66d70)
//   · 现场打卡码 pages/merchant/game-node/index.js:556
//   · 海报码     pages/topic/merchantinfo/merchantinfo.js:2858
//   · 点位角色   components/cy/node-npc-form/index.js:81/273/366/395/417
//   · 门店声音   pages/merchant/decor/ai-npc/index.js:506

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/merchant_npc_api.dart';
import 'package:chengyin_app/data/models/merchant_npc.dart';

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

  Map<String, String> formFields(RequestOptions o) => <String, String>{
    for (final MapEntry<String, String> e in (o.data as FormData).fields)
      e.key: e.value,
  };

  group('现场打卡码', () {
    test('★★ 走表单,且打到 live-checkin-code —— 不是海报码那条', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'code': 'CY-LIVE',
          'qrcodeUrl': 'https://x/live.png',
          'ttlMs': 60000,
        },
      });
      final Map<String, dynamic> d = await r.api.chapterNodeLiveCheckinCode(5);
      expect(
        r.sent.single.data,
        isA<FormData>(),
        reason: '后端签名是裸参数;发 JSON 会让参数全变 null,而且一句报错都没有',
      );
      expect(r.sent.single.path, '/api/merchant/chapter-node/live-checkin-code');
      expect(formFields(r.sent.single), <String, String>{'nodeId': '5'});
      expect(d['ttlMs'], 60000);
    });
  });

  group('点位角色', () {
    test('★★ detail 走表单;data:null = 没配过,是空态不是错误', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': null});
      final Map<String, dynamic>? d = await r.api.chapterNodeNpcDetail(5);
      expect(r.sent.single.path, '/api/merchant/chapter-node/npc/detail');
      expect(r.sent.single.data, isA<FormData>());
      expect(
        d,
        isNull,
        reason: '把"没配过"抛成异常,商家第一次进来看到的会是报错页',
      );
    });

    test('★ 承接失效的报错原文透传 —— 那是权限态,重试解决不了', () async {
      final r = build(<String, dynamic>{
        'code': 500,
        'msg': '承接已失效或未生效,不能编辑节点内容',
      });
      await expectLater(
        r.api.chapterNodeNpcDetail(5),
        throwsA(predicate((Object e) => e.toString().contains('承接已失效'))),
      );
    });

    test('★★ save 只发后端收的四个字段,不夹带归属/审核态', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.chapterNodeNpcSave(
        nodeId: 5,
        name: '阿福',
        avatar: 'https://x/a.png',
        greeting: '来杯咖啡吧',
      );
      expect(r.sent.single.path, '/api/merchant/chapter-node/npc/save');
      expect(formFields(r.sent.single), <String, String>{
        'nodeId': '5',
        'name': '阿福',
        'avatar': 'https://x/a.png',
        'greeting': '来杯咖啡吧',
      });
    });

    test('★ 招呼语空也要发出去 —— 后端按它落"清空招呼语"', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await r.api.chapterNodeNpcSave(nodeId: 5, name: '阿福', avatar: 'https://x/a.png');
      final Map<String, String> f = formFields(r.sent.single);
      expect(f.containsKey('greeting'), isTrue, reason: '不发的话旧招呼语会留在库里');
      expect(f['greeting'], '');
    });

    test('★★ 录音提交发的是**一段** voiceSample,不是门店的五段数组', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'voiceStatus': 1},
      });
      await r.api.chapterNodeNpcVoiceEnroll(
        nodeId: 5,
        voiceSample: 'https://x/one.mp3',
      );
      expect(
        r.sent.single.path,
        '/api/merchant/chapter-node/npc/voice/enroll',
      );
      final Map<String, String> f = formFields(r.sent.single);
      expect(f, <String, String>{'nodeId': '5', 'voiceSample': 'https://x/one.mp3'});
      expect(
        f.containsKey('sampleUrls'),
        isFalse,
        reason: 'sampleUrls 是**门店**侧的字段名;发过去后端绑不上,'
            '表现只是"提交成功但永远没声音"',
      );
    });

    test('reset 走表单只带 nodeId', () async {
      final r = build(<String, dynamic>{'code': 200, 'data': <dynamic>[]});
      await r.api.chapterNodeNpcVoiceReset(5);
      expect(r.sent.single.path, '/api/merchant/chapter-node/npc/voice/reset');
      expect(formFields(r.sent.single), <String, String>{'nodeId': '5'});
    });

    test('status 走表单带 nodeId,四态原样带回', () async {
      final r = build(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{'voiceStatus': 2, 'voiceSample': 'https://x/one.mp3'},
      });
      final Map<String, dynamic> d = await r.api.chapterNodeNpcVoiceStatus(5);
      expect(r.sent.single.path, '/api/merchant/chapter-node/npc/voice/status');
      expect(formFields(r.sent.single), <String, String>{'nodeId': '5'});
      expect(d['voiceStatus'], 2);
    });
  });

  group('门店声音状态', () {
    test('★ 打到 /api/merchant/npc/voice/status(两条 status 别互相替代)', () async {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      final List<RequestOptions> sent = <RequestOptions>[];
      c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
        sent.add(o);
        return <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'voiceStatus': 2, 'voiceSample': 'https://x/v.mp3'},
        };
      });
      final NpcVoiceStatus st = await MerchantNpcApi(c).voiceStatus();
      expect(sent.single.path, '/api/merchant/npc/voice/status');
      expect(st.isReady, isTrue);
      expect(st.voiceSample, 'https://x/v.mp3');
    });

    test('★ 生成中说清"稍后自动刷新",不是让人干等', () async {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      c.dio.httpClientAdapter = _StubAdapter(
        (RequestOptions o) => <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{'voiceStatus': 1},
        },
      );
      final NpcVoiceStatus st = await MerchantNpcApi(c).voiceStatus();
      expect(st.isGenerating, isTrue);
      expect(st.label, '声音生成中…(稍后自动刷新)');
    });

    test('★ 非 200 抛出去,别把失败说成"未配置"', () async {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      c.dio.httpClientAdapter = _StubAdapter(
        (RequestOptions o) => <String, dynamic>{'code': 500, 'msg': '查询失败'},
      );
      await expectLater(
        MerchantNpcApi(c).voiceStatus(),
        throwsA(predicate((Object e) => e.toString().contains('查询失败'))),
      );
    });
  });

  group('门店形象读取', () {
    (MerchantNpcApi, List<RequestOptions>) buildNpc(
      Map<String, dynamic> reply,
    ) {
      final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
      final List<RequestOptions> sent = <RequestOptions>[];
      c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
        sent.add(o);
        return reply;
      });
      return (MerchantNpcApi(c), sent);
    }

    test(
      '★★ 打到 /api/merchant/npc/profile —— /npc/info 后端全树不存在,打过去是 404',
      () async {
        final (MerchantNpcApi api, List<RequestOptions> sent) = buildNpc(
          <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{
              'id': 9,
              'name': '老周',
              'avatar': 'px1:3',
              'greeting': '来杯咖啡吧',
              'persona': '说话慢,先问客人今天累不累',
              'auditStatus': 1,
              'enabled': 1,
              'voiceStatus': 2,
            },
          },
        );

        final MerchantNpcProfile p = await api.myProfile();
        expect(
          sent.single.path,
          '/api/merchant/npc/profile',
          reason: '真源 ai-npc/index.js:125 打的就是这条;打 /npc/info 编辑页回填永远是空的',
        );
        expect(sent.single.data, <String, dynamic>{});
        expect(p.name, '老周');
        expect(p.avatar, 'px1:3');
        expect(p.persona, '说话慢,先问客人今天累不累');
        expect(p.isApproved, isTrue);
      },
    );

    test('★ 没配过 = data 为 null → 空表单,不是异常', () async {
      final (MerchantNpcApi api, List<RequestOptions> _) = buildNpc(
        <String, dynamic>{'code': 200, 'data': null},
      );

      final MerchantNpcProfile p = await api.myProfile();
      expect(p.configured, isFalse);
      expect(p.name, '');
      expect(p.avatar, isNull);
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
