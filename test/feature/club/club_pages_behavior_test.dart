// 俱乐部管理页的行为门(负控):权限门、防重复操作门、解散确认档。
//
// 只测「该红的必须红」的判据,不碰网络 —— API 全部 override 成假实现:
//   - clubApiProvider      → _FakeClubApi(记录调用,可挂闸)
//   - clubCompensationApiProvider / groupCodeApiProvider → 假实现
//   - clubDetailProvider / clubTopicsProvider / clubMembersProvider /
//     clubJoinRequestsProvider / clubTeamDetailProvider → 固定假数据
//   - authControllerProvider → 可注入任意 User.role / null
//
// 判据对齐小程序与后端授权模型:
//   - enroll 退款 = 只有 owner 看得到「退款」,管理员(role=1 且是自己)只读;
//   - join-requests 处理中两键同禁(防连点把同一条处理两遍);
//   - apply 第 1 步实名/昵称+联系方式都填了才能继续;
//   - edit 解散:有非创建者成员 → 必须过「确认成员后果」档才真正调 dissolve。

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/group_code_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_apply_page.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_edit_page.dart';
import 'package:chengyin_app/feature/club/club_enroll_page.dart';
import 'package:chengyin_app/feature/club/club_group_code_page.dart';
import 'package:chengyin_app/feature/club/club_join_requests_page.dart';

import '../../support/fake_publisher_identity.dart';

