import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/play_check.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/widgets/journey_check_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// R14 旅程检定在游玩会话页的完整链路(真源 pages/play/index.js 的
/// `_probeJourneyCheck`/`onJourneyCheckAction`/`_afterCheck`/`_recoverSettledCheck`):
/// 开节点 → encounter 探测 → 题面 → 掷 → (重掷) → 结算 → 继续;
/// 探测失败静默;roll 遇「已结算」用幂等 settle 回读。
DioClient _client() => DioClient(TokenStore(const FlutterSecureStorage()));

const PlayNode _node = PlayNode(
  nodeId: 17,
  name: '雨夜的柜台',
  address: '河埠头 12 号',
  sortId: 1,
  done: false,
  validationMethod: 0,
);

const Map<String, Object?> _checkProblem = <String, Object?>{
  'allowedActions': <String>['checkin', 'check'],
  'check': <String, Object?>{
    'checkId': 9,
    'skill': '观察',
    'tier': 'hard',
    'advantage': false,
    'disadvantage': true,
    'mods': <Map<String, Object?>>[
      <String, Object?>{'label': '下雨', 'value': -2, 'held': true},
    ],
  },
};

Map<String, Object?> _receipt({
  required List<int> dice,
  required int kept,
  required int total,
  required bool success,
  bool settled = false,
  bool rerolled = false,
  int? luck = 1,
  int? hp,
  String text = '',
}) => <String, Object?>{
  'tier': 'hard',
  'dc': 3,
  'dice': dice,
  'kept': kept,
  'total': total,
  'success': success,
  'rerolled': rerolled,
  'settled': settled,
  'luck': luck,
  'hp': hp,
  'text': text,
};

const CheckinReward _arriveReward = CheckinReward(
  nodeId: 17,
  firstTime: true,
  doneCount: 1,
  total: 1,
  completed: false,
  newBadges: <PlayBadge>[],
);

class _CheckPlayApi extends PlayApi {
  _CheckPlayApi({this.encounterError, this.rollError}) : super(_client());

  /// 非 null = encounter 探测直接失败(真源口径:静默,不打断任何已有路径)。
  final String? encounterError;

  /// 非 null = roll 被这条后端原文拒绝(走 `_recoverSettledCheck` 用)。
  final String? rollError;

  final List<String> calls = <String>[];
  final List<JourneyCheckReceipt> receipts = <JourneyCheckReceipt>[
    JourneyCheckReceipt.fromJson(
      _receipt(dice: <int>[4], kept: 4, total: 2, success: false),
    ),
    JourneyCheckReceipt.fromJson(
      _receipt(
        dice: <int>[6],
        kept: 6,
        total: 4,
        success: true,
        rerolled: true,
        luck: 0,
      ),
    ),
    JourneyCheckReceipt.fromJson(
      _receipt(
        dice: <int>[6],
        kept: 6,
        total: 4,
        success: true,
        settled: true,
        rerolled: true,
        luck: 0,
        hp: 3,
        text: '雨夜里你看清了柜台后的脸。',
      ),
    ),
  ];

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async =>
      const PlayNodesResult(
        topicId: 23,
        mode: 1,
        playable: true,
        total: 1,
        doneCount: 0,
        nodes: <PlayNode>[_node],
      );

  @override
  Future<CheckinReward> submitTopicArrive({
    required int topicId,
    required int nodeId,
    required double longitude,
    required double latitude,
    RouteAdvanceToken? routeAdvance,
  }) async => _arriveReward;

  @override
  Future<Map<String, dynamic>> encounter({
    required int topicId,
    required int nodeId,
  }) async {
    calls.add('encounter:$topicId:$nodeId');
    if (encounterError != null) throw PlayException(encounterError!);
    return Map<String, Object?>.from(_checkProblem).cast<String, dynamic>();
  }

  Future<JourneyCheckReceipt> _action(
    String name,
    int topicId,
    int nodeId,
    String checkId, {
    String? error,
  }) async {
    calls.add('$name:$topicId:$nodeId:$checkId');
    if (error != null) throw PlayException(error);
    return receipts.removeAt(0);
  }

  @override
  Future<JourneyCheckReceipt> rollCheck({
    required int topicId,
    required int nodeId,
    required String checkId,
  }) => _action('roll', topicId, nodeId, checkId, error: rollError);

  @override
  Future<JourneyCheckReceipt> rerollCheck({
    required int topicId,
    required int nodeId,
    required String checkId,
  }) => _action('reroll', topicId, nodeId, checkId);

