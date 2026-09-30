// 竞猜待答(商家侧)行为门。判据逐条对齐小程序
// `pages/merchant/predict/index.js`,只测「该红的必须红」:
//   · 有期限:0 天的文案是「今天不给就作废」,不是「还剩 0 天」;
//   · 只能结一次:没选选项就点不了「就是这个」;确认框取消 = 一个请求都不发;
//   · 服务端说了算:结算失败**留在原地**(那一轮还没结,人得能再试),
//     绝不把没结掉的卡片从列表里拿掉。
//
// 网络一律 override 成记录型假实现,不碰真 Dio。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_confirm.dart';
import 'package:chengyin_app/data/api/merchant_predict_api.dart';
import 'package:chengyin_app/data/api/page_parity_api.dart';
import 'package:chengyin_app/data/models/merchant_predict.dart';
import 'package:chengyin_app/feature/merchant/merchant_predict_page.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

class _FakeAccess extends PageParityApi {
  _FakeAccess({this.canManageProjects = true, this.throws = false})
    : super(_dummyDioClient());

  final bool canManageProjects;
  final bool throws;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> merchantAccess() async {
    calls += 1;
    if (throws) throw const MerchantPredictApiException('经营身份加载失败');
    return <String, dynamic>{
      'active': true,
      'canManageProjects': canManageProjects,
    };
  }
}

class _FakePredictApi extends MerchantPredictApi {
  _FakePredictApi({required this.rows, this.settleError})
    : super(_dummyDioClient());

  final List<Map<String, dynamic>> rows;
  final String? settleError;
  int inboxCalls = 0;
  final List<Map<String, dynamic>> settles = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> inbox() async {
    inboxCalls += 1;
    return rows;
  }

  @override
  Future<int> settle({
    required int nodeId,
    required String playDay,
    required String settledOption,
  }) async {
    settles.add(<String, dynamic>{
      'nodeId': nodeId,
      'playDay': playDay,
      'settledOption': settledOption,
    });
    if (settleError != null) {
      throw MerchantPredictApiException(settleError!);
    }
    return 7;
  }
}

class _Confirm implements CyNativeConfirmPresenter {
  _Confirm(this.result);

  final CyNativeConfirmResult result;
  final List<CyNativeConfirmRequest> requests = <CyNativeConfirmRequest>[];

  @override
  Future<CyNativeConfirmResult> show(
    BuildContext context,
    CyNativeConfirmRequest request,
  ) async {
    requests.add(request);
    return result;
  }
}

Map<String, dynamic> _round({
  int nodeId = 8,
  String playDay = '09-11',
  String nodeName = '河畔咖啡',
  String question = '明天哪款会卖得最好?',
  int betCount = 12,
  int daysLeft = 1,
}) => <String, dynamic>{
  'nodeId': nodeId,
  'playDay': playDay,
  'nodeName': nodeName,
  'question': question,
  'betCount': betCount,
  'daysLeft': daysLeft,
  'options': <Map<String, dynamic>>[
    <String, dynamic>{'key': 'A', 'label': '冰美式'},
    <String, dynamic>{'key': 'B', 'label': '燕麦拿铁'},
  ],
};

