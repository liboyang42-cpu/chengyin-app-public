// 成员治理页(governance)的负控门:三模式(manage / report / appeal)、
// 「理由是提交的前置」、解封只在俱乐部封禁上出现、转让只给主理人。
//
// 判据对齐小程序 pages/club/governance(@90e66d70):
//   - 封禁 / 转让 / 举报 / 申诉全部「先填理由再提交」,理由缺失即中止;
//   - 解封只在 status=ACTIVE && sourceType=CLUB 时出现(平台封禁仅平台可解);
//   - appeal 模式不查俱乐部权限,只拉「我的平台工单」;
//   - report 模式缺合法目标直接进错误态,不发请求。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dio/dio.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_ops.dart';
import 'package:chengyin_app/feature/club/club_governance_page.dart';
import 'package:chengyin_app/feature/club/club_ops_access.dart';

/// 原生输入弹窗在测试里退成 Cupertino Alert,输入框固定这个 key。
const Key _reasonFieldKey = Key('cy-system-input-alert-field');

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

ClubOpsAccess _access({
  bool owner = true,
  bool memberManage = true,
  bool active = true,
  int clubId = 1,
}) => ClubOpsAccess(
  activeDeclared: true,
  active: active,
  clubId: clubId,
  permissions: memberManage
      ? const <String>{kClubMemberManage}
      : const <String>{},
  roleCodes: owner
      ? const <String>['CLUB_OWNER']
      : const <String>['CLUB_OPERATOR'],
  canManageRoles: owner,
);

ClubMember _member(int id, String nick, {bool owner = false}) =>
    ClubMember(memberId: id, nickname: nick, isOwner: owner);

GovernanceBan _ban({
  required int id,
  String sourceType = 'CLUB',
  String status = 'ACTIVE',
  String nickname = '阿明',
  int version = 5,
}) => GovernanceBan(
  id: id,
  version: version,
  sourceType: sourceType,
  sourceText: sourceType == 'PLATFORM' ? '平台治理' : '俱乐部治理',
  targetNickname: nickname,
  status: status,
  statusText: status == 'ACTIVE'
      ? '封禁中'
      : (status == 'EXPIRED' ? '已到期' : '已解封'),
  bannedAtText: '2026-09-01 10:00',
  expiresText: sourceType == 'PLATFORM' ? '平台永久封禁' : '至 2026-10-01 10:00',
  unbanReason: '',
  canClubUnban: status == 'ACTIVE' && sourceType == 'CLUB',
);

class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dummyDioClient());

  List<ClubMember> membersValue = <ClubMember>[
    _member(1, '小柚', owner: true),
    _member(12, '阿明'),
  ];

  @override
  Future<List<ClubMember>> members(int clubId) async => membersValue;
}

class _FakeClubOpsApi extends ClubOpsApi {
  _FakeClubOpsApi() : super(_dummyDioClient());

  ClubOpsAccess accessValue = _access();
  Object? accessError;
  int accessCalls = 0;
  List<GovernanceBan>? bansValue = <GovernanceBan>[];
  Object? bansError;
  List<GovernanceCase>? casesValue = <GovernanceCase>[];
  Object? banError;
  Object? transferError;

  final List<Map<String, dynamic>> bans = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> unbans = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> transfers = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> cases = <Map<String, dynamic>>[];

  @override
  Future<ClubOpsAccess> access({required int clubId, int? activityId}) async {
    accessCalls += 1;
    if (accessError != null) throw accessError!;
    return accessValue;
  }

  @override
  Future<List<GovernanceBan>?> governanceBans({required int clubId}) async {
    if (bansError != null) throw bansError!;
    return bansValue;
  }

  @override
  Future<List<GovernanceCase>?> governanceCasesMine({
    required int clubId,
  }) async => casesValue;

  @override
  Future<void> banMember({
    required int clubId,
    required int targetMemberId,
    required String reason,
    required String expiresAt,
    required String requestId,
  }) async {
    bans.add(<String, dynamic>{
      'targetMemberId': targetMemberId,
      'reason': reason,
      'expiresAt': expiresAt,
      'requestId': requestId,
    });
    if (banError != null) throw banError!;
  }

  @override
  Future<void> unbanMember({
    required int clubId,
    required int banId,
    required int version,
    required String reason,
    required String requestId,
  }) async {
    unbans.add(<String, dynamic>{
      'banId': banId,
      'version': version,
      'reason': reason,
      'requestId': requestId,
    });
  }

