// 「附近的队伍」(地图组队 P 方案,Figma txQoyVyK 590:1014)的整页快照。
//
// ★ 判据:小队卡在三种关键态下的**视觉**对不对 ——
//     ① 列表(顶部计数条 + 范围 / 我的队伍两枚角控件 + 队伍行);
//     ② P3 有票卡(✓ 说明 + 主按钮「申请加入」+ 群聊说明);
//     ③ P5 队长审批(拒绝在左、同意在右,两行申请)。
//   逻辑与文案由 test/feature/team/** 钉住,这里只锁"长什么样"。
// ★ 快照里不出现相对时间(申请行的 appliedAt 不给),避免基准图自己腐烂。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_team_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/team_map_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/team/team_nearby_page.dart';
import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.fixed);
  final AuthState fixed;

  @override
  AuthState build() => fixed;
}

class _FakeTeamMapApi extends TeamMapApi {
  _FakeTeamMapApi() : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<Map<String, dynamic>> teams = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> applicants = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    int radiusM = 3000,
  }) async => teams;

  @override
  Future<List<Map<String, dynamic>>> applications(int teamId) async => applicants;

  @override
  Future<List<Map<String, dynamic>>> myTeams() async => <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> myApplications() async => <Map<String, dynamic>>[];
}

Map<String, dynamic> _team({
  required int teamId,
  required String title,
  required String activityName,
  String viewerStatus = 'NONE',
  bool viewerHasTicket = false,
  int joinedCount = 3,
  int maxMembers = 4,
  int? pendingCount,
  int distance = 600,
}) => <String, dynamic>{
  'teamId': teamId,
  'title': title,
  'activityId': 11,
  'activityName': activityName,
  'productType': 1,
  'addressName': '外滩源',
  'coordSource': 'GATHER',
  'latitude': 31.2,
  'longitude': 121.4,
  'distance': distance,
  'leaderName': '小周',
  'joinedCount': joinedCount,
  'maxMembers': maxMembers,
  'memberAvatars': const <String>[],
  'viewerStatus': viewerStatus,
  'viewerHasTicket': viewerHasTicket,
  'pendingCount': pendingCount,
};

Future<void> _pump(WidgetTester tester, _FakeTeamMapApi api) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        // 本页对游客是登录门(游客深链落地只看到「登录后查看附近的队伍」),
        // 这三张快照拍的是页面自己的三态,所以给已登录态。
        authControllerProvider.overrideWith(
          () => _FixedAuth(
            AuthState(
              initialized: true,
              user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
            ),
          ),
        ),
      ].cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: TeamNearbyPage(
          api: api,
          locate: () async =>
              const MapCoordinate(latitude: 31.2304, longitude: 121.4737),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('附近的队伍列表:计数条 + 两枚角控件 + 招募中的队伍行', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(
          teamId: 7,
          title: '外滩夜行',
          activityName: '外滩夜行路线 · 周五 19:30 场',
          viewerHasTicket: true,
        ),
        _team(
          teamId: 8,
          title: '苏河湾探店日',
          activityName: '苏河湾探店日 · 周六 14:00 场',
          viewerStatus: 'PENDING',
          distance: 1500,
        ),
      ];
    await _pump(tester, api);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pages_team_nearby_list.png'),
    );
  });

  testWidgets('P3 有票卡:✓ 说明 + 申请加入 + 群聊说明', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(
          teamId: 7,
          title: '外滩夜行',
          activityName: '外滩夜行路线 · 周五 19:30 场',
          viewerHasTicket: true,
        ),
      ];
    await _pump(tester, api);
    await tester.tap(find.text('外滩夜行路线 · 周五 19:30 场'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pages_team_nearby_card.png'),
    );
  });

  testWidgets('P5 队长审批:拒绝(次)在左、同意(主)在右', (WidgetTester tester) async {
    final _FakeTeamMapApi api = _FakeTeamMapApi()
      ..teams = <Map<String, dynamic>>[
        _team(
          teamId: 7,
          title: '外滩夜行',
          activityName: '外滩夜行路线 · 周五 19:30 场',
          viewerStatus: 'LEADER',
          pendingCount: 2,
        ),
      ]
      ..applicants = <Map<String, dynamic>>[
        <String, dynamic>{'memberId': 5, 'memberName': '阿杰'},
        <String, dynamic>{'memberId': 6, 'memberName': 'Mia'},
      ];
    await _pump(tester, api);
    await tester.tap(find.text('外滩夜行路线 · 周五 19:30 场'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/pages_team_nearby_leader.png'),
    );
  });
}
