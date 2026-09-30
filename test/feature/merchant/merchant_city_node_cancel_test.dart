import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_city_node.dart';
import 'package:chengyin_app/feature/merchant/merchant_city_node_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 撤回待审认领(快照 citynode/index.js:308):不撤回,节点会锁在
/// 「已有待审申请」,别人认领不了。
void main() {
  testWidgets('待审认领可撤回:点击调到 claim/cancel 并重拉列表', (WidgetTester tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('city-node-cancel-claim-9')));
    await tester.pumpAndSettle();

    expect(api.cancelled, <int>[9], reason: '撤回用的是申请行 id(= poiId)');
    expect(api.cityNodeCalls, 2, reason: '撤回成功要重拉,行状态才会更新');
    expect(find.text('已撤回认领申请'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('投放申请 / 已审结的认领不摆撤回入口', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_FakeMerchantApi()));
    await tester.pumpAndSettle();

    expect(find.text('据点投放 · 新据点'), findsOneWidget, reason: '投放申请仍要显示');
    expect(find.byKey(const Key('city-node-cancel-claim-10')), findsNothing);
    expect(find.byKey(const Key('city-node-cancel-claim-11')), findsNothing);
  });

  testWidgets('撤回失败把后端原因说出来,不吃掉', (WidgetTester tester) async {
    final _FakeMerchantApi api = _FakeMerchantApi()..failCancel = true;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('city-node-cancel-claim-9')));
    await tester.pumpAndSettle();

    expect(find.text('该认领申请已不可撤回，请刷新后重试'), findsOneWidget);
    expect(api.cityNodeCalls, 1, reason: '失败不重拉');
    await tester.pump(const Duration(seconds: 3));
  });
}

Widget _app(MerchantApi api) {
  return ProviderScope(
    overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
    child: const MaterialApp(home: MerchantCityNodePage()),
  );
}

class _FakeMerchantApi implements MerchantApi {
  int cityNodeCalls = 0;
  final List<int> cancelled = <int>[];
  bool failCancel = false;

  @override
  Future<CityNodeHome> cityNodes() async {
    cityNodeCalls += 1;
    return CityNodeHome(
      applications: <CityNodeApplication>[
        CityNodeApplication.fromJson(<String, dynamic>{
          'id': 9,
          'poiName': '老码头咖啡',
          'applicationType': 2,
          'auditStatus': 0,
        }),
        CityNodeApplication.fromJson(<String, dynamic>{
          'id': 10,
          'poiName': '新据点',
          'applicationType': 1,
          'auditStatus': 0,
        }),
        CityNodeApplication.fromJson(<String, dynamic>{
          'id': 11,
          'poiName': '已通过的认领',
          'applicationType': 2,
          'auditStatus': 1,
        }),
      ],
    );
  }

  @override
  Future<void> cancelClaim(int poiId) async {
    cancelled.add(poiId);
    if (failCancel) {
      throw MerchantApiException('该认领申请已不可撤回，请刷新后重试');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
