// 游玩首屏的空态引导体系(`emptyKind` 六分支) —— 真源 `pages/play/index.js:2828-2852`
// + `index.wxml:1412-1427`。
//
// 修的是报告 A1670/A1671:402 / 未报名 / 缺参 / 节点空此前全部落成一屏通用「加载失败,请重试」,
// 新玩家在入口就被挡死且没有任何出路(点「重试」对缺参和未报名是死循环)。
// 每一种态只留真走得通的出口:缺参不给重新加载(真源注释:那是物理上回到同一状态的假按钮)。

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_empty_state.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

class _StubPlayApi extends PlayApi {
  _StubPlayApi({this.result, this.failure}) : super(_client());

  final PlayNodesResult? result;
  final Object? failure;

  final List<int> activityCalls = <int>[];
  final List<int> topicCalls = <int>[];

  int get nodesCalls => activityCalls.length + topicCalls.length;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    activityCalls.add(activityId);
    if (failure != null) throw failure!;
    return result!;
  }

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async {
    topicCalls.add(topicId);
    if (failure != null) throw failure!;
    return result!;
  }
}

PlayNodesResult _result({
  bool? registered,
  int topicId = 23,
  List<PlayNode> nodes = const <PlayNode>[
    PlayNode(
      nodeId: 7,
      name: '第一站',
      address: '城瘾路 1 号',
      sortId: 1,
      done: false,
    ),
  ],
}) => PlayNodesResult(
  topicId: topicId,
  mode: 1,
  playable: true,
  total: nodes.length,
  doneCount: 0,
  nodes: nodes,
  registered: registered,
);

