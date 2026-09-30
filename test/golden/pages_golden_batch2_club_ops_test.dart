// 俱乐部运营页金图 · 批次2 —— F19 / F20 / F21 / F22。
//
// 小程序真源 `pages/club/{roles,governance,event-ops,notify}/index`(@github/master)。
// 四个 shot 都在**空态 / 表单初始态**,所以夹具只回答「主理人有权限」+「列表为空」,
// 不伪造成员、权限分配或订阅消息可用性(shot 备注里点名的口径)。
//
// 主题:俱乐部页是玩家域 = 恒暗(与商家恒浅相对),所以用 goldenTheme()。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_golden_batch2_club_ops_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_event_ops_page.dart';
import 'package:chengyin_app/feature/club/club_governance_page.dart';
import 'package:chengyin_app/feature/club/club_notify_page.dart';
import 'package:chengyin_app/feature/club/club_roles_page.dart';

import 'golden_theme.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(
    theme: goldenTheme(),
    debugShowCheckedModeBanner: false,
    home: home,
  ),
);

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 844));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

/// 主理人回执:有权限、俱乐部 id 对得上。
ClubOpsAccess _ownerAccess({int clubId = 42}) => ClubOpsAccess(
  activeDeclared: true,
  active: true,
  clubId: clubId,
  permissions: const <String>{
    'CLUB_ROLE_MANAGE',
    'CLUB_GOVERNANCE_MANAGE',
    'CLUB_ACTIVITY_MANAGE',
    'CLUB_CHECKIN_MANAGE',
    'CLUB_NOTIFY_SEND',
    'CLUB_EVENT_OPERATE',
  },
  roleCodes: const <String>['CLUB_OWNER'],
  canManageRoles: true,
);

class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dummyDioClient());

  @override
  Future<List<ClubMember>> members(int clubId) async => <ClubMember>[
    ClubMember(memberId: 1, nickname: '小柚', role: 0, isOwner: true),
    ClubMember(memberId: 12, nickname: '阿明', role: 0),
  ];
}

/// 空态四页共用的假 API:只答「有权限」与「列表为空」。
class _FakeClubOpsApi extends ClubOpsApi {
  _FakeClubOpsApi() : super(_dummyDioClient());

  @override
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async =>
      _ownerAccess(clubId: clubId);

  @override
  Future<RoleScopeData?> rolesList({
    required int clubId,
    int? activityId,
  }) async => const RoleScopeData(
    roles: <RoleOption>[],
    assignments: <RoleAssignment>[],
  );

  @override
  Future<List<GovernanceBan>?> governanceBans({required int clubId}) async =>
      <GovernanceBan>[];

  @override
  Future<List<GovernanceCase>?> governanceCasesMine({
    required int clubId,
  }) async => <GovernanceCase>[];

  @override
  Future<List<EventOpsTopic>> eventTopics({required int clubId}) async =>
      <EventOpsTopic>[];

  @override
  Future<List<EventSeries>> seriesList({required int clubId}) async =>
      <EventSeries>[];

  @override
  Future<AudienceCounts?> audienceCounts({
    required int clubId,
    int? activityId,
  }) async =>
      const AudienceCounts(<String, int?>{'ALL_MEMBERS': 0, 'ADMINS': 0});

  @override
  Future<NotificationPreview?> notificationPreview({
    required int clubId,
    int? activityId,
    required String audienceType,
    required String title,
    required String content,
  }) async => const NotificationPreview(
    recipientCount: 0,
    phoneIncluded: false,
    inApp: 'ok',
    wechatSubscription: 'unavailable',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('本快照只用到读接口: $invocation');
}

void main() {
  testWidgets('F19 角色委派 · 空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(_FakeClubApi()),
        clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
      ], const ClubRolesPage(clubId: 42)),
      'goldens/page_club_roles_empty.png',
    );
  });

  testWidgets('F20 成员治理 · 空态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(_FakeClubApi()),
        clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
      ], const ClubGovernancePage(clubId: 42, mode: 'manage')),
      'goldens/page_club_governance_empty.png',
    );
  });

  testWidgets('F21 活动运营 · 无合作主题/无系列', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        clubApiProvider.overrideWithValue(_FakeClubApi()),
        clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
      ], const ClubEventOpsPage(clubId: 42)),
      'goldens/page_club_event_ops_empty.png',
    );
  });

  testWidgets('F22 站内通知 · 表单初始态', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(<dynamic>[
        clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
      ], const ClubNotifyPage(clubId: 42)),
      'goldens/page_club_notify_form.png',
    );
  });
}
