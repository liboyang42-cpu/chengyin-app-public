import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/feature/merchant/project_home_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 圈层实例(`circleThemeCode` 非空)才有「30天供给复核」这一块 ——
/// 入口的显示条件与后端 `/api/circle-theme/instance/review` 的适用范围同源。
///
/// 真源:`pages/topic/components/project-host/index.wxml:92-100`
/// + `pages/topic/merchantinfo/merchantinfo.js:1844`。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.reply);

  final Map<String, dynamic> reply;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _home({
  String circleThemeCode = 'CIRCLE-SH-31',
  String reviewedAt = '',
}) => <String, dynamic>{
  'topic': <String, dynamic>{
    'name': '夜游苏河',
    'circleThemeCode': circleThemeCode,
    'circleReviewedAt': reviewedAt,
  },
  'host': <String, dynamic>{
    'recruit': <String, dynamic>{
      'nodeTotal': 4,
      'nodeFilled': 2,
      'pendingCount': 1,
    },
    // 后端 `host.players` 是 `{paidCount}`(小程序 `merchantinfo.js:1507,1543`)。
    'players': <String, dynamic>{'paidCount': 2},
  },
};

Future<_StubAdapter> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? home,
  Map<String, dynamic>? reply,
  String? scope,
}) async {
  FlutterSecureStorage.setMockInitialValues(<String, String>{});
  await tester.binding.setSurfaceSize(const Size(390, 900));
  final adapter = _StubAdapter(
    reply ?? <String, dynamic>{'code': 200, 'data': <String, dynamic>{}},
  );
  final DioClient client = DioClient(TokenStore(const FlutterSecureStorage()));
  client.dio.httpClientAdapter = adapter;
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        projectHomeProvider(7).overrideWith((ref) async => home ?? _home()),
        dioClientProvider.overrideWithValue(client),
      ].cast(),
      child: MaterialApp(
        home: ProjectHomePage(topicId: 7, scope: scope),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  testWidgets('圈层项目:复核按钮打真实接口,并把 topicId 带过去', (WidgetTester tester) async {
    final adapter = await _pump(tester);

    expect(find.text('30天供给复核'), findsOneWidget);
    expect(find.text('尚未完成城市供给复核'), findsOneWidget);

    await tester.tap(find.byKey(const Key('project-host-circle-review')));
    await tester.pumpAndSettle();

    expect(adapter.last?.path, '/api/circle-theme/instance/review');
    expect(adapter.last?.method, 'POST');
    expect(
      (adapter.last?.data as Map<String, dynamic>?)?['topicId'],
      7,
      reason: '复核按实例发,没有 topicId 后端无从复核',
    );
    expect(find.text('供给复核已更新'), findsOneWidget);
  });

  testWidgets('已复核过就说日期,回执没给时间不许拿今天兜底', (WidgetTester tester) async {
    await _pump(tester, home: _home(reviewedAt: '2026-09-01 10:00:00'));

    expect(find.text('2026-09-01 已复核'), findsOneWidget);
    expect(find.text('尚未完成城市供给复核'), findsNothing);
  });

  testWidgets('店员代店主操作时,归属标记原样进复核提交体', (WidgetTester tester) async {
    final adapter = await _pump(tester, scope: 'MERCHANT');

    await tester.tap(find.byKey(const Key('project-host-circle-review')));
    await tester.pumpAndSettle();

    expect(
      (adapter.last?.data as Map<String, dynamic>?)?['scope'],
      'MERCHANT',
      reason: '服务端 resolveProjectOwner 读的就是它;丢了就按店员身份复核,必然被拒',
    );
  });

  testWidgets('host.players 是 {paidCount} 对象:名单入口照常渲染', (WidgetTester tester) async {
    await _pump(tester);

    // 按数组取 length 会在这里抛类型转换异常,整张「我主办的」卡都不出来。
    expect(find.text('看玩家名单(2 人)'), findsOneWidget);
  });

  testWidgets('非圈层项目不摆复核入口', (WidgetTester tester) async {
    await _pump(tester, home: _home(circleThemeCode: ''));

    expect(find.text('30天供给复核'), findsNothing);
    expect(find.byKey(const Key('project-host-circle-review')), findsNothing);
  });

  testWidgets('被复核规则拒时透传后端原文,不写成网络故障', (WidgetTester tester) async {
    final adapter = await _pump(
      tester,
      reply: <String, dynamic>{'code': 500, 'msg': '当前有效供给少于 3 家,本次不刷新'},
    );

    await tester.tap(find.byKey(const Key('project-host-circle-review')));
    await tester.pumpAndSettle();

    expect(adapter.last?.path, '/api/circle-theme/instance/review');
    expect(find.text('当前有效供给少于 3 家,本次不刷新'), findsOneWidget);
    expect(find.textContaining('网络'), findsNothing);
  });
}