Widget _app(List<dynamic> overrides, Widget home, {Locale locale = const Locale('zh')}) {
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

/// RUN-52 后第 4 屏多了发布者实名闸:本文件旧用例「不填实名直接提交」的
/// 动作会被闸挡下。这里替它们补齐三项(登记规则由 club_apply_identity_test
/// 单独钉),保住本文件原本要测的 payload / 错误条断言。
Future<void> _fillPublisherIdentity(WidgetTester tester) async {
  final Finder name =
      find.byKey(const ValueKey<String>('identity-real-name'));
  final Finder idCard =
      find.byKey(const ValueKey<String>('identity-id-card'));
  final Finder consent = find.byKey(const Key('identity-consent'));
  await tester.ensureVisible(name);
  await tester.pumpAndSettle();
  await tester.enterText(name, '陈晨');
  await tester.enterText(idCard, '99000019491231019X');
  await tester.ensureVisible(consent);
  await tester.pumpAndSettle();
  await tester.tap(consent);
  await tester.pump();
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

/// 记录调用、可挂闸的 ClubApi 假实现。
class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dummyDioClient());

  Completer<void> reviewGate = Completer<void>();
  int? reviewedMemberId;
  bool? reviewedApprove;

  Completer<void> dissolveGate = Completer<void>();
  int? dissolvedId;
  bool? dissolvedMembersConfirmed;
  Map<String, dynamic>? becomeLeaderPayload;
  Map<String, dynamic>? updateMinePayload;
  Object? becomeLeaderError;

  @override
  Future<void> becomeLeader(Map<String, dynamic> payload) async {
    becomeLeaderPayload = Map<String, dynamic>.from(payload);
    if (becomeLeaderError != null) throw becomeLeaderError!;
  }

  @override
  Future<void> updateMine(Map<String, dynamic> payload) async {
    updateMinePayload = Map<String, dynamic>.from(payload);
  }

  @override
  Future<void> reviewJoinRequest({
    required int clubId,
    required int memberId,
    required bool approve,
  }) async {
    reviewedMemberId = memberId;
    reviewedApprove = approve;
    await reviewGate.future;
  }

  @override
  Future<void> dissolve({
    required int id,
    required bool memberConsequencesConfirmed,
  }) async {
    dissolvedId = id;
    dissolvedMembersConfirmed = memberConsequencesConfirmed;
    await dissolveGate.future;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;

  @override
  AuthState build() => _initial;

  @override
  Future<void> refreshRole() async {}
}

AuthState _auth(User? user) => AuthState(user: user, initialized: true);

Club _club({bool owner = false, int nonOwner = 0, int pending = 0}) => Club(
  id: 1,
  name: '城西探店社',
  city: '上海',
  isOwner: owner,
  nonOwnerMemberCount: nonOwner,
  pendingJoinRequestCount: pending,
);

JoinRequest _req(int memberId, String nick) => JoinRequest(
  memberId: memberId,
  nickname: nick,
  joinTime: '2026-08-19T10:20:00',
);

void main() {
  group('join-requests:防连点门', () {
    testWidgets('处理中通过/拒绝两键同禁,完成才恢复', (WidgetTester tester) async {
      final fake = _FakeClubApi();
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(fake),
          clubJoinRequestsProvider(1).overrideWith(
            (ref) async => <JoinRequest>[_req(11, '小明'), _req(12, '小红')],
          ),
        ], const ClubJoinRequestsPage(clubId: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('小明'), findsOneWidget);

      // 点「通过」→ 确认弹窗。
      await tester.tap(find.widgetWithText(CupertinoButton, '通过').first);
      await tester.pumpAndSettle();
      expect(find.text('通过入会申请'), findsOneWidget);

      // 确认 → reviewJoinRequest 挂闸(未完成),两键应同禁。
      await tester.tap(find.text('通过').last);
      await tester.pump();
      await tester.pump();
      expect(fake.reviewedMemberId, 11);
      expect(fake.reviewedApprove, isTrue);

      // ★ 断言对象要挑准:处理中那一行的「通过」按钮**文案会被转圈替换掉**,
      //   所以 find.widgetWithText(CupertinoButton,'通过').first 找到的是**另一行**
      //   (小红)的按钮 —— 那一行本来就不该禁,断言它必然失败。
      //   正确做法:①处理中的行以转圈为证 ②该行的「拒绝」文案不变,断它被禁。
      expect(
        find.descendant(
          of: find
              .ancestor(of: find.text('小明'), matching: find.byType(Row))
              .last,
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
        reason: '处理中的那一行「通过」应显示转圈,即已进入 busy 态',
      );
      final rejectBtn = tester.widget<CupertinoButton>(
        find
            .descendant(
              of: find
                  .ancestor(of: find.text('小明'), matching: find.byType(Row))
                  .last,
              matching: find.widgetWithText(CupertinoButton, '拒绝'),
            )
            .first,
      );
      expect(rejectBtn.onPressed, isNull, reason: '处理中同一行的「拒绝」必须一起禁用');

      // 放闸 → 完成,按钮恢复可点。
      fake.reviewGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('已通过'), findsOneWidget);
      expect(
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, '通过').first,
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  group('enroll:退款权限门', () {
    testWidgets('English roster preserves denied permission and no refund action', (tester) async {
      await tester.pumpWidget(_app([
        clubDetailProvider(1).overrideWith((ref) async => _club()),
        clubMembersProvider(1).overrideWith((ref) async => <ClubMember>[]),
      ], const ClubEnrollPage(clubId: 1), locale: const Locale('en')));
      await tester.pumpAndSettle();
      expect(find.text('You cannot view the registration roster'), findsOneWidget);
      expect(find.text('Refund'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('非 owner 非管理员 → 无权限', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          clubDetailProvider(1).overrideWith((ref) async => _club()),
          clubMembersProvider(1).overrideWith((ref) async => <ClubMember>[]),
        ], const ClubEnrollPage(clubId: 1, clubName: '城西探店社')),
      );
      await tester.pumpAndSettle();

      expect(find.text('没有权限查看报名名册'), findsOneWidget);
    });

    testWidgets('owner → 看到可退款报名者的「退款」', (WidgetTester tester) async {
      final team = ClubTopic(
        id: 10,
        name: '静安第一期',
        signupCount: 1,
        startDate: '2026-08-24 14:00',
      );
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi()),
          clubDetailProvider(1).overrideWith((ref) async => _club(owner: true)),
          clubTopicsProvider(1).overrideWith((ref) async => <ClubTopic>[team]),
          clubMembersProvider(1).overrideWith((ref) async => <ClubMember>[]),
          clubTeamDetailProvider((clubId: 1, topicId: 10)).overrideWith(
            (ref) async => TeamDetail(
              tickets: <TeamTicket>[
                TeamTicket(
                  name: '早鸟票',
                  totalInventory: 20,
                  teamStatus: 1,
                  regs: <TeamRegistrant>[
                    TeamRegistrant(
                      id: 1001,
                      nickname: '阿明',
                      paymentStatus: 2,
                      verificationStatus: 0,
                    ),
                    TeamRegistrant(
                      id: 1002,
                      nickname: '小静',
                      paymentStatus: 2,
                      verificationStatus: 1,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ], const ClubEnrollPage(clubId: 1, clubName: '城西探店社')),
      );
      await tester.pumpAndSettle();

      expect(find.text('静安第一期'), findsOneWidget);

      // 展开该团 → 名单出现。
      await tester.tap(find.text('静安第一期'));
      await tester.pumpAndSettle();

      expect(find.text('阿明'), findsOneWidget);
      // 已支付且未核销 → 可退。
      expect(find.text('退款'), findsOneWidget);
      // 已核销的不可退,只有一条「退款」。
      expect(find.text('退款'), findsOneWidget);
    });

    testWidgets('管理员(role=1 是自己)只读:有团但无「退款」', (WidgetTester tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      final team = ClubTopic(
        id: 10,
        name: '静安第一期',
        signupCount: 1,
        startDate: '2026-08-24 14:00',
      );
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi()),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(
              _auth(User(id: 5, nickname: '管理员', avatar: '', role: 'player')),
            ),
          ),
          clubDetailProvider(1).overrideWith(
            (ref) async => _club(), // 非 owner
          ),
          clubTopicsProvider(1).overrideWith((ref) async => <ClubTopic>[team]),
          clubMembersProvider(1).overrideWith(
            (ref) async => <ClubMember>[
              ClubMember(memberId: 5, nickname: '管理员', role: 1),
            ],
          ),
          clubTeamDetailProvider((clubId: 1, topicId: 10)).overrideWith(
            (ref) async => TeamDetail(
              tickets: <TeamTicket>[
                TeamTicket(
                  name: '早鸟票',
                  totalInventory: 20,
                  teamStatus: 1,
                  regs: <TeamRegistrant>[
                    TeamRegistrant(
                      id: 1001,
                      nickname: '阿明',
                      paymentStatus: 2,
                      verificationStatus: 0,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ], const ClubEnrollPage(clubId: 1, clubName: '城西探店社')),
      );
      await tester.pumpAndSettle();

      // 有权限看到名单。
      expect(find.text('静安第一期'), findsOneWidget);
      await tester.tap(find.text('静安第一期'));
      await tester.pumpAndSettle();

      // 管理员只读:能看到人,但看不到「退款」。
      expect(find.text('阿明'), findsOneWidget);
      expect(find.text('退款'), findsNothing);
      // 主理人/管理员都能出示团码。
      expect(find.text('出示团码'), findsOneWidget);
      final Finder showCode = find.byKey(const Key('club-team-group-code-10'));
      expect(showCode, findsOneWidget);
      expect(tester.getRect(showCode).width, greaterThanOrEqualTo(44));
      expect(tester.getRect(showCode).height, greaterThanOrEqualTo(44));
      final CupertinoButton showCodeButton = tester.widget<CupertinoButton>(
        find.descendant(of: showCode, matching: find.byType(CupertinoButton)),
      );
      expect(
        showCodeButton.minimumSize?.height ?? 0,
        greaterThanOrEqualTo(44),
        reason: '团码必须依靠按钮本身的 44pt 热区，不能依靠 Transform 放大命中区',
      );
      final showCodeSemantics = tester.getSemantics(showCode);
      final showCodeData = showCodeSemantics.getSemanticsData();
      expect(showCodeData.label, '出示团码');
      expect(showCodeData.hasAction(ui.SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    // E-07(真源 enroll/index.js:46-49,292):主题页「核销台账」带着
    // topicId 进来 → 到达即展开那一团并拉名单;预展开不是过滤,其他团照列。
    testWidgets('带 topicId 进来:那一团不用人再点一次', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi()),
          clubDetailProvider(1).overrideWith((ref) async => _club(owner: true)),
          clubTopicsProvider(1).overrideWith(
            (ref) async => <ClubTopic>[
              ClubTopic(
                id: 10,
                name: '静安第一期',
                signupCount: 1,
                startDate: '2026-08-24 14:00',
              ),
              ClubTopic(
                id: 11,
                name: '静安第二期',
                signupCount: 0,
                startDate: '2026-09-24 14:00',
              ),
            ],
          ),
          clubMembersProvider(1).overrideWith((ref) async => <ClubMember>[]),
          clubTeamDetailProvider((clubId: 1, topicId: 10)).overrideWith(
            (ref) async => TeamDetail(
              tickets: <TeamTicket>[
                TeamTicket(
                  name: '早鸟票',
                  totalInventory: 20,
                  teamStatus: 1,
                  regs: <TeamRegistrant>[
                    TeamRegistrant(
                      id: 1001,
                      nickname: '阿明',
                      paymentStatus: 2,
                      verificationStatus: 0,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ], const ClubEnrollPage(clubId: 1, clubName: '城西探店社', topicId: 10)),
      );
      await tester.pumpAndSettle();

      expect(find.text('静安第二期'), findsOneWidget, reason: '预展开≠过滤');
      expect(find.text('阿明'), findsOneWidget, reason: '该团到达即展开');
    });
  });

  group('apply:第一步门', () {
    testWidgets('实名/昵称与联系方式都填了才能「继续」', (WidgetTester tester) async {
      await tester.pumpWidget(_app(<dynamic>[], const ClubApplyPage()));
      await tester.pumpAndSettle();

      CupertinoButton next() => tester.widget<CupertinoButton>(
        find.ancestor(
          of: find.text('继续'),
          matching: find.byType(CupertinoButton),
        ),
      );

      expect(next().onPressed, isNull, reason: '空表不能进下一步');

      await tester.enterText(find.byType(CupertinoTextField).at(0), '陈晨');
      await tester.pump();
      expect(next().onPressed, isNull, reason: '只填实名/昵称还不够');

      await tester.enterText(
        find.byType(CupertinoTextField).at(1),
        '13800000000',
      );
      await tester.pump();
      expect(next().onPressed, isNotNull, reason: '实名/昵称+联系方式齐了才能继续');
    });

    testWidgets('四步提交保留小程序 payload 并停在完成态', (WidgetTester tester) async {
      final _FakeClubApi fake = _FakeClubApi();
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(fake),
          publisherIdentityApiProvider.overrideWithValue(
            FakePublisherIdentityApi(),
          ),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_auth(null)),
          ),
        ], const ClubApplyPage()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-leader-name')),
        '陈晨',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-phone')),
        'chenchen_wechat',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-identity')),
        '户外领队',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-cofounders')),
        '小林,阿明',
      );
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('5-20场'));
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-max-size')),
        '50',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-avg-size')),
        '20',
      );
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pump();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await _fillPublisherIdentity(tester);
      await tester.tap(find.text('成为俱乐部主理人'));
      await tester.pumpAndSettle();

      expect(fake.becomeLeaderPayload, <String, dynamic>{
        'leaderName': '陈晨',
        'phone': 'chenchen_wechat',
        'identity': '户外领队',
        'coFounders': '小林,阿明',
        'experience': '5-20场',
        'hasExperience': 1,
        'maxEventSize': 50,
        'avgEventSize': 20,
        'canDesignRoute': 1,
        'canDesignTask': 0,
        'canNpc': 0,
        'canMerchantCoop': 0,
        'hasGuideCert': 0,
        'certImages': '',
      });
      expect(find.text('已成为主理人'), findsOneWidget);
      expect(find.text('创建我的俱乐部'), findsOneWidget);
    });

    // 真源 apply/index.wxml:159:提交失败是第 4 步页内 `cy-inline-error`
    // (主标+原因+重试),不是弹窗 —— 弹窗会把已填表单的上下文整个丢掉。
    testWidgets('提交失败落第 4 步页内错误条并可重试,不弹 alert', (WidgetTester tester) async {
      final _FakeClubApi fake = _FakeClubApi()
        ..becomeLeaderError = ClubApiException('资料不全,请补齐实名');
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(fake),
          publisherIdentityApiProvider.overrideWithValue(
            FakePublisherIdentityApi(),
          ),
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_auth(null)),
          ),
        ], const ClubApplyPage()),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-leader-name')),
        '陈晨',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-apply-phone')),
        'chenchen_wechat',
      );
      await tester.pump();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5-20场'));
      await tester.pump();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.pump();
      await _fillPublisherIdentity(tester);
      await tester.tap(find.text('成为俱乐部主理人'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(find.byKey(const Key('apply-submit-error')), findsOneWidget);
      expect(find.text('提交没有完成'), findsOneWidget);
      expect(find.text('资料不全,请补齐实名'), findsOneWidget);

      // 后端放行后点「重试」→ 原样再提交一次,进完成态,错误条消失。
      fake.becomeLeaderError = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(fake.becomeLeaderPayload?['leaderName'], '陈晨');
      expect(find.text('已成为主理人'), findsOneWidget);
      expect(find.byKey(const Key('apply-submit-error')), findsNothing);
    });
  });

  group('edit:解散档', () {
    testWidgets('保存保留小程序经营字段且不提交停用会员价', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final _FakeClubApi fake = _FakeClubApi();
      final Club editable = Club(
        id: 1,
        name: '城西探店社',
        city: '上海',
        logo: 'https://img/logo.jpg',
        cover: 'https://img/cover.jpg',
        description: '老介绍',
        clubType: '兴趣社群',
        activityPrefs: const <String>['城市定向'],
        keywords: '探店',
        style: '轻松',
        prioritySignupEnabled: false,
        memberReservedQuota: 3,
        joinPolicySupported: true,
        joinPolicy: 0,
      );
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(fake),
          clubDetailProvider(1).overrideWith((ref) async => editable),
        ], const ClubEditPage(clubId: 1)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('club-edit-name')),
        '城西新探店社',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-edit-city')),
        '杭州',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('club-edit-pref-轻社交')),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('club-member-reserved-quota')),
        '5',
      );
      await tester.tap(find.byType(CupertinoSwitch).at(0));
      await tester.tap(find.byType(CupertinoSwitch).at(1));
      await tester.pump();
      await tester.tap(find.text('保存修改'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fake.updateMinePayload, containsPair('id', 1));
      expect(fake.updateMinePayload, containsPair('name', '城西新探店社'));
      expect(fake.updateMinePayload, containsPair('city', '杭州'));
      expect(fake.updateMinePayload, containsPair('address', '杭州'));
      expect(fake.updateMinePayload, containsPair('memberReservedQuota', 5));
      expect(fake.updateMinePayload, containsPair('prioritySignupEnabled', 1));
      expect(fake.updateMinePayload, containsPair('joinPolicy', 1));
      expect(fake.updateMinePayload?['activityPrefs'], '城市定向,轻社交');
      expect(fake.updateMinePayload, isNot(contains('memberDiscountPrice')));
    });

    testWidgets('有非创建者成员 → 必须先过「确认成员后果」档', (WidgetTester tester) async {
      final fake = _FakeClubApi();
      await tester.pumpWidget(
        _app(<dynamic>[
          clubApiProvider.overrideWithValue(fake),
          clubDetailProvider(
            1,
          ).overrideWith((ref) async => _club(owner: true, nonOwner: 2)),
        ], const ClubEditPage(clubId: 1)),
      );
      await tester.pumpAndSettle();

      // 滚到底部找到解散按钮。
      // ★ finder 必须精确到**按钮**:页面上「解散俱乐部」同时是分区标题和按钮文案,
      //   用 find.text 会匹配到多个,scrollUntilVisible 直接抛 Bad state: Too many elements。
      await tester.scrollUntilVisible(
        find.widgetWithText(CupertinoButton, '解散俱乐部'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(CupertinoButton, '解散俱乐部'));
      await tester.pumpAndSettle();

      // 第一档:解散本身不可逆。
      // ★ 不数「解散俱乐部」出现几次 —— 页面上分区标题、按钮、弹窗标题都是这四个字,
      //   数字符串既脆(加一个标题就红)又不防 bug。断**这一档独有的正文**才算数。
      expect(find.text('解散后俱乐部及其项目将不可恢复。确定继续吗?'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();

      // 第二档:确认成员后果(有 2 位非创建者成员)。
      expect(find.text('确认成员后果'), findsOneWidget);
      expect(find.textContaining('2 位其他成员'), findsOneWidget);

      // 在第二档确认前,dissolve 必须还没被调。
      expect(fake.dissolvedId, isNull, reason: '成员后果未确认前不许调 dissolve');

      fake.dissolveGate.complete();
      await tester.tap(find.text('仍要解散'));
      await tester.pumpAndSettle();

      expect(fake.dissolvedId, 1);
      expect(fake.dissolvedMembersConfirmed, isTrue);
    });
  });

  group('group-code:状态机', () {
    testWidgets('带 activityId → 直接出码', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          groupCodeApiProvider.overrideWithValue(_FakeGroupCodeApi()),
        ], const ClubGroupCodePage(activityId: 77, activityName: '静安第一期')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('静安第一期 · 团核销码'), findsOneWidget);
      expect(find.text('KX-2026-08-19-01'), findsOneWidget);
      // ★ 剩余时间**不上屏**:小程序那张稿没画,倒计时只是内部态。
      expect(find.textContaining('后自动刷新'), findsNothing);

      // 收尾:销毁页面释放周期 Timer,避免遗留 pending timer。
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('无任何参数 → 缺参终态,只给「进入俱乐部管理」', (WidgetTester tester) async {
      await tester.pumpWidget(_app(<dynamic>[], const ClubGroupCodePage()));
      await tester.pump();
      await tester.pump();

      // 小程序 group-code 的 invalid 终态主标逐字:「缺少路线或场次信息」。
      expect(find.text('缺少路线或场次信息'), findsOneWidget);
      // 终态:没有重试键(重试必然再失败),出路只有俱乐部管理。
      expect(find.text('返回俱乐部，选择具体场次后再出示团码'), findsOneWidget);
      expect(find.text('请从俱乐部管理进入具体场次'), findsOneWidget);
      expect(find.text('进入俱乐部管理'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });

    testWidgets('403/无权限 → 出码权限终态,不落进通用的「出码失败」', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(<dynamic>[
          groupCodeApiProvider.overrideWithValue(_DeniedGroupCodeApi()),
        ], const ClubGroupCodePage(activityId: 77, activityName: '静安第一期')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('当前账号没有出码权限'), findsOneWidget);
      expect(find.text('当前账号不能出示这一场的团码'), findsOneWidget);
      expect(find.text('进入俱乐部管理'), findsOneWidget);
      expect(find.text('出码失败'), findsNothing);
    });

    testWidgets('★ 出码卡能保存到相册(下载→写相册→回话)', (WidgetTester tester) async {
      final List<String> saved = <String>[];
      saveGroupCodeToAlbum = (Uint8List bytes, String name) async {
        saved.add('$name:${bytes.length}');
      };
      addTearDown(() {
        saveGroupCodeToAlbum = (Uint8List bytes, String name) =>
            Gal.putImageBytes(bytes, name: name);
      });

      await tester.pumpWidget(
        _app(<dynamic>[
          groupCodeApiProvider.overrideWithValue(
            _FakeGroupCodeApi(qrUrl: 'https://cdn.example.com/qr.png'),
          ),
        ], const ClubGroupCodePage(activityId: 77, activityName: '静安第一期')),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('group-code-save')));
      await tester.pumpAndSettle();

      expect(saved, <String>['团核销码:3'], reason: '存进相册的必须是下载下来的字节');
      expect(find.text('已存到相册，可打印后贴在站点'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

/// 后端 403 拒绝(「您没有该场次的团码核销权限」):终态。
class _DeniedGroupCodeApi extends GroupCodeApi {
  _DeniedGroupCodeApi() : super(_dummyDioClient());

  @override
  Future<GroupCodeIssue> issue(int activityId) async {
    throw const GroupCodePermissionException('您没有该场次的团码核销权限');
  }
}

class _FakeGroupCodeApi extends GroupCodeApi {
  _FakeGroupCodeApi({this.qrUrl = ''}) : super(_dummyDioClient());

  final String qrUrl;

  @override
  Future<GroupCodeIssue> issue(int activityId) async {
    return GroupCodeIssue(
      qrcodeUrl: qrUrl,
      code: 'KX-2026-08-19-01',
      ttlMs: 5000,
    );
  }

  @override
  Future<Uint8List> fetchQrBytes(String url) async =>
      Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Future<List<GroupCodeActivity>> activities(int topicId) async =>
      const <GroupCodeActivity>[];
}
