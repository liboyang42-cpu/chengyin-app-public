// 游客点进 topic 域:后端 401 必须变成「去登录」,不能是「检查网络 / 网络异常」。
//
// ★ 来自对生产后端的实测(2026-09-18,无 token):
//     POST /prod-api/api/topic/info-to-user      → HTTP 401 {"msg":"登录状态已失效，请重新登录"}
//     POST /prod-api/api/topic/pricing/preview   → HTTP 401 同上
//   而 app_router 的 `_loginRequiredPrefixes` **不含 /topic** —— 路由是对游客开放的,
//   设计假设与后端现实对不上(小程序不会撞上:那边人人都被微信静默登录,没有"游客")。
//
// 后果(2026-09-18 b1-sim-topic 模拟器走查实拍 tp-01/tp-03):
//   · 路线详情把 401 说成「检查网络后重试」,重试永远是死路;
//   · 定价页(资金路径)把整段原始 DioException(英文 + MDN 链接)**画在屏幕上**。
//
// 同时守住反面:网络故障**不能**也被当成要登录,否则断网用户会被反复推去登录页。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/pricing.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';
import 'package:chengyin_app/feature/topic/topic_pricing_page.dart';

DioException _http(int status) => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
    statusCode: status,
  ),
);

DioException _offline() => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  type: DioExceptionType.connectionError,
);

/// 只负责抛指定异常的定价预览 API(其余方法不会被调到)。
class _FailingTopicApi extends TopicApi {
  _FailingTopicApi(this.error)
    : super(DioClient(TokenStore(const FlutterSecureStorage())));
  final Object error;

  @override
  Future<PricingPreview> pricingPreview({
    required int topicId,
    required PricingSubType subType,
    double? leadCost,
    int? teamSize,
  }) async => throw error;
}

Widget _detail(Object error) => ProviderScope(
  overrides: [topicDetailProvider(7).overrideWith((ref) async => throw error)],
  child: const MaterialApp(home: TopicDetailPage(topicId: 7)),
);

Widget _pricing(Object error) => ProviderScope(
  overrides: [topicApiProvider.overrideWithValue(_FailingTopicApi(error))],
  child: const CupertinoApp(home: TopicPricingPage(topicId: 7)),
);

void main() {
  group('路线详情 /topic/:id', () {
    testWidgets('401 → 登录引导(不是「检查网络」)', (WidgetTester tester) async {
      await tester.pumpWidget(_detail(_http(401)));
      await tester.pumpAndSettle();

      expect(find.text('登录后查看路线详情'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('没能打开这条路线'), findsNothing);
    });

    testWidgets('断网 → 通用错误态(别把断网也推去登录)', (WidgetTester tester) async {
      await tester.pumpWidget(_detail(_offline()));
      await tester.pumpAndSettle();

      expect(find.textContaining('没能打开这条路线'), findsOneWidget);
      expect(find.text('登录后查看路线详情'), findsNothing);
    });

    testWidgets('其它 HTTP 错误(500)走通用错误态', (WidgetTester tester) async {
      await tester.pumpWidget(_detail(_http(500)));
      await tester.pumpAndSettle();

      expect(find.textContaining('没能打开这条路线'), findsOneWidget);
      expect(find.text('登录后查看路线详情'), findsNothing);
    });
  });

  group('定价 /topic/:id/pricing(资金路径)', () {
    testWidgets('401 → 登录引导,且不把原始异常画在屏幕上', (WidgetTester tester) async {
      await tester.pumpWidget(_pricing(_http(401)));
      await tester.pumpAndSettle();

      expect(find.text('登录后确认终价'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('developer.mozilla.org'), findsNothing);
    });

    testWidgets('断网 → 场景兜底文案(不是 DioException 原文)', (WidgetTester tester) async {
      await tester.pumpWidget(_pricing(_offline()));
      await tester.pumpAndSettle();

      expect(find.text('定价信息加载失败'), findsOneWidget);
      expect(find.text('网络异常，请稍后重试'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('登录后确认终价'), findsNothing);
    });

    testWidgets('500 → 同样不泄漏异常原文', (WidgetTester tester) async {
      await tester.pumpWidget(_pricing(_http(500)));
      await tester.pumpAndSettle();

      expect(find.textContaining('DioException'), findsNothing);
      expect(find.text('定价信息加载失败'), findsOneWidget);
    });

    // ★ 不能「遮盖过头」:小程序 pages/topic/pricing/index.js 是三档
    //   (业务 msg / 定价信息不完整 / 网络异常),把业务拒绝也改写成「网络异常」
    //   等于又造一条「重试永不成功」的死路(报告 P1-2/P1-5 的同一类缺陷)。
    testWidgets('业务拒绝(HTTP 200 + code≠200)照原话显示', (WidgetTester tester) async {
      await tester.pumpWidget(_pricing(Exception('缺少主题信息')));
      await tester.pumpAndSettle();

      expect(find.text('缺少主题信息'), findsOneWidget);
      expect(find.text('网络异常，请稍后重试'), findsNothing);
    });

    testWidgets('定价信息不完整 → 说清是不完整,不是网络问题', (WidgetTester tester) async {
      await tester.pumpWidget(_pricing(const PricingIncompleteException()));
      await tester.pumpAndSettle();

      expect(find.text('定价信息不完整,请稍后重试'), findsOneWidget);
      expect(find.text('网络异常，请稍后重试'), findsNothing);
    });

    testWidgets('长/含链接的异常文本仍然兜底(不整段上屏)', (WidgetTester tester) async {
      await tester.pumpWidget(_pricing(StateError('x' * 200)));
      await tester.pumpAndSettle();

      expect(find.text('网络异常，请稍后重试'), findsOneWidget);
    });
  });
}