  @override
  Future<void> transferOwner({
    required int clubId,
    required int targetMemberId,
    required String reason,
    required String requestId,
  }) async {
    transfers.add(<String, dynamic>{
      'targetMemberId': targetMemberId,
      'reason': reason,
      'requestId': requestId,
    });
    if (transferError != null) throw transferError!;
  }

  @override
  Future<void> submitGovernanceCase({
    required int clubId,
    required bool appeal,
    String? targetType,
    int? targetId,
    required String reason,
    required String requestId,
  }) async {
    cases.add(<String, dynamic>{
      'appeal': appeal,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason,
      'requestId': requestId,
    });
  }
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}

Future<void> _pickMember(WidgetTester tester, int memberId) async {
  await _tapVisible(tester, const Key('governance-pick-member'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('governance-member-$memberId')));
  await tester.pumpAndSettle();
}

Future<int> _daysUntil(String wire) async {
  final DateTime at = DateTime.parse(wire.replaceFirst(' ', 'T'));
  return at.difference(DateTime.now()).inHours ~/ 24;
}

void main() {
  group('governance:权限与状态', () {
    testWidgets('无 member:manage → 无权限屏', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessValue = _access(memberManage: false)
        ..bansValue = <GovernanceBan>[_ban(id: 1)];
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('你没有成员治理的权限'), findsOneWidget);
      expect(find.byKey(const Key('governance-ban')), findsNothing);
    });

    testWidgets('治理记录回执坏了 → 错误态可重试', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()..bansValue = null;
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('治理功能暂时不可用'), findsOneWidget);
      expect(find.text('治理记录暂时不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('成员与记录都空 → 空态', (WidgetTester tester) async {
      final clubApi = _FakeClubApi()
        ..membersValue = <ClubMember>[_member(1, '小柚', owner: true)];
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
          clubApiProvider.overrideWithValue(clubApi),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂无可治理成员'), findsOneWidget);
      expect(find.byKey(const Key('governance-ban')), findsNothing);
    });

    testWidgets('有成员但无记录 → 「暂无治理记录」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(_FakeClubOpsApi()),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂无治理记录'), findsOneWidget);
      expect(find.byKey(const Key('governance-ban')), findsOneWidget);
    });
  });

  group('governance:封禁 / 解封 / 转让', () {
    testWidgets('解封只在「俱乐部封禁且生效中」出现,平台封禁仅平台可解', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..bansValue = <GovernanceBan>[
          _ban(id: 1, nickname: '阿明'),
          _ban(id: 2, sourceType: 'PLATFORM', nickname: '小静'),
          _ban(id: 3, status: 'UNBANNED', nickname: '老王'),
        ];
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('governance-unban-1')), findsOneWidget);
      expect(find.byKey(const Key('governance-unban-2')), findsNothing);
      expect(find.byKey(const Key('governance-unban-3')), findsNothing);
      expect(find.textContaining('仅平台可解封'), findsOneWidget);
    });

    testWidgets('理由为空 → 中止并提示,一个请求都不发', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _pickMember(tester, 12);
      await _tapVisible(tester, const Key('governance-ban'));
      await tester.pumpAndSettle();
      expect(find.text('确认封禁 阿明'), findsOneWidget);

      await tester.tap(find.text('确认封禁'));
      await tester.pumpAndSettle();

      expect(find.text('请填写理由'), findsOneWidget);
      expect(fake.bans, isEmpty, reason: '理由缺失时不能发请求');
    });

    testWidgets('封禁带原因与所选期限;解封带 version', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..bansValue = <GovernanceBan>[_ban(id: 21, version: 5)];
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      await _pickMember(tester, 12);
      // 期限选 7 天。
      await _tapVisible(tester, const Key('governance-pick-duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('governance-duration-7')));
      await tester.pumpAndSettle();
      expect(find.text('7 天'), findsOneWidget);

      await _tapVisible(tester, const Key('governance-ban'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '连续骚扰其他成员');
      await tester.tap(find.text('确认封禁'));
      await tester.pumpAndSettle();

      expect(fake.bans, hasLength(1));
      expect(fake.bans.single['targetMemberId'], 12);
      expect(fake.bans.single['reason'], '连续骚扰其他成员');
      expect(
        await _daysUntil('${fake.bans.single['expiresAt']}'),
        inInclusiveRange(6, 8),
        reason: '选了 7 天就必须按 7 天算到期',
      );
      expect('${fake.bans.single['requestId']}', startsWith('cgb'));

      // 解封:理由可选,直接提交。
      await _tapVisible(tester, const Key('governance-unban-21'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('解除封禁'));
      await tester.pumpAndSettle();

      expect(fake.unbans, hasLength(1));
      expect(fake.unbans.single['banId'], 21);
      expect(fake.unbans.single['version'], 5);
      expect('${fake.unbans.single['requestId']}', startsWith('cgu'));
    });

    testWidgets('转让主理人:非 owner(副主理人)不给入口', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessValue = _access(owner: false, memberManage: true);
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('governance-ban')), findsOneWidget);
      expect(find.byKey(const Key('governance-transfer')), findsNothing);
    });

    testWidgets('转让主理人:owner 必须填交接原因并带 requestId', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('governance-transfer')), findsOneWidget);

      await _pickMember(tester, 12);
      await _tapVisible(tester, const Key('governance-transfer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '身体原因，交给阿明继续带');
      await tester.tap(find.text('确认转让'));
      await tester.pumpAndSettle();

      expect(fake.transfers, hasLength(1));
      expect(fake.transfers.single['targetMemberId'], 12);
      expect(fake.transfers.single['reason'], '身体原因，交给阿明继续带');
      expect('${fake.transfers.single['requestId']}', startsWith('cgt'));
    });
  });

  group('governance:举报 / 申诉', () {
    testWidgets('report 模式缺合法目标 → 直接错误态,不发请求', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1, mode: 'report'), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('缺少合法的举报目标'), findsWidgets);
      expect(fake.accessCalls, 0);
    });

    testWidgets('report 模式(成员举报):提交带 targetType/targetId', (
      WidgetTester tester,
    ) async {
      final fake = _FakeClubOpsApi();
      await tester.pumpWidget(
        _app(
          const ClubGovernancePage(
            clubId: 1,
            mode: 'report',
            targetType: 'MEMBER',
            targetId: 12,
          ),
          <dynamic>[
            clubOpsApiProvider.overrideWithValue(fake),
            clubApiProvider.overrideWithValue(_FakeClubApi()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 标题出现两次:导航栏标准标题(手册 §3.2 N1)+ 页内大标题(D10④)。
      expect(find.text('成员举报'), findsNWidgets(2));
      await _tapVisible(tester, const Key('governance-report'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '在活动现场多次骚扰他人');
      await tester.tap(find.text('提交平台'));
      await tester.pumpAndSettle();

      expect(fake.cases, hasLength(1));
      expect(fake.cases.single['appeal'], isFalse);
      expect(fake.cases.single['targetType'], 'MEMBER');
      expect(fake.cases.single['targetId'], 12);
      expect('${fake.cases.single['requestId']}', startsWith('cgr'));
    });

    testWidgets('appeal 模式不查俱乐部权限,工单空态与提交都成立', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..accessError = _networkFailure()
        ..casesValue = <GovernanceCase>[];
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1, mode: 'appeal'), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      // 标题出现两次:导航栏标准标题(手册 §3.2 N1)+ 页内大标题(D10④)。
      expect(find.text('封禁申诉'), findsNWidgets(2));
      expect(
        fake.accessCalls,
        0,
        reason: '申诉只看自己的工单,不该去查俱乐部权限(否则没权限的人连申诉都递不了)',
      );
      expect(find.text('暂无已提交工单'), findsOneWidget);

      await _tapVisible(tester, const Key('governance-appeal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_reasonFieldKey), '封禁时我并不在现场');
      await tester.tap(find.text('提交平台'));
      await tester.pumpAndSettle();

      expect(fake.cases, hasLength(1));
      expect(fake.cases.single['appeal'], isTrue);
      expect('${fake.cases.single['requestId']}', startsWith('cga'));
    });

    testWidgets('appeal 模式展示已提交工单与平台说明', (WidgetTester tester) async {
      final fake = _FakeClubOpsApi()
        ..casesValue = const <GovernanceCase>[
          GovernanceCase(
            id: 7,
            typeText: '封禁申诉',
            reason: '封禁时我并不在现场',
            createTimeText: '2026-09-05 09:00',
            status: 'REJECTED',
            statusText: '未支持',
            decisionReason: '证据不足',
          ),
        ];
      await tester.pumpWidget(
        _app(const ClubGovernancePage(clubId: 1, mode: 'appeal'), <dynamic>[
          clubOpsApiProvider.overrideWithValue(fake),
          clubApiProvider.overrideWithValue(_FakeClubApi()),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('governance-case-7')), findsOneWidget);
      expect(find.text('未支持'), findsOneWidget);
      expect(find.textContaining('平台说明：证据不足'), findsOneWidget);
    });
  });
}

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/club/access/me'),
  type: DioExceptionType.connectionError,
);