/// 游玩页既可能作为根路由(分享链/门口码直落),也可能由场次详情压入。
/// 两条路都得测,因为「返回活动详情」的出路不一样(pop vs 回票夹)。
Future<void> _pump(
  WidgetTester tester, {
  required _StubPlayApi api,
  int activityId = 0,
  int? topicId,
  bool startAtDetail = false,
}) async {
  final String playLocation =
      '/play/$activityId${topicId == null ? '' : '?topicId=$topicId'}';
  final GoRouter router = GoRouter(
    initialLocation: startAtDetail ? '/detail' : playLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/detail',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: Center(
            child: CupertinoButton(
              onPressed: () => context.push(playLocation),
              child: const Text('场次详情'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/play/:activityId',
        builder: (BuildContext context, GoRouterState state) => PlaySessionPage(
          activityId:
              int.tryParse(state.pathParameters['activityId'] ?? '') ?? 0,
          topicId: int.tryParse(state.uri.queryParameters['topicId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/topic/:id',
        builder: (BuildContext context, GoRouterState state) =>
            Scaffold(body: Text('通行证购买页 ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/tickets',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('我的票夹')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  if (startAtDetail) {
    // 从场次详情压进来 ⇒ 游玩页有「上一页」,返回动作该是 pop 而不是回票夹。
    await tester.tap(find.text('场次详情'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('★ 判定顺序(真源 loadData)', () {
    test('402 优先于「登录」字样:自玩没有报名/登录出路,只有买通行证', () {
      final guide = classifyPlayNodesFailure(
        PlayException('登录状态已失效，请先购买自玩通行证', code: 402),
      );
      expect(guide.kind, PlayEmptyKind.needPass);
    });

    test('HTTP 状态异常的 402 不算 needPass(真源 successStatusAbnormal 同口径)', () {
      final guide = classifyPlayNodesFailure(
        DioException(
          requestOptions: RequestOptions(path: '/api/play/nodes'),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/play/nodes'),
            statusCode: 402,
            data: <String, dynamic>{'code': 402, 'msg': 'bad gateway'},
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(guide.kind, PlayEmptyKind.error);
      expect(guide.tip, '加载失败，请稍后重试');
    });

    test('未报名优先于空节点:先说清是人没报名,别让人以为路线没配', () {
      final guide = classifyPlayNodesResult(
        _result(registered: false, nodes: const <PlayNode>[]),
      );
      expect(guide?.kind, PlayEmptyKind.signup);
      expect(guide?.tip, '你还没有报名这个场次');
    });

    test('后端没发 registered 时不判未报名', () {
      expect(
        classifyPlayNodesResult(_result(registered: null))?.kind,
        isNot(PlayEmptyKind.signup),
      );
    });
  });

  group('★ 六种空态各自渲染与出路', () {
    testWidgets('缺参:不发请求、不给「重新加载」,只给返回', (WidgetTester tester) async {
      final api = _StubPlayApi(result: _result());
      await _pump(tester, api: api, activityId: 0);

      expect(find.text('场次信息缺失，请从票夹或路线详情进入'), findsOneWidget);
      expect(find.text('重新加载'), findsNothing);
      expect(find.text('返回活动详情'), findsOneWidget);
      expect(api.nodesCalls, 0, reason: '真源在发请求之前就 return 了');

      await tester.tap(find.text('返回活动详情'));
      await tester.pumpAndSettle();
      expect(find.text('我的票夹'), findsOneWidget);
    });

    testWidgets('402:文案用后端原话,「获取通行证」跳主题详情', (WidgetTester tester) async {
      final api = _StubPlayApi(failure: PlayException('请先购买自玩通行证', code: 402));
      await _pump(tester, api: api, topicId: 73);

      expect(find.text('请先购买自玩通行证'), findsOneWidget);
      expect(find.text('获取通行证'), findsOneWidget);
      expect(find.text('去报名'), findsNothing, reason: '自玩没有报名这个动作');
      expect(api.topicCalls, <int>[73]);

      await tester.tap(find.text('获取通行证'));
      await tester.pumpAndSettle();
      expect(find.text('通行证购买页 73'), findsOneWidget);
    });

    testWidgets('未报名:「去报名」回场次详情', (WidgetTester tester) async {
      final api = _StubPlayApi(result: _result(registered: false));
      await _pump(tester, api: api, activityId: 41, startAtDetail: true);

      expect(find.text('你还没有报名这个场次'), findsOneWidget);
      expect(find.text('第一站'), findsNothing, reason: '未报名不渲染地图');

      await tester.tap(find.text('去报名'));
      await tester.pumpAndSettle();
      expect(find.text('场次详情'), findsOneWidget);
    });

    testWidgets('没有节点:「返回」,不是「去报名」', (WidgetTester tester) async {
      final api = _StubPlayApi(
        result: _result(registered: true, nodes: const <PlayNode>[]),
      );
      await _pump(tester, api: api, activityId: 41);

      expect(find.text('本场路线节点还在配置中，请稍后查看'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
      expect(find.text('去报名'), findsNothing);
    });

    testWidgets('加载失败:给「重新加载」+「返回活动详情」,重试真的重拉首屏', (WidgetTester tester) async {
      final api = _StubPlayApi(
        failure: DioException(
          requestOptions: RequestOptions(path: '/api/play/nodes'),
          type: DioExceptionType.connectionError,
        ),
      );
      await _pump(tester, api: api, activityId: 41);

      expect(find.text('加载失败，请稍后重试'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('返回活动详情'), findsOneWidget);
      expect(api.nodesCalls, 1);

      await tester.tap(find.text('重新加载'));
      // 重新加载会回到「加载中」,转圈的 CupertinoActivityIndicator 永不停帧,
      // pumpAndSettle 在这里必然超时 —— 手动泵到异步回包落地即可。
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.nodesCalls, 2, reason: '重新加载必须真把首屏再拉一遍');
    });

    testWidgets('回包形状坏了点名是路线没加载出来', (WidgetTester tester) async {
      final api = _StubPlayApi(
        failure: PlayException(kPlayRouteShapeBrokenTip),
      );
      await _pump(tester, api: api, activityId: 41);

      expect(find.text('路线没加载出来，请稍后重试'), findsOneWidget);
      expect(find.text('本场路线节点还在配置中，请稍后查看'), findsNothing);
    });

    testWidgets('登录态失效:「重新登录」而不是「重新加载」', (WidgetTester tester) async {
      final api = _StubPlayApi(
        failure: PlayException('登录状态已失效，请重新登录', code: 401),
      );
      await _pump(tester, api: api, activityId: 41);

      expect(find.text('登录已过期，请重新登录'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.text('重新加载'), findsNothing);
    });
  });
}