Future<void> _pump(
  WidgetTester tester, {
  required PageParityApi access,
  required MerchantPredictApi api,
  CyNativeConfirmPresenter? confirm,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/merchant/predict',
    routes: <RouteBase>[
      GoRoute(
        path: '/merchant/predict',
        builder: (_, _) => MerchantPredictPage(confirmPresenter: confirm),
      ),
      GoRoute(
        path: '/merchant',
        builder: (_, _) => const Scaffold(body: Text('ROUTE /merchant')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      // 不写 List<Override> 的显式类型:Riverpod 3 把它导出在另一处,靠推断。
      overrides: [
        pageParityApiProvider.overrideWithValue(access),
        merchantPredictApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp.router(
        theme: ThemeData(useMaterial3: true),
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('卡片文案:期限与押注人数都按小程序口径;0 天不是「还剩 0 天」', (WidgetTester tester) async {
    await _pump(
      tester,
      access: _FakeAccess(),
      api: _FakePredictApi(
        rows: <Map<String, dynamic>>[
          _round(),
          _round(nodeId: 9, playDay: '09-12', daysLeft: 0, betCount: 0),
        ],
      ),
    );

    expect(find.text('共 2 轮等你给答案'), findsOneWidget);
    expect(find.text('河畔咖啡'), findsNWidgets(2));
    expect(find.text('09-11 那一轮'), findsOneWidget);
    expect(find.text('还剩 1 天'), findsOneWidget);
    // 今天不给就作废 —— 这一档是红的,文案也不许写成「还剩 0 天」。
    expect(find.text('今天不给就作废'), findsOneWidget);
    expect(find.text('还剩 0 天'), findsNothing);
    expect(find.text('12 个人押了这一轮'), findsOneWidget);
    // 没人押的轮次不许写「0 个人押了这一轮」。
    expect(find.text('这一轮还没有人押'), findsOneWidget);
    expect(find.text('2 个选项'), findsNWidgets(2));
  });

  testWidgets('无权限:整页给「当前岗位不能结算竞猜」,不是加载失败', (WidgetTester tester) async {
    await _pump(
      tester,
      access: _FakeAccess(canManageProjects: false),
      api: _FakePredictApi(rows: <Map<String, dynamic>>[_round()]),
    );

    expect(find.text('当前岗位不能结算竞猜'), findsOneWidget);
    expect(
      find.text('结算会按规则发券,需要项目管理权限。请联系店主调整经营团队权限'),
      findsOneWidget,
    );
    expect(find.text('待答列表加载失败'), findsNothing);
  });

  testWidgets('没有待答轮次:给空态而不是空列表', (WidgetTester tester) async {
    await _pump(
      tester,
      access: _FakeAccess(),
      api: _FakePredictApi(rows: const <Map<String, dynamic>>[]),
    );

    expect(find.text('没有等你给答案的竞猜'), findsOneWidget);
    expect(find.text('玩家押完之后,那一轮会出现在这里等你公布答案'), findsOneWidget);
  });

  testWidgets('取数失败:整页错误态 + 重试真的会再拉一次', (WidgetTester tester) async {
    final api = _FakePredictApi(rows: const <Map<String, dynamic>>[]);
    await _pump(tester, access: _FakeAccess(throws: true), api: api);

    expect(find.text('待答列表加载失败'), findsOneWidget);
    expect(api.inboxCalls, 0, reason: '身份都没拿到就不该去拉待办');

    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('待答列表加载失败'), findsOneWidget);
  });

  testWidgets('没选选项时「就是这个」点不动;确认取消 = 一个请求都不发', (WidgetTester tester) async {
    final api = _FakePredictApi(
      rows: <Map<String, dynamic>>[_round()],
    );
    final confirm = _Confirm(CyNativeConfirmResult.cancelled);
    await _pump(tester, access: _FakeAccess(), api: api, confirm: confirm);

    await tester.tap(find.text('给答案'));
    await tester.pumpAndSettle();
    expect(find.text('选出正确答案'), findsOneWidget);

    // 未选选项 → 主键禁用(点下去什么都不该发生)。
    await tester.tap(find.text('就是这个'));
    await tester.pumpAndSettle();
    expect(confirm.requests, isEmpty);
    expect(api.settles, isEmpty);

    await tester.tap(find.text('燕麦拿铁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('就是这个'));
    await tester.pumpAndSettle();

    // 确认框把后果写全(一次性 + 会发券),取消后不发请求。
    expect(confirm.requests.single.title, '公布答案「燕麦拿铁」?');
    expect(
      confirm.requests.single.content,
      '押中的人会按你配的规则拿到奖励。这一轮只能公布一次,公布后不能改。',
    );
    expect(confirm.requests.single.confirmText, '公布并结算');
    expect(api.settles, isEmpty);
    expect(find.text('河畔咖啡'), findsOneWidget, reason: '取消后卡片必须留在原地');
  });

  testWidgets('结算成功:按 rid 参数发对,提示人数,并把这一轮从列表拿掉', (WidgetTester tester) async {
    final api = _FakePredictApi(
      rows: <Map<String, dynamic>>[_round(), _round(nodeId: 9, playDay: '09-12')],
    );
    final confirm = _Confirm(CyNativeConfirmResult.confirmed);
    await _pump(tester, access: _FakeAccess(), api: api, confirm: confirm);

    await tester.tap(find.text('给答案').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('冰美式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('就是这个'));
    await tester.pumpAndSettle();

    expect(api.settles.single, <String, dynamic>{
      'nodeId': 8,
      'playDay': '09-11',
      'settledOption': 'A',
    });
    expect(find.text('已公布 · 7 人猜中'), findsOneWidget);
    expect(find.text('共 1 轮等你给答案'), findsOneWidget);
  });

  testWidgets('结算失败:留在原地可再试 —— 绝不把没结掉的卡片拿掉', (WidgetTester tester) async {
    final api = _FakePredictApi(
      rows: <Map<String, dynamic>>[_round()],
      settleError: '结算失败，请重试',
    );
    final confirm = _Confirm(CyNativeConfirmResult.confirmed);
    await _pump(tester, access: _FakeAccess(), api: api, confirm: confirm);

    await tester.tap(find.text('给答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('冰美式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('就是这个'));
    await tester.pumpAndSettle();

    expect(find.text('结算失败，请重试'), findsOneWidget);
    expect(find.text('河畔咖啡'), findsOneWidget);
    expect(find.text('共 1 轮等你给答案'), findsOneWidget);
  });

  test('行模型:rid / 缺省点位名 / 选项过滤逐条对齐小程序 shapeRound', () {
    final PredictRound round = shapePredictRound(<String, dynamic>{
      'nodeId': 8,
      'playDay': '09-11',
      'options': <dynamic>[
        <String, dynamic>{'key': 'A', 'label': '冰美式'},
        <String, dynamic>{'label': '没有 key 的选项要被丢掉'},
      ],
    });
    expect(round.rid, '8:09-11');
    expect(round.nodeName, '未命名点位');
    expect(round.options.length, 1);
    expect(round.optionOf('A')?.label, '冰美式');
    expect(round.optionOf('Z'), isNull);
    expect(round.expired, isTrue);
    expect(round.deadlineText, '今天不给就作废');
  });
}
