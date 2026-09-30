import 'package:chengyin_app/data/api/merchant_operator_api.dart';
import 'package:chengyin_app/data/models/merchant_operator.dart';
import 'package:chengyin_app/feature/merchant/merchant_operator_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('分享链接使用 App Universal Link 并编码邀请凭证', () {
    final Uri link = merchantOperatorInviteAppLink(
      'merchant-invite-token:123456',
    );

    expect(link.scheme, 'https');
    expect(link.host, 'api.example.invalid');
    expect(link.path, '/app/merchant/team');
    expect(link.queryParameters['invite'], 'merchant-invite-token:123456');
  });

  testWidgets('店主按小程序顺序看到成员、邀请和岗位选择', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway();
    MerchantInviteCreation? shared;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
          onShareInvite: (MerchantInviteCreation value) async {
            shared = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('经营团队'), findsOneWidget);
    expect(find.text('河畔咖啡'), findsOneWidget);
    expect(find.text('当前岗位 · 店主'), findsOneWidget);
    expect(find.text('团队成员'), findsOneWidget);
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('待接受邀请'), findsOneWidget);

    await tester.tap(find.text('邀请员工'));
    await tester.pumpAndSettle();
    expect(find.text('选择邀请岗位'), findsOneWidget);
    await tester.tap(find.text('财务').first);
    await tester.pumpAndSettle();

    expect(gateway.invitedRole, MerchantOperatorRole.finance);
    expect(find.text('财务邀请已创建'), findsOneWidget);
    await tester.tap(find.text('立即分享'));
    await tester.pumpAndSettle();
    expect(shared?.invite.id, 22);
  });

  testWidgets('改岗和移除都通过 Apple 弹层确认后使用后端版本', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway();
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('operator-role-12')));
    await tester.pumpAndSettle();
    expect(find.text('调整岗位'), findsOneWidget);
    await tester.tap(find.text('核销员'));
    await tester.pumpAndSettle();
    expect(gateway.updatedRole, MerchantOperatorRole.checkin);
    expect(gateway.updatedVersion, 3);

    await tester.tap(find.byKey(const Key('operator-remove-12')));
    await tester.pumpAndSettle();
    expect(find.text('移除团队成员？'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '确认'));
    await tester.pumpAndSettle();
    expect(gateway.removedId, 12);
    expect(gateway.removedVersion, 3);
  });

  testWidgets('员工只看到自己的岗位权限，不触发团队敏感读取', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..owner = false;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的岗位权限'), findsOneWidget);
    expect(find.text('运营'), findsOneWidget);
    expect(find.text('邀请员工'), findsNothing);
    expect(gateway.teamCalls, 0);
    expect(gateway.rolesCalls, 0);
  });

  testWidgets('员工进入工作台默认导航到商家一级页', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..owner = false;
    final GoRouter router = GoRouter(
      initialLocation: '/team',
      routes: <RouteBase>[
        GoRoute(
          path: '/team',
          builder: (_, _) => MerchantOperatorPage(
            api: gateway,
            intentStore: gateway.intentStore,
          ),
        ),
        GoRoute(
          path: '/merchant',
          builder: (_, _) =>
              const CupertinoPageScaffold(child: Center(child: Text('商家工作台'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(CupertinoApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('进入工作台'));
    await tester.pumpAndSettle();

    expect(find.text('商家工作台'), findsOneWidget);
  });

  testWidgets('撤销邀请确认后使用邀请版本', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway();
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('operator-revoke-invite-21')));
    await tester.pumpAndSettle();
    expect(find.text('撤销这条邀请？'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '确认'));
    await tester.pumpAndSettle();

    expect(gateway.revokedInviteId, 21);
    expect(gateway.revokedInviteVersion, 0);
  });

  testWidgets('无团队身份但带邀请凭证时可接受并回读身份', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()
      ..owner = false
      ..accessActive = false;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
          incomingInviteToken: 'merchant-invite-token-123456',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('加入经营团队'), findsOneWidget);
    await tester.tap(find.text('接受邀请'));
    await tester.pumpAndSettle();

    expect(gateway.acceptedToken, 'merchant-invite-token-123456');
    expect(find.text('你的岗位权限'), findsOneWidget);
  });

  testWidgets('已有经营身份时仍显示传入邀请并在处理后收起', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway();
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
          incomingInviteToken: 'merchant-invite-token-123456',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你还有一条团队邀请'), findsOneWidget);
    await tester.tap(find.text('接受'));
    await tester.pumpAndSettle();

    expect(gateway.acceptedToken, 'merchant-invite-token-123456');
    expect(find.text('你还有一条团队邀请'), findsNothing);
  });

  testWidgets('岗位加载失败不遮住团队名单并可独立重试', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..rolesFailure = true;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小林'), findsOneWidget);
    expect(find.text('岗位列表暂未更新'), findsOneWidget);
    expect(find.text('邀请员工'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoButton>(find.widgetWithText(CupertinoButton, '邀请员工'))
          .onPressed,
      isNull,
    );

    gateway.rolesFailure = false;
    await tester.tap(find.widgetWithText(CupertinoButton, '重试'));
    await tester.pumpAndSettle();
    expect(find.text('岗位列表暂未更新'), findsNothing);
  });

  testWidgets('5xx 后页面重建复用 requestId，明确 4xx 后清理', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..inviteErrorCode = 500;

    Future<void> build() => tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          key: UniqueKey(),
          api: gateway,
          intentStore: gateway.intentStore,
        ),
      ),
    );

    await build();
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请员工'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('财务').first);
    await tester.pumpAndSettle();
    final String uncertainRequestId = gateway.inviteRequestIds.single;
    expect(gateway.intentStore.values.values, contains(uncertainRequestId));

    gateway.inviteErrorCode = null;
    await build();
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请员工'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('财务').first);
    await tester.pumpAndSettle();
    expect(gateway.inviteRequestIds.last, uncertainRequestId);
    expect(gateway.intentStore.values, isEmpty);

    final _Gateway rejected = _Gateway()..inviteErrorCode = 400;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          key: UniqueKey(),
          api: rejected,
          intentStore: rejected.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请员工'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('财务').first);
    await tester.pumpAndSettle();
    final String rejectedRequestId = rejected.inviteRequestIds.single;
    expect(rejected.intentStore.values, isEmpty);

    rejected.inviteErrorCode = null;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          key: UniqueKey(),
          api: rejected,
          intentStore: rejected.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('邀请员工'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('财务').first);
    await tester.pumpAndSettle();
    expect(rejected.inviteRequestIds.last, isNot(rejectedRequestId));
  });

  testWidgets('写回执确认后名单刷新失败不误报写失败且本地先更新', (WidgetTester tester) async {
    final _Gateway gateway = _Gateway()..teamFailureAfterCall = 2;
    await tester.pumpWidget(
      CupertinoApp(
        home: MerchantOperatorPage(
          api: gateway,
          intentStore: gateway.intentStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('operator-remove-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '确认'));
    await tester.pumpAndSettle();

    expect(gateway.removedId, 12);
    expect(find.text('小林'), findsNothing);
    expect(gateway.intentStore.values, isEmpty);
    expect(find.textContaining('成员已移除，但团队名单刷新失败'), findsOneWidget);
  });
}

class _Gateway implements MerchantOperatorGateway {
  final _IntentStore intentStore = _IntentStore();
  bool owner = true;
  bool accessActive = true;
  bool accepted = false;
  bool rolesFailure = false;
  int? inviteErrorCode;
  int? teamFailureAfterCall;
  int teamCalls = 0;
  int rolesCalls = 0;
  MerchantOperatorRole? invitedRole;
  MerchantOperatorRole? updatedRole;
  int? updatedVersion;
  int? removedId;
  int? removedVersion;
  int? revokedInviteId;
  int? revokedInviteVersion;
  String? acceptedToken;
  final List<String> inviteRequestIds = <String>[];

  MerchantOperator get operator => MerchantOperator(
    id: 12,
    nickname: '小林',
    avatar: null,
    role: MerchantOperatorRole.marketing,
    status: MerchantOperatorStatus.active,
    acceptedAt: DateTime(2026, 8, 27, 10, 30),
    version: 3,
  );

  @override
  Future<MerchantOperatorAccess> access() async {
    final bool active = accessActive || accepted;
    return MerchantOperatorAccess(
      active: active,
      merchantId: active ? 1 : null,
      merchantName: active ? '河畔咖啡' : null,
      merchantLogo: null,
      roleCode: active
          ? (owner ? 'MERCHANT_OWNER' : 'MERCHANT_MARKETING')
          : null,
      permissions: active
          ? (owner
                ? const <String>{'merchant:operator:manage'}
                : const <String>{
                    'merchant:crm:read',
                    'merchant:marketing:write',
                  })
          : const <String>{},
      canManageOperators: active && owner,
    );
  }

  @override
  Future<List<MerchantAssignableRole>> roles() async {
    rolesCalls += 1;
    if (rolesFailure) {
      throw const MerchantOperatorApiException('岗位列表加载失败', code: 500);
    }
    return MerchantOperatorRole.values
        .map(
          (MerchantOperatorRole role) => MerchantAssignableRole(
            role: role,
            name: role.label,
            permissions: switch (role) {
              MerchantOperatorRole.checkin => const <String>{'merchant:verify'},
              MerchantOperatorRole.marketing => const <String>{
                'merchant:crm:read',
                'merchant:marketing:write',
              },
              MerchantOperatorRole.finance => const <String>{
                'merchant:finance:read',
              },
              MerchantOperatorRole.manager => const <String>{
                'merchant:project:manage',
              },
            },
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<MerchantTeam> team() async {
    teamCalls += 1;
    if (teamFailureAfterCall != null && teamCalls >= teamFailureAfterCall!) {
      throw const MerchantOperatorApiException('团队名单加载失败', code: 500);
    }
    return MerchantTeam(
      operators: <MerchantOperator>[operator],
      invites: <MerchantOperatorInvite>[
        MerchantOperatorInvite(
          id: 21,
          role: MerchantOperatorRole.finance,
          status: MerchantInviteStatus.pending,
          expiresAt: DateTime(2026, 8, 28, 10, 30),
          version: 0,
        ),
      ],
    );
  }

  @override
  Future<MerchantInviteCreation> invite({
    required MerchantOperatorRole role,
    required String requestId,
  }) async {
    inviteRequestIds.add(requestId);
    invitedRole = role;
    if (inviteErrorCode != null) {
      throw MerchantOperatorApiException('邀请创建失败', code: inviteErrorCode);
    }
    return MerchantInviteCreation(
      invite: MerchantOperatorInvite(
        id: 22,
        role: role,
        status: MerchantInviteStatus.pending,
        expiresAt: DateTime(2026, 8, 28, 11),
        version: 0,
      ),
      token: 'merchant-invite-token-123456',
    );
  }

  @override
  Future<MerchantOperatorReceipt> updateRole({
    required MerchantOperator operator,
    required MerchantOperatorRole role,
    required String requestId,
  }) async {
    updatedRole = role;
    updatedVersion = operator.version;
    return MerchantOperatorReceipt(
      operator: MerchantOperator(
        id: operator.id,
        nickname: operator.nickname,
        avatar: operator.avatar,
        role: role,
        status: MerchantOperatorStatus.active,
        acceptedAt: operator.acceptedAt,
        version: operator.version + 1,
      ),
      mutationState: MerchantMutationState.exactResult,
    );
  }

  @override
  Future<MerchantOperatorReceipt> remove({
    required MerchantOperator operator,
    required String reason,
    required String requestId,
  }) async {
    removedId = operator.id;
    removedVersion = operator.version;
    return MerchantOperatorReceipt(
      operator: MerchantOperator(
        id: operator.id,
        nickname: operator.nickname,
        avatar: operator.avatar,
        role: operator.role,
        status: MerchantOperatorStatus.revoked,
        acceptedAt: operator.acceptedAt,
        version: operator.version + 1,
      ),
      mutationState: MerchantMutationState.exactResult,
    );
  }

  @override
  Future<MerchantInviteReceipt> revokeInvite({
    required MerchantOperatorInvite invite,
    required String reason,
    required String requestId,
  }) async {
    revokedInviteId = invite.id;
    revokedInviteVersion = invite.version;
    return MerchantInviteReceipt(
      invite: MerchantOperatorInvite(
        id: invite.id,
        role: invite.role,
        status: MerchantInviteStatus.revoked,
        expiresAt: invite.expiresAt,
        version: invite.version + 1,
      ),
      mutationState: MerchantMutationState.exactResult,
    );
  }

  @override
  Future<MerchantOperator> acceptInvite({
    required String token,
    required String requestId,
  }) async {
    acceptedToken = token;
    accepted = true;
    return MerchantOperator(
      id: 18,
      nickname: '小陈',
      avatar: null,
      role: MerchantOperatorRole.marketing,
      status: MerchantOperatorStatus.active,
      acceptedAt: DateTime(2026, 8, 27, 11),
      version: 0,
    );
  }
}

class _IntentStore implements MerchantOperatorIntentStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String intentKey) async => values[intentKey];

  @override
  Future<void> write(String intentKey, String requestId) async {
    values[intentKey] = requestId;
  }

  @override
  Future<void> delete(String intentKey) async {
    values.remove(intentKey);
  }
}
