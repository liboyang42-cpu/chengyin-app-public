// AI 生成两条 + 我的模板详情。
//
// ★★ 后端把两种失败**分开**了(ApiAiController:38/41),前端必须跟着分:
//   ·「当前身份暂不支持AI创作,请切换到俱乐部或商家身份」→ 身份问题,**重试无用**
//   ·「AI 服务暂时不可用,请稍后重试」                    → 故障,**重试有用**
//   后端注释原话:「这不是身份问题,是我们的锅:如实记下来,
//   也别再对用户谎称是身份问题」。
//   ⇒ 给身份问题配一个"重试"按钮 = 让用户点到死也点不出结果。

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/ai_creator_api.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/ai_quota.dart';

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

  group('★★ 两种失败必须分开', () {
    const String roleMsg = '当前身份暂不支持AI创作,请切换到俱乐部或商家身份';
    const String faultMsg = 'AI 服务暂时不可用,请稍后重试';

    test('身份问题:不给重试,并告诉他怎么换身份', () {
      expect(AiGateResult.isRoleBlocked(roleMsg), isTrue);
      expect(
        AiGateResult.retryable(roleMsg),
        isFalse,
        reason: '配一个重试按钮 = 让用户点到死也点不出结果',
      );
      expect(AiGateResult.nextStep(roleMsg), contains('申请成为俱乐部主理人'));
    });

    test('故障:给重试,不谎称是身份问题', () {
      expect(AiGateResult.isRoleBlocked(faultMsg), isFalse);
      expect(AiGateResult.retryable(faultMsg), isTrue);
      expect(
        AiGateResult.nextStep(faultMsg),
        isNull,
        reason: '这是我们的锅,别让用户去改自己的身份',
      );
    });

    test('两条 AI 接口的失败都原文抛出,交给同一套分流', () async {
      for (final Future<Object?> Function(AiCreatorApi) call
          in <Future<Object?> Function(AiCreatorApi)>[
            (a) => a.templateFill(shopName: '静安寺', extraNote: 'x'),
            (a) => a.clubDesign(idea: '周末夜骑'),
          ]) {
        final s = stub(<String, dynamic>{'code': 500, 'msg': roleMsg});
        await expectLater(
          call(AiCreatorApi(s.client)),
          throwsA(predicate((Object e) => e.toString().contains('暂不支持AI创作'))),
        );
      }
    });
  });

  group('请求体', () {
    test('clubDesign 带上可选项', () async {
      final s = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await AiCreatorApi(
        s.client,
      ).clubDesign(idea: '夜骑', clubStyle: '轻松', targetDurationMin: 90);
      final Map<String, dynamic> b = (s.sent.single.data as Map)
          .cast<String, dynamic>();
      expect(b['clubStyle'], '轻松');
      expect(b['targetDurationMin'], 90);
    });

    test('路径各走各的', () async {
      final s1 = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await AiCreatorApi(
        s1.client,
      ).templateFill(shopName: 'x', extraNote: 'y');
      expect(s1.sent.single.path, '/api/ai/template/fill');

      final s2 = stub(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{},
      });
      await AiCreatorApi(s2.client).clubDesign(idea: 'x');
      expect(s2.sent.single.path, '/api/ai/club/design');
    });
  });

  test('我的模板详情走表单 id', () async {
    final s = stub(<String, dynamic>{
      'code': 200,
      'data': <String, dynamic>{'id': 3, 'questionAnswer': 'B'},
    });
    final Map<String, dynamic> d = await MerchantApi(
      s.client,
    ).myTemplateInfo(3);
    // 这条只给自己的模板,所以含答案这类只有拥有者能看的字段。
    expect(d['questionAnswer'], 'B');
    expect((s.sent.single.data as FormData).fields.single.value, '3');
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
