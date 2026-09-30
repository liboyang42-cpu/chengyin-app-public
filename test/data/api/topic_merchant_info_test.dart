// M-12 降级位:商家浏览「招商中、尚未对玩家上架」的主题。
//
// 真源 `pages/topic/merchantinfo/merchantinfo.js` `loadBrowseData`:
// 玩家接口 `/api/topic/info-to-user` 回「不存在」时改走与招商列表同口径的
// `/api/topic/info-to-merchant`;App 对等页 `MerchantRecruitPage` 原来只会
// 拿玩家投影空回包渲一个无名页面。这里钉两端点的请求形状与降级触发。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_state.dart';

DioClient clientRouting(
  Map<String, dynamic> Function(RequestOptions o) reply,
  List<RequestOptions> sink,
) {
  final DioClient c = DioClient(TokenStore(const FlutterSecureStorage()));
  c.dio.httpClientAdapter = _StubAdapter((RequestOptions o) {
    sink.add(o);
    return reply(o);
  });
  return c;
}

Map<String, String> form(RequestOptions o) => <String, String>{
  for (final MapEntry<String, String> e in (o.data as FormData).fields)
    e.key: e.value,
};

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  group('topicApi.detailForMerchant', () {
    test('POST /api/topic/info-to-merchant 表单 id,回包按玩家同形状解析', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final TopicApi api = TopicApi(
        clientRouting((RequestOptions o) {
          return <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{'id': 42, 'name': '城市咖啡巡游'},
          };
        }, sent),
      );

      final detail = await api.detailForMerchant(42);

      expect(sent.single.path, '/api/topic/info-to-merchant');
      expect(form(sent.single)['id'], '42');
      expect(detail.name, '城市咖啡巡游');
    });

    test('服务端拒绝时点名失败原因,不静默回空详情', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final TopicApi api = TopicApi(
        clientRouting((RequestOptions o) {
          return <String, dynamic>{'code': 500, 'msg': '商家才能报名'};
        }, sent),
      );

      expect(
        api.detailForMerchant(42),
        throwsA(
          isA<Exception>().having(
            (Exception e) => '$e',
            'message',
            contains('商家才能报名'),
          ),
        ),
      );
    });
  });

  group('MerchantRecruitPage M-12 降级', () {
    Future<RecruitState> loadTopic(
      Map<String, dynamic> Function(RequestOptions o) route,
    ) async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final container = ProviderContainer(
        overrides: [
          dioClientProvider.overrideWithValue(clientRouting(route, sent)),
        ],
      );
      addTearDown(container.dispose);
      final state = await container.read(merchantRecruitProvider(42).future);
      expect(
        sent.map((RequestOptions o) => o.path),
        contains('/api/topic/info-to-merchant'),
        reason: '玩家投影空回包后必须真发商家投影请求',
      );
      return state;
    }

    Map<String, dynamic> unlistedToPlayer(RequestOptions o) {
      switch (o.path) {
        case '/api/topic/info-to-user':
          // 后端对未对玩家上架的主题回 code=500「主题活动不存在」、data 缺失,
          // 现网解析口径下 detail() 得到空 name(不抛)。
          return <String, dynamic>{'code': 500, 'msg': '主题活动不存在'};
        case '/api/topic/info-to-merchant':
          return <String, dynamic>{
            'code': 200,
            'data': <String, dynamic>{'id': 42, 'name': '招商中的路线'},
          };
        case '/api/topic/merchant-recruitment-chapters':
          return <String, dynamic>{
            'code': 200,
            'data': <dynamic>[
              <String, dynamic>{
                'id': 7,
                'name': '第一章 · 咖啡',
                'category': '咖啡',
                'required': 1,
              },
            ],
          };
        case '/api/merchant/chapter-application/mine':
          return <String, dynamic>{'code': 200, 'data': <dynamic>[]};
        case '/api/merchant/chapter-node/mine':
          return <String, dynamic>{'code': 200, 'rows': <dynamic>[]};
        default:
          return <String, dynamic>{'code': 200, 'data': <dynamic>[]};
      }
    }

    test('玩家投影判「不存在」的招商主题,承接页经商家投影拿到真名与章节', () async {
      final RecruitState state = await loadTopic(unlistedToPlayer);

      expect(state.mode, RecruitMode.chapterRecruit);
      expect(state.topicName, '招商中的路线', reason: '名字必须来自降级后的商家投影');
      expect(state.chapters.map((RecruitChapter c) => c.name), <String>[
        '第一章 · 咖啡',
      ]);
    });

    test('已上架主题不降级:玩家投影有名字就一次请求都不多发', () async {
      final List<RequestOptions> sent = <RequestOptions>[];
      final container = ProviderContainer(
        overrides: [
          dioClientProvider.overrideWithValue(
            clientRouting((RequestOptions o) {
              switch (o.path) {
                case '/api/topic/info-to-user':
                  return <String, dynamic>{
                    'code': 200,
                    'data': <String, dynamic>{'id': 42, 'name': '已上架路线'},
                  };
                case '/api/topic/merchant-recruitment-chapters':
                  return <String, dynamic>{'code': 200, 'data': <dynamic>[]};
                case '/api/merchant/chapter-application/mine':
                  return <String, dynamic>{'code': 200, 'data': <dynamic>[]};
                case '/api/merchant/chapter-node/mine':
                  return <String, dynamic>{'code': 200, 'rows': <dynamic>[]};
                default:
                  return <String, dynamic>{'code': 200, 'data': <dynamic>[]};
              }
            }, sent),
          ),
        ],
      );
      addTearDown(container.dispose);

      final RecruitState state = await container.read(
        merchantRecruitProvider(42).future,
      );

      expect(state.topicName, '已上架路线');
      expect(
        sent.map((RequestOptions o) => o.path),
        isNot(contains('/api/topic/info-to-merchant')),
        reason: '已上架主题走玩家投影(带评分/评论/票务),不许反向降级',
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
