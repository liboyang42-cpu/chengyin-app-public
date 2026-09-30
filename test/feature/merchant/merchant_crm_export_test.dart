// 客户名册页的「导出脱敏 Excel」。
//
// ★★ 三条判据,每一条对应一个真源里的硬约束:
//   ① 能力位没开就不摆按钮 —— `canExportCrm` 从 `/api/merchant/access/me` 读
//      (真源 utils/merchant-access-policy.js:134),不在客户端自己推;
//   ② 导出的是**当前视图**:关键词要跟着走,不然导出来是全量;
//   ③ 重试复用同一个 requestId —— 后端按它幂等,换新的 = 多一个导出任务。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';

import '../../support/fake_crm_console_api.dart';

class _FakePageParityApi implements PageParityApi {
  _FakePageParityApi({this.canExport = true});

  final bool canExport;

  /// 轮询返回什么。null = 一路 SUCCESS。
  Map<String, dynamic>? status;
  Map<String, dynamic> createReply = <String, dynamic>{
    'id': 12,
    'status': 'PENDING',
    'downloadToken': 'tok-1',
  };

  final List<String> requestIds = <String>[];
  Map<String, dynamic>? lastQuery;
  int statusCalls = 0;

  @override
  Future<Map<String, dynamic>> merchantAccess() async => <String, dynamic>{
    'active': true,
    // 名册能读:导出条渲染在列表之上,读不了名册的岗位根本到不了这一步。
    'canReadCrm': true,
    'canExportCrm': canExport,
  };

  @override
  Future<Map<String, dynamic>> createCrmExport({
    required String requestId,
    required Map<String, dynamic> query,
  }) async {
    requestIds.add(requestId);
    lastQuery = query;
    return createReply;
  }

  @override
  Future<Map<String, dynamic>> crmExportStatus(int taskId) async {
    statusCalls++;
    return status ??
        <String, dynamic>{'id': taskId, 'status': 'SUCCESS', 'rowCount': 37};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(_FakePageParityApi api) {
  return ProviderScope(
    overrides: [
      pageParityApiProvider.overrideWithValue(api),
      // 名册 / 分群走真接口的话会打网络;这一组用例只验导出链路,
      // 给一页空名册即可(页面落在「还没有客户」,不会去点别的)。
      merchantCrmConsoleApiProvider.overrideWithValue(FakeCrmConsoleApi()),
    ],
    child: const MaterialApp(home: MerchantCustomerPage()),
  );
}

void main() {
  testWidgets('★★ 没有 merchant:crm:export 能力就不摆「导出」', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_FakePageParityApi(canExport: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const Key('merchant-crm-export')),
      findsNothing,
      reason: '摆一个点下去必被后端拒的按钮,是本项目反复出现的缺陷',
    );
    expect(find.byKey(const Key('merchant-crm-export-strip')), findsNothing);
  });

  testWidgets('★★ 先筛「回头客」再导出:导的是当前视图,不是全量', (WidgetTester tester) async {
    final _FakePageParityApi api = _FakePageParityApi();
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('回头客'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('merchant-crm-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      api.lastQuery?['segment'],
      'repeat',
      reason: '在「回头客」下点导出却拿到全量名单 = 入口点得到、口径对不上'
          '(快照 _customerQuery(1) 把六个筛选字段一起发)',
    );
  });

  testWidgets('★★ 有能力位:导出 → 轮询 → 就绪,状态条一路说清', (WidgetTester tester) async {
    final _FakePageParityApi api = _FakePageParityApi();
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('merchant-crm-export')), findsOneWidget);
    expect(
      find.byKey(const Key('merchant-crm-export-strip')),
      findsNothing,
      reason: '还没有任务时整条不渲染 —— 空着一条栏会让人以为有内容没加载出来',
    );

    await tester.tap(find.byKey(const Key('merchant-crm-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.requestIds.length, 1);
    expect(api.requestIds.single.startsWith('crm-export-'), isTrue);
    expect(
      api.lastQuery?['keyword'],
      isNull,
      reason: '没输关键词就不发它 —— 导出跟着当前视图走',
    );
    expect(api.lastQuery?['segment'], isNull, reason: '默认分段 all 折成 null');
    expect(find.byKey(const Key('merchant-crm-export-strip')), findsOneWidget);
    expect(find.text('正在生成脱敏 Excel,可继续浏览客户'), findsOneWidget);
    expect(
      find.byKey(const Key('merchant-crm-export-download')),
      findsNothing,
      reason: '还没生成完,不给下载',
    );

    // 1.5 秒一拍,等它自己收到 SUCCESS。
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(api.statusCalls, greaterThanOrEqualTo(1));
    expect(find.text('导出已就绪(37 行)'), findsOneWidget);
    expect(find.byKey(const Key('merchant-crm-export-download')), findsOneWidget);

    // 收口之后必须停表(不然会一直打后端)。
    final int settled = api.statusCalls;
    await tester.pump(const Duration(seconds: 5));
    expect(
      api.statusCalls,
      settled,
      reason: '已经 SUCCESS 还继续轮询 = 白打后端,状态永远不会再变',
    );
  });

  testWidgets('★★ 结果不可信的那一帧不落到界面上,而是继续问', (WidgetTester tester) async {
    final _FakePageParityApi api = _FakePageParityApi()
      // 未知状态码 → tryParse 回 null。
      ..status = <String, dynamic>{'id': 12, 'status': 'QUEUED'};
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('merchant-crm-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('正在生成脱敏 Excel,可继续浏览客户'), findsOneWidget);
    expect(
      find.text('导出已就绪(37 行)'),
      findsNothing,
      reason: '编一个状态比说"没读到"更坏',
    );
    expect(find.textContaining('导出状态没读到'), findsOneWidget);
  });

  testWidgets('★ 失败态给「重新创建导出」,且复用同一个 requestId', (WidgetTester tester) async {
    final _FakePageParityApi api = _FakePageParityApi()
      // 创建时还是 PENDING,失败是**轮询**回来的(真源同路径:
      // 失败原因只在 status 响应里更新)。
      ..status = <String, dynamic>{
        'id': 12,
        'status': 'FAILED',
        'errorMessage': '模板损坏',
      };
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('merchant-crm-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('导出失败'), findsOneWidget);
    expect(find.text('模板损坏'), findsOneWidget);
    await tester.tap(find.byKey(const Key('merchant-crm-export-download')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.requestIds.length, 2);
    expect(
      api.requestIds[1],
      api.requestIds[0],
      reason: '换一个 requestId 重试 = 后端那边多一个导出任务;幂等靠的就是它不变',
    );
  });
}
