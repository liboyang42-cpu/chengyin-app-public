// 「均分为 0」和「还没有评价」是两件事,后端 SQL 对没有评价的人也给
// avgRating=COALESCE(...,0)=0 —— 只有 reviewCount 能把两者分开(coop_mybiz.dart)。
// 这正是本项目反复撞到的那一类:把「没拿到 / 还没发生」说成「数值是 0」。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/feature/coop/coop_mybiz_page.dart';

class _FakeCoopApi extends CoopApi {
  _FakeCoopApi(DioClient client, this._reply) : super(client);
  final Map<String, dynamic> _reply;

  @override
  Future<Map<String, dynamic>> myBiz() async => _reply;
}

Future<void> _pump(WidgetTester t, Map<String, dynamic> reply) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async => null,
  );
  final client = DioClient(TokenStore(const FlutterSecureStorage()));
  await t.pumpWidget(ProviderScope(
    overrides: <dynamic>[
      coopApiProvider.overrideWithValue(_FakeCoopApi(client, reply)),
    ].cast(),
    child: const MaterialApp(home: CoopMyBizPage()),
  ));
  await t.pumpAndSettle();
}

void main() {
  final ratingText = find.byKey(const Key('coop_mybiz_rating_text'));

  testWidgets('★★ 没有评价:avgRating=0 且 reviewCount=0 → 不能说「0 分」', (WidgetTester t) async {
    await _pump(t, <String, dynamic>{
      'credit': <String, dynamic>{'fulfillmentRate': 100, 'violationCount': 0},
      'review': <String, dynamic>{'avgRating': 0, 'reviewCount': 0},
      'settlements': <dynamic>[],
    });
    expect(find.text('还没有评价'), findsOneWidget,
        reason: '真的没有评价时要照实说,不能被下面那条一起吞掉');
    expect(
      (t.widget(ratingText) as Text).data,
      '还没有评价',
      reason: '0 分和没有评价长得一样(后端都给 avgRating=0),只有 reviewCount 能区分',
    );
  });

  testWidgets('★ 真有评价:avgRating 照实显示,不能被上一条一起吞掉', (WidgetTester t) async {
    await _pump(t, <String, dynamic>{
      'credit': <String, dynamic>{'fulfillmentRate': 100, 'violationCount': 0},
      'review': <String, dynamic>{'avgRating': 4.5, 'reviewCount': 12},
      'settlements': <dynamic>[],
    });
    expect(
      (t.widget(ratingText) as Text).data,
      '4.5 分',
      reason: '有真实评分时必须显示出来,不能因为处理了「没有评价」态就连带吞掉了这条',
    );
    expect(find.text('共 12 条'), findsOneWidget);
    expect(find.text('还没有评价'), findsNothing);
  });

  testWidgets('结算记录为空 → 空态提示,不是加载失败', (WidgetTester t) async {
    await _pump(t, <String, dynamic>{
      'credit': <String, dynamic>{'fulfillmentRate': 100, 'violationCount': 0},
      'review': <String, dynamic>{'avgRating': 0, 'reviewCount': 0},
      'settlements': <dynamic>[],
    });
    expect(find.text('还没有结算记录'), findsOneWidget);
  });

  testWidgets('★ 结算金额缺席(待结算)不显示 ¥0.00', (WidgetTester t) async {
    await _pump(t, <String, dynamic>{
      'credit': <String, dynamic>{'fulfillmentRate': 100, 'violationCount': 0},
      'review': <String, dynamic>{'avgRating': 0, 'reviewCount': 0},
      'settlements': <dynamic>[
        <String, dynamic>{'id': 1, 'topicId': 9, 'status': 0},
      ],
    });
    expect(find.textContaining('¥0.00'), findsNothing,
        reason: 'amount 字段缺席是「还没算出来」,不是「金额是 0」');
    expect(find.text('主题 #9'), findsOneWidget,
        reason: 'mySettlements 不带 topicName,兜底用 主题 #id,不编一个假名字');
  });
}