  @override
  Future<JourneyCheckReceipt> settleCheck({
    required int topicId,
    required int nodeId,
    required String checkId,
  }) => _action('settle', topicId, nodeId, checkId);
}

class _GrantedLocationPlatform extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => Position(
    longitude: 121.4737,
    latitude: 31.2304,
    timestamp: DateTime.fromMillisecondsSinceEpoch(1755518400000),
    accuracy: 4,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

Future<void> _openNode(WidgetTester tester, _CheckPlayApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
      child: const MaterialApp(
        home: PlaySessionPage(activityId: 0, topicId: 23),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('雨夜的柜台'));
  await tester.pumpAndSettle();
  // 到店回执 sheet 压在检定屏上:先收起,检定屏才露脸(它本来就不是闸)。
  if (find.text('知道了').evaluate().isNotEmpty) {
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
  }
}

void main() {
  late GeolocatorPlatform originalPlatform;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _GrantedLocationPlatform();
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalPlatform;
  });

  testWidgets('开节点探到 check:题面 → 掷 → 重掷 → 结算 → 继续 全链走通', (
    WidgetTester tester,
  ) async {
    final api = _CheckPlayApi();
    await _openNode(tester, api);

    expect(api.calls, <String>['encounter:23:17']);
    // 题面:skill/难度中文档/劣势 tag/条件修正(held 点亮)
    expect(find.text('观察'), findsOneWidget);
    expect(find.text('难度 · 困难'), findsOneWidget);
    expect(find.text('劣势'), findsOneWidget);
    expect(find.text('条件修正'), findsOneWidget);
    expect(find.text('下雨'), findsOneWidget);
    expect(find.text('生效 -2'), findsOneWidget);
    expect(find.text('掷骰'), findsOneWidget);

    await tester.tap(find.text('掷骰'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('roll:23:17:9'));
    // 结果屏:只报事实,没有文案(骰面 4 与达成值 kept=4 各出一个「4」)
    expect(find.text('4'), findsNWidgets(2));
    expect(find.text('达成值 2 · 难度 3'), findsOneWidget);
    expect(find.text('没过线'), findsOneWidget);
    expect(find.text('还剩幸运，可以重掷一次'), findsOneWidget);

    await tester.tap(find.text('重掷'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('reroll:23:17:9'));
    // 重掷后 luck 用尽:没有第二次「重掷」,hint 消失
    expect(find.text('重掷'), findsNothing);
    expect(find.text('还剩幸运，可以重掷一次'), findsNothing);
    expect(find.text('过线了'), findsOneWidget);

    await tester.tap(find.text('结算'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('settle:23:17:9'));
    // 结算屏:文案这时候才出现
    expect(find.text('雨夜里你看清了柜台后的脸。'), findsOneWidget);
    expect(find.text('生命 3'), findsOneWidget);
    expect(find.text('幸运 0'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('继续'), findsNothing);
    expect(find.text('难度 · 困难'), findsNothing);
  });

  testWidgets('探测失败静默:不弹检定、不打断到店', (WidgetTester tester) async {
    final api = _CheckPlayApi(encounterError: '节点不存在');
    await _openNode(tester, api);

    expect(api.calls, contains('encounter:23:17'));
    expect(find.text('掷骰'), findsNothing);
    expect(find.text('节点不存在'), findsNothing);
    // 到店链路仍走完(检定不是闸)。
    expect(find.text('继续'), findsNothing);
  });

  testWidgets('上局已结算:roll 被拒后幂等 settle 回读回执,不把玩家卡死', (
    WidgetTester tester,
  ) async {
    final api = _CheckPlayApi(rollError: '这次检定已结算，不能再掷');
    // 已结算的局:第一份「roll 回执」用不上,直接给 settle 回读的那份。
    api.receipts.removeAt(0);
    api.receipts.removeAt(0);
    await _openNode(tester, api);

    await tester.tap(find.text('掷骰'));
    await tester.pumpAndSettle();

    expect(api.calls, <String>[
      'encounter:23:17',
      'roll:23:17:9',
      'settle:23:17:9',
    ], reason: 'roll 遇「已结算」→ 自动补一次幂等 settle,而不是停在报错');
    expect(find.text('结算'), findsNothing, reason: '已直接落到结算屏');
    expect(find.text('雨夜里你看清了柜台后的脸。'), findsOneWidget);
  });

  testWidgets('检定屏挡不住退出:右上角退出直接收起', (WidgetTester tester) async {
    final api = _CheckPlayApi();
    await _openNode(tester, api);
    expect(find.text('掷骰'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(JourneyCheckStage),
        matching: find.bySemanticsLabel('退出'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('掷骰'), findsNothing);
  });
}
