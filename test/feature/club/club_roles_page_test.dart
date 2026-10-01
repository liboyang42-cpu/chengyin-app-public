// 角色与权限页(roles)的负控门:裁决真源是 canManageRoles、坏回执不当没权限、
// 撤销三段式与 requestId 稳定、场次范围只放场次级角色。
//
// 判据对齐小程序 pages/club/roles(@90e66d70):
//   - 「回执坏了」(active 不是布尔)与「没权限」(canManageRoles !== true)是两回事:
//     前者给重试,后者重试也没用;
//   - 撤销 = 二次确认 → 请求 → 结果反馈;requestId 会话内稳定,只有 4xx 明确失败才丢;
//   - 带 activityId 时只可委派场次级角色,且 assign 必须把 activityId 带上。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dio/dio.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_roles_page.dart';

Widget _app(Widget home, List<dynamic> overrides, {Locale locale = const Locale('zh')}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

ClubOpsAccess _access({
  bool canManageRoles = true,
  bool active = true,
  bool activeDeclared = true,
  int clubId = 1,
  Set<String> permissions = const <String>{},
}) => ClubOpsAccess(
  activeDeclared: activeDeclared,
  active: active,
  clubId: clubId,
  permissions: permissions,
  roleCodes: canManageRoles
      ? const <String>['CLUB_OWNER']
      : const <String>['CLUB_MEMBER'],
  canManageRoles: canManageRoles,
);

ClubMember _member(int id, String nick, {bool owner = false, int role = 0}) =>
    ClubMember(memberId: id, nickname: nick, role: role, isOwner: owner);

RoleScopeData _clubScope() => const RoleScopeData(
  roles: <RoleOption>[
    RoleOption(
      roleCode: 'CLUB_CO_OWNER',
      name: '副主理人',
      scopeType: 'CLUB',
      summary: '可维护俱乐部资料、成员与活动；不能分配角色',
    ),
    RoleOption(
      roleCode: 'CLUB_OPERATOR',
      name: '运营管理员',
      scopeType: 'CLUB',
      summary: '可管理内容、入会审核与成员通知；活动与现场权限按场次单独委派',
    ),
  ],
  assignments: <RoleAssignment>[
    RoleAssignment(
      id: 11,
      targetMemberId: 12,
      memberName: '阿明',
      roleCode: 'CLUB_CO_OWNER',
      roleName: '副主理人',
      scopeType: 'CLUB',
      scopeId: 1,
      version: 3,
    ),
  ],
);

/// 记录调用、可挂闸的 ClubApi 假实现(角色页要用成员名册)。
class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dummyDioClient());

  List<ClubMember> membersValue = <ClubMember>[
    _member(1, '小柚', owner: true),
    _member(12, '阿明'),
    _member(13, '小静', role: 1),
  ];

  @override
  Future<List<ClubMember>> members(int clubId) async => membersValue;
}

class _FakeClubOpsApi extends ClubOpsApi {
  _FakeClubOpsApi() : super(_dummyDioClient());

  ClubOpsAccess accessValue = _access();
  Object? accessError;
  RoleScopeData? scopeValue = _clubScope();
  Object? scopeError;
  Completer<void>? assignGate;
  Object? assignError;
  Object? revokeError;

  final List<Map<String, dynamic>> assigns = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> revokes = <Map<String, dynamic>>[];
  final List<int?> rolesListActivityIds = <int?>[];

  @override
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async {
    if (accessError != null) throw accessError!;
    return accessValue;
  }

  @override
  Future<RoleScopeData?> rolesList({
    required int clubId,
    int? activityId,
  }) async {
    rolesListActivityIds.add(activityId);
    if (scopeError != null) throw scopeError!;
    return scopeValue;
  }

  @override
  Future<void> assignRole({
    required int clubId,
    int? activityId,
    required int targetMemberId,
    required String roleCode,
    required String requestId,
  }) async {
    assigns.add(<String, dynamic>{
      'clubId': clubId,
      'activityId': activityId,
      'targetMemberId': targetMemberId,
      'roleCode': roleCode,
      'requestId': requestId,
    });
    if (assignGate != null) await assignGate!.future;
    if (assignError != null) throw assignError!;
  }

