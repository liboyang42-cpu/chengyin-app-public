// a2-club-entry 条目7/10 的行为门(enroll 名册页):
//   - topic-detail「核销台账」带着 topicId 进来(小程序 enroll `focusTopicId`)
//     → 本主题的团**默认展开**,别的不展开;
//   - 报名行头像可点 → 玩家公开主页 /user/<memberId>(小程序
//     `enroll/index.wxml:66`);拿不到 memberId 不给点。
//
// API 全部钉假数据:名册权限走 owner,团与名单来自固定 fixture。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_enroll_page.dart';

import '../../support/fixed_auth.dart';

class _StubClubApi extends ClubApi {
  _StubClubApi() : super(_dummyDioClient());
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

ClubTopic _team(int id, String name) => ClubTopic(
  id: id,
  name: name,
  signupCount: 2,
  startDate: '2026-08-24 14:00',
);

TeamDetail _detail({required int regId, required String nickname}) =>
    TeamDetail(
      tickets: <TeamTicket>[
        TeamTicket(
          name: '早鸟票',
          totalInventory: 20,
          teamStatus: 1,
          regs: <TeamRegistrant>[
            TeamRegistrant(
              id: regId,
              nickname: nickname,
              memberId: regId + 50,
              paymentStatus: 2,
              verificationStatus: 0,
            ),
            // 没绑会员的历史报名:头像不给点。
            TeamRegistrant(
              id: regId + 1,
              nickname: '$nickname-无会员',
              paymentStatus: 2,
              verificationStatus: 0,
            ),
          ],
        ),
      ],
    );

Future<GoRouter> _pump(WidgetTester tester, {int? topicId}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1000));
  final router = GoRouter(
    initialLocation: '/enroll',
    routes: <RouteBase>[
      GoRoute(
        path: '/enroll',
        builder: (_, _) =>
            ClubEnrollPage(clubId: 1, clubName: '城西探店社', topicId: topicId),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, state) =>
            Scaffold(body: Text('user-${state.pathParameters['id']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(
          () => FixedAuth(
            AuthState(
              user: User(id: 1, nickname: '主理人', avatar: '', role: 'player'),
              initialized: true,
            ),
          ),
        ),
        clubApiProvider.overrideWithValue(_StubClubApi()),
        clubDetailProvider(1).overrideWith(
          (ref) async => Club(id: 1, name: '城西探店社', isOwner: true),
        ),
        clubTopicsProvider(1).overrideWith(
          (ref) async => <ClubTopic>[_team(10, '静安第一期'), _team(11, '徐汇晨光')],
        ),
        clubMembersProvider(1).overrideWith((ref) async => <ClubMember>[]),
        clubTeamDetailProvider((
          clubId: 1,
          topicId: 10,
        )).overrideWith((ref) async => _detail(regId: 2001, nickname: '阿明')),
        clubTeamDetailProvider((
          clubId: 1,
          topicId: 11,
        )).overrideWith((ref) async => _detail(regId: 3001, nickname: '小静')),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('带 topicId 进来 → 本主题的团默认展开,别家仍收起', (WidgetTester tester) async {
    final router = await _pump(tester, topicId: 11);
    expect(find.text('小静'), findsOneWidget, reason: 'focusTopicId 的团默认展开');
    expect(find.text('阿明'), findsNothing, reason: '未聚焦的团不该先展开');
    router.dispose();
  });

  testWidgets('不带 topicId(全俱乐部入口)→ 两团都收起,点开谁看谁', (WidgetTester tester) async {
    final router = await _pump(tester);
    expect(find.text('阿明'), findsNothing);
    expect(find.text('小静'), findsNothing);
    await tester.tap(find.text('静安第一期'));
    await tester.pumpAndSettle();
    expect(find.text('阿明'), findsOneWidget);
    router.dispose();
  });

  testWidgets('报名行头像 → 玩家公开主页;无 memberId 不给点', (WidgetTester tester) async {
    final router = await _pump(tester, topicId: 10);
    // regId 2001 → memberId 2051。
    await tester.tap(find.byKey(const Key('club-enroll-user-2001')));
    await tester.pumpAndSettle();
    expect(find.text('user-2051'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    // 历史报名拿不到 memberId:不给跳 /user/0 空主页的入口。
    expect(find.byKey(const Key('club-enroll-user-2002')), findsNothing);
    router.dispose();
  });
}
