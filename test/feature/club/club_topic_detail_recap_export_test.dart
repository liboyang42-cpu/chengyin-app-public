// 活动详情(已结束)的**复盘导出**:点按钮 → 读哪条接口 → 剪贴板里有什么。
//
// 判据对齐小程序 `pages/club/topic-detail`(director.js 的 copyRecap +
// index.wxml 的 ctd-director-recaphead),四件事缺一不可:
//   ① 导出按钮的唯一闸是服务端下发的 `recap.exportAvailable`,不是本地猜的;
//   ② 复盘没生成时写「复盘尚未生成,不会把缺失指标显示为零。」,且**不给按钮**;
//   ③ 点一次 = 一次 `GET /api/game/session/recap/export?activityId=…`,
//      接口给的那一份整份进剪贴板(归一化/白名单在 API 层做,见
//      test/data/models/game_session_recap_export_test.dart);
//   ④ 失败要分清「网络」和「业务」两句不同的提示(小程序就这么分)。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/feature/club/club_topic_detail_page.dart';

import '../../support/game_recap_export_fixture.dart';

Widget _app(Widget home, List<dynamic> overrides) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/game/session/recap/export'),
  type: DioExceptionType.connectionError,
);

Map<String, dynamic> _overviewJson({
  String status = 'ended',
  List<Map<String, dynamic>> activities = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': 12,
  'name': '静安夜行',
  'status': status,
  'chapterCount': 2,
  'nodeCount': 7,
  'gameConfiguredCount': 3,
  'storyReady': true,
  'playModeText': '经典定向',
  'startDate': '2026-09-01 19:00:00',
  'endDate': '2026-09-30 22:00:00',
  'sessions': const <Map<String, dynamic>>[],
  'activityList': activities,
};

class _FakeClubTopicOpsApi extends ClubTopicOpsApi {
  _FakeClubTopicOpsApi(this.overviewValue) : super(_dummyDioClient());

  ClubTopicOverview overviewValue;

  @override
  Future<ClubTopicOverview> overview(int topicId) async => overviewValue;

  @override
  Future<ClubTopicManageStats> manageStats({
    required int clubId,
    required int topicId,
    int? activityId,
  }) async => const ClubTopicManageStats(
    canDirect: false,
    canManageSessions: false,
    canViewVerify: false,
    nodeCount: 7,
    sessionHeadcount: 9,
    pendingVerifyCount: 0,
    verifiedByMeCount: 0,
  );
}

class _FakeClubGateway implements ClubGameSessionGateway {
  _FakeClubGateway({this.state, this.viewError, this.exportError});

  ClubRecapState? state;
  Object? viewError;
  Object? exportError;
  final List<int> views = <int>[];
  final List<int> exports = <int>[];

  @override
  Future<ClubRecapState> loadClubView({required int activityId}) async {
    views.add(activityId);
    if (viewError != null) throw viewError!;
    return state!;
  }

  @override
  Future<Map<String, dynamic>> loadClubRecapExport({
    required int activityId,
  }) async {
    exports.add(activityId);
    if (exportError != null) throw exportError!;
    return gameRecapExportJson(activityId: activityId);
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeClubTopicOpsApi ops,
  required _FakeClubGateway gateway,
  int? activityId = 41,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      ClubTopicDetailPage(
        key: ObjectKey(ops),
        clubId: 1,
        topicId: 12,
        activityId: activityId,
      ),
      <dynamic>[
        clubTopicOpsApiProvider.overrideWithValue(ops),
        gameSessionApiClubProvider.overrideWithValue(gateway),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

/// 复盘块在页面最下面,先滚到它再动手。
Future<Finder> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 200);
  await tester.pumpAndSettle();
  return target;
}

List<MethodCall> _captureClipboard(WidgetTester tester) {
  final List<MethodCall> calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall call,
      ) async {
        calls.add(call);
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

void main() {
  testWidgets('★ 已结束 + 服务端说可导出:点一次 = 一次导出请求 + 原样进剪贴板', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> platform = _captureClipboard(tester);
    final gateway = _FakeClubGateway(
      state: const ClubRecapState(recapAvailable: true, exportAvailable: true),
    );
    await _pumpPage(
      tester,
      ops: _FakeClubTopicOpsApi(
        ClubTopicOverview.tryFromJson(_overviewJson())!,
      ),
      gateway: gateway,
    );

    expect(gateway.views, <int>[41], reason: '判闸要用这一场的俱乐部投影');
    await _scrollTo(tester, find.byKey(const Key('topic-recap-export')));
    await tester.tap(find.byKey(const Key('topic-recap-export')));
    await tester.pumpAndSettle();

    expect(gateway.exports, <int>[41], reason: '点一次只发一次导出请求');
    final MethodCall setData = platform.singleWhere(
      (MethodCall call) => call.method == 'Clipboard.setData',
    );
    expect(
      (setData.arguments as Map<dynamic, dynamic>)['text'],
      jsonEncode(gameRecapExportJson()),
    );
    expect(find.text('复盘数据已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('复盘没生成:只写那句不做零兜底的告知，不给导出按钮', (WidgetTester tester) async {
    final gateway = _FakeClubGateway(
      state: const ClubRecapState(
        recapAvailable: false,
        exportAvailable: false,
      ),
    );
    await _pumpPage(
      tester,
      ops: _FakeClubTopicOpsApi(
        ClubTopicOverview.tryFromJson(_overviewJson())!,
      ),
      gateway: gateway,
    );

    await _scrollTo(tester, find.text('复盘尚未生成，不会把缺失指标显示为零。'));
    expect(find.byKey(const Key('topic-recap-export')), findsNothing);
    expect(gateway.exports, isEmpty);
  });

  testWidgets('还没结束就不进这套状态机:不读俱乐部投影', (WidgetTester tester) async {
    final gateway = _FakeClubGateway(
      state: const ClubRecapState(recapAvailable: true, exportAvailable: true),
    );
    await _pumpPage(
      tester,
      ops: _FakeClubTopicOpsApi(
        ClubTopicOverview.tryFromJson(_overviewJson(status: 'running'))!,
      ),
      gateway: gateway,
    );

    expect(gateway.views, isEmpty);
    expect(find.byKey(const Key('topic-recap-export')), findsNothing);
  });

  testWidgets('导出失败分两句:网络一句、业务一句(都不装作成功)', (WidgetTester tester) async {
    for (final ({Object error, String copy}) case_
        in <({Object error, String copy})>[
          (error: _networkFailure(), copy: '网络异常，复制失败'),
          (
            error: const GameSessionContractException('复盘导出数据无效'),
            copy: '复盘数据复制失败',
          ),
        ]) {
      final gateway = _FakeClubGateway(
        state: const ClubRecapState(
          recapAvailable: true,
          exportAvailable: true,
        ),
        exportError: case_.error,
      );
      await _pumpPage(
        tester,
        ops: _FakeClubTopicOpsApi(
          ClubTopicOverview.tryFromJson(_overviewJson())!,
        ),
        gateway: gateway,
      );

      await _scrollTo(tester, find.byKey(const Key('topic-recap-export')));
      await tester.tap(find.byKey(const Key('topic-recap-export')));
      await tester.pumpAndSettle();

      expect(find.text(case_.copy), findsOneWidget);
      expect(find.text('复盘数据已复制'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('投影读不到:写清是哪一块没读到，并且能再点一次', (WidgetTester tester) async {
    final gateway = _FakeClubGateway(viewError: _networkFailure());
    await _pumpPage(
      tester,
      ops: _FakeClubTopicOpsApi(
        ClubTopicOverview.tryFromJson(_overviewJson())!,
      ),
      gateway: gateway,
    );

    await _scrollTo(tester, find.text('本局复盘状态没能加载出来'));
    expect(gateway.views, <int>[41]);
    expect(find.text('复盘尚未生成，不会把缺失指标显示为零。'), findsNothing);

    gateway.viewError = null;
    gateway.state = const ClubRecapState(
      recapAvailable: true,
      exportAvailable: true,
    );
    await tester.tap(find.byKey(const Key('topic-recap-retry')));
    await tester.pumpAndSettle();

    expect(gateway.views, <int>[41, 41]);
    await _scrollTo(tester, find.byKey(const Key('topic-recap-export')));
  });

  testWidgets('从俱乐部页进来没带 activityId:按主题下第一个场次查(小程序同一条兜底)', (
    WidgetTester tester,
  ) async {
    final gateway = _FakeClubGateway(
      state: const ClubRecapState(recapAvailable: true, exportAvailable: true),
    );
    await _pumpPage(
      tester,
      ops: _FakeClubTopicOpsApi(
        ClubTopicOverview.tryFromJson(
          _overviewJson(
            activities: <Map<String, dynamic>>[
              <String, dynamic>{'id': 77, 'name': '九月夜场'},
            ],
          ),
        )!,
      ),
      gateway: gateway,
      activityId: null,
    );

    expect(gateway.views, <int>[77]);
  });
}
