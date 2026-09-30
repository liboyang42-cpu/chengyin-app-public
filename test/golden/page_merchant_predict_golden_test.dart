// 竞猜待答(商家侧)整页快照。
//
// fixture 刻意造**语义边界**而不是漂亮数据:
//   · 一轮还剩 1 天(警示档);
//   · 一轮 0 天 + 0 人押 —— 文案必须是「今天不给就作废」与「这一轮还没有人押」,
//     「还剩 0 天 / 0 个人押了这一轮」都会被读成「不急」,而它恰恰最急。
//
// 更新基准图:flutter test --update-goldens test/golden/page_merchant_predict_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_predict_api.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_predict_page.dart';
import 'golden_theme.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

class _FakeAccess extends PageParityApi {
  _FakeAccess() : super(_dummyDioClient());

  @override
  Future<Map<String, dynamic>> merchantAccess() async => <String, dynamic>{
    'active': true,
    'canManageProjects': true,
  };
}

class _FakePredictApi extends MerchantPredictApi {
  _FakePredictApi() : super(_dummyDioClient());

  @override
  Future<List<Map<String, dynamic>>> inbox() async => <Map<String, dynamic>>[
    <String, dynamic>{
      'nodeId': 8,
      'playDay': '09-11',
      'nodeName': '河畔咖啡',
      'question': '明天哪款会卖得最好?',
      'betCount': 12,
      'daysLeft': 1,
      'options': <Map<String, dynamic>>[
        <String, dynamic>{'key': 'A', 'label': '冰美式'},
        <String, dynamic>{'key': 'B', 'label': '燕麦拿铁'},
      ],
    },
    <String, dynamic>{
      'nodeId': 9,
      'playDay': '09-12',
      'nodeName': '外滩观景平台',
      'question': '日落时这里会挤满人吗?',
      'betCount': 0,
      'daysLeft': 0,
      'options': <Map<String, dynamic>>[
        <String, dynamic>{'key': 'A', 'label': '会'},
        <String, dynamic>{'key': 'B', 'label': '不会'},
        <String, dynamic>{'key': 'C', 'label': '不好说'},
      ],
    },
  ];
}

Future<void> _pump(WidgetTester tester) async {
  setGoldenViewport(tester, const Size(390, 900));
  final GoRouter router = GoRouter(
    initialLocation: '/merchant/predict',
    routes: <RouteBase>[
      GoRoute(
        path: '/merchant/predict',
        builder: (_, _) => const MerchantPredictPage(),
      ),
      GoRoute(
        path: '/merchant',
        builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
      overrides: [
        pageParityApiProvider.overrideWithValue(_FakeAccess()),
        merchantPredictApiProvider.overrideWithValue(_FakePredictApi()),
      ],
      child: MaterialApp.router(
        theme: merchantGoldenTheme(),
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('竞猜待答:期限警示与押注人数同屏', (WidgetTester tester) async {
    await _pump(tester);
    // golden 只证明「长这样」;这三条证明「那些字符确实是这一档文案」。
    expect(find.text('今天不给就作废'), findsOneWidget);
    expect(find.text('还剩 0 天'), findsNothing);
    expect(find.text('这一轮还没有人押'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/merchant_predict_ready.png'),
    );
  });

  testWidgets('竞猜待答:展开选答案', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('给答案').first);
    await tester.pumpAndSettle();

    expect(find.text('选出正确答案'), findsOneWidget);
    expect(find.text('先不给'), findsOneWidget);
    expect(find.text('就是这个'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/merchant_predict_picking.png'),
    );
  });
}