  @override
  Future<void> revokeRole({
    required int clubId,
    int? activityId,
    required int assignmentId,
    required int version,
    required String reason,
    required String requestId,
  }) async {
    revokes.add(<String, dynamic>{
      'clubId': clubId,
      'activityId': activityId,
      'assignmentId': assignmentId,
      'version': version,
      'reason': reason,
      'requestId': requestId,
    });
    if (revokeError != null) throw revokeError!;
  }
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}

Future<void> _pickMember(WidgetTester tester, int memberId) async {
  await _tapVisible(tester, const Key('roles-pick-member'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('roles-member-$memberId')));
  await tester.pumpAndSettle();
}

Future<void> _pickRole(WidgetTester tester, String roleCode) async {
  await _tapVisible(tester, const Key('roles-pick-role'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('roles-role-$roleCode')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('English role denial still prevents assignments', (tester) async {
    final fake = _FakeClubOpsApi()..accessValue = _access(canManageRoles: false);
    await tester.pumpWidget(_app(const ClubRolesPage(clubId: 1), [
      clubOpsApiProvider.overrideWithValue(fake),
      clubApiProvider.overrideWithValue(_FakeClubApi()),
    ], locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('You cannot manage roles'), findsOneWidget);
    expect(find.text('Assign'), findsNothing);
    expect(fake.assigns, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English role chrome preserves server role and member names', (tester) async {
    final fake = _FakeClubOpsApi();
    await tester.pumpWidget(_app(const ClubRolesPage(clubId: 1), [
      clubOpsApiProvider.overrideWithValue(fake),
      clubApiProvider.overrideWithValue(_FakeClubApi()),
    ], locale: const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Current assignments'), findsOneWidget);
    expect(find.text('阿明'), findsOneWidget);
    expect(find.textContaining('副主理人'), findsWidgets);
    expect(fake.revokes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  group('roles:权限裁决', () {
    testWidgets('canManageRoles 不是 true → 无权限屏(重试也没用)', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessValue = _access(canManageRoles: false);
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你没有管理角色的权限'), findsOneWidget);
      expect(find.text('重试'), findsNothing, reason: '明确没权限时不给重试');
    });

    testWidgets('active 不是布尔(回执坏了)→ 错误态可重试,不栽成没权限', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessValue = _access(activeDeclared: false, active: false);
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('角色管理暂时不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('读权限网络失败 → 网络态可重试', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..accessError = _networkFailure();
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('没有可委派成员 → 空态', (WidgetTester tester) async {
      final clubApi = _FakeClubApi()
        ..membersValue = <ClubMember>[_member(1, '小柚', owner: true)];
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
          clubApiProvider.overrideWithValue(clubApi),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有可委派的成员'), findsOneWidget);
      expect(find.byKey(const Key('roles-assign')), findsNothing);
    });
  });

  group('roles:委派门', () {
    testWidgets('未选成员/角色时「分配」禁用;选齐后可分配且参数正确', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      // 当前委派:主理人 + 已有委派行。
      expect(find.text('当前委派'), findsOneWidget);
      expect(find.text('阿明'), findsOneWidget);
      expect(
        find.text('可维护俱乐部资料、成员与活动；不能分配角色'),
        findsOneWidget,
        reason: '固定角色说明要逐字上屏',
      );
      expect(find.byKey(const Key('roles-assignment-11')), findsOneWidget);

      CyNativeButton assignButton() => tester.widget<CyNativeButton>(
        find.byKey(const Key('roles-assign')),
      );
      expect(assignButton().onPressed, isNull, reason: '未选成员与角色时不能分配');

      await _pickMember(tester, 12);
      expect(assignButton().onPressed, isNull, reason: '只选成员还不够');
      await _pickRole(tester, 'CLUB_CO_OWNER');
      expect(assignButton().onPressed, isNotNull);

      await _tapVisible(tester, const Key('roles-assign'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(fake.assigns, hasLength(1));
      expect(fake.assigns.single['targetMemberId'], 12);
      expect(fake.assigns.single['roleCode'], 'CLUB_CO_OWNER');
      expect(fake.assigns.single['activityId'], isNull);
      expect(
        '${fake.assigns.single['requestId']}',
        startsWith('club-role-'),
        reason: '委派必须带幂等键',
      );
      // 成功后回到未选角色态。
      expect(assignButton().onPressed, isNull);
    });

    testWidgets('分配中其余动作一起禁用(防连点)', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..assignGate = Completer<void>();
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _pickMember(tester, 12);
      await _pickRole(tester, 'CLUB_OPERATOR');
      await _tapVisible(tester, const Key('roles-assign'));
      await tester.pump();
      await tester.pump();

      // 请求在途:分配键与撤销键都必须禁用。
      expect(
        tester
            .widget<CyNativeButton>(find.byKey(const Key('roles-assign')))
            .onPressed,
        isNull,
      );
      final Finder revoke = find.byKey(const Key('roles-revoke-11'));
      await tester.ensureVisible(revoke);
      await tester.pumpAndSettle();
      await tester.tap(revoke, warnIfMissed: false);
      await tester.pump();
      expect(fake.revokes, isEmpty, reason: '在途时撤销不能发出去');

      fake.assignGate!.complete();
      await tester.pumpAndSettle();
      expect(fake.assigns, hasLength(1));
    });

    testWidgets('带 activityId → 只给场次级角色,分配带上 activityId', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..scopeValue = const RoleScopeData(
          roles: <RoleOption>[
            RoleOption(
              roleCode: 'EVENT_LEAD',
              name: '现场负责人',
              scopeType: 'EVENT',
              summary: '仅负责当前场次的现场执行与核销',
            ),
          ],
          assignments: <RoleAssignment>[],
        );
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1, activityId: 9), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(fake.rolesListActivityIds, contains(9));
      await _pickMember(tester, 13);
      await _pickRole(tester, 'EVENT_LEAD');
      await _tapVisible(tester, const Key('roles-assign'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      expect(fake.assigns, hasLength(1));
      expect(fake.assigns.single['activityId'], 9);
      expect(fake.assigns.single['roleCode'], 'EVENT_LEAD');
    });

    testWidgets('角色目录回执坏了 → 错误态可重试', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..scopeValue = null;
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('角色管理暂时不可用'), findsOneWidget);
      expect(find.text('角色目录暂时不可用'), findsOneWidget);
    });
  });

  group('roles:撤销三段式', () {
    testWidgets('先二次确认再撤销,version 与 assignmentId 都带上', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, const Key('roles-revoke-11'));
      await tester.pumpAndSettle();
      expect(find.text('撤销 阿明 的「副主理人」？'), findsOneWidget);
      expect(fake.revokes, isEmpty, reason: '确认前不能发请求');

      await tester.tap(find.text('撤销角色'));
      await tester.pumpAndSettle();

      expect(fake.revokes, hasLength(1));
      expect(fake.revokes.single['assignmentId'], 11);
      expect(fake.revokes.single['version'], 3);
      expect('${fake.revokes.single['requestId']}', startsWith('club-role-'));
    });

    testWidgets('取消确认 → 不发请求', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, const Key('roles-revoke-11'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(fake.revokes, isEmpty);
      expect(find.byKey(const Key('roles-assignment-11')), findsOneWidget);
    });

    testWidgets('4xx 明确失败才丢 requestId:重试换新键', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..revokeError = ClubOpsRejectedException('该角色已不存在');
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, const Key('roles-revoke-11'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销角色'));
      await tester.pumpAndSettle();
      expect(fake.revokes, hasLength(1));

      fake.revokeError = null;
      await _tapVisible(tester, const Key('roles-revoke-11'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销角色'));
      await tester.pumpAndSettle();

      expect(fake.revokes, hasLength(2));
      expect(
        fake.revokes[1]['requestId'],
        isNot(fake.revokes[0]['requestId']),
        reason: '4xx 明确失败后必须重开一条意图',
      );
    });

    testWidgets('网络失败保持同一 requestId:重试是同一意图', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..revokeError = _networkFailure();
      await tester.pumpWidget(
        _app(const ClubRolesPage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, const Key('roles-revoke-11'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销角色'));
      await tester.pumpAndSettle();

      fake.revokeError = null;
      await _tapVisible(tester, const Key('roles-revoke-11'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销角色'));
      await tester.pumpAndSettle();

      expect(fake.revokes, hasLength(2));
      expect(
        fake.revokes[1]['requestId'],
        fake.revokes[0]['requestId'],
        reason: '网络结果未知时必须复用同一幂等键',
      );
    });
  });
}

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/club/roles/revoke'),
  type: DioExceptionType.connectionTimeout,
);
