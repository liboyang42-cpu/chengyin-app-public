import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';
import 'package:chengyin_app/feature/topic/topic_self_play_service.dart';

TopicDetail _topic({
  int? lifecycle,
  int? selfPlay,
  double? price,
  bool owner = false,
}) => TopicDetail.fromJson(<String, dynamic>{
  'id': 1,
  'name': '静安微旅行',
  'description': '沿着城市的隐秘线索往前走',
  'lifecycle': ?lifecycle,
  'selfPlay': ?selfPlay,
  'selfPlayPrice': ?price,
  if (owner) 'isOwner': 1,
  'chaptersList': <dynamic>[],
});

class _LoggedInAuth extends AuthController {
  _LoggedInAuth([this.role = 'player']);

  final String role;

  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 8, nickname: '测试玩家', avatar: '', role: role),
  );
}

class _FakeSelfPlayService implements TopicSelfPlayService {
  int? topicId;
  String? realName;
  String? phone;
  List<TopicActivityEntry> activityRows = <TopicActivityEntry>[];

  @override
  Future<List<TopicActivityEntry>> activities(int topicId) async =>
      activityRows;

  @override
  Future<RegistrationCreateResult> createPass({
    required int topicId,
    required String realName,
    required String phone,
    required String requestId,
  }) async {
    this.topicId = topicId;
    this.realName = realName;
    this.phone = phone;
    return const RegistrationCreateResult(registrationId: 66);
  }

  @override
  Future<Map<String, String>> payApp(int registrationId) async =>
      <String, String>{};
}

Future<GoRouter> _pump(
  WidgetTester tester,
  TopicDetail detail, {
  TopicSelfPlayService? selfPlayService,
  String role = 'player',
}) async {
  final router = GoRouter(
    initialLocation: '/topic/1',
    routes: <RouteBase>[
      GoRoute(
        path: '/topic/:id',
        builder: (_, _) => const TopicDetailPage(topicId: 1),
      ),
      GoRoute(
        path: '/topic/:id/pricing',
        builder: (_, _) => const Scaffold(body: Text('pricing-destination')),
      ),
      GoRoute(
        path: '/activities',
        builder: (_, _) => const Scaffold(body: Text('activities-destination')),
      ),
      GoRoute(
        path: '/activity/:id',
        builder: (_, state) =>
            Scaffold(body: Text('activity-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/tickets',
        builder: (_, _) => const Scaffold(body: Text('tickets-destination')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _LoggedInAuth(role)),
        if (selfPlayService != null)
          topicSelfPlayServiceProvider.overrideWithValue(selfPlayService),
        topicDetailProvider(1).overrideWith((ref) async => detail),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('定价中且本人主办 → 进主题定价页', (WidgetTester tester) async {
    final router = await _pump(tester, _topic(lifecycle: 2, owner: true));

    await tester.tap(find.text('定价中 · 未开售'));
    await tester.pumpAndSettle();

    expect(find.text('pricing-destination'), findsOneWidget);
    router.dispose();
  });

  testWidgets('随时开玩不能跳进泛化活动列表', (WidgetTester tester) async {
    final router = await _pump(tester, _topic(selfPlay: 1, price: 49));

    await tester.tap(find.text('¥49.00 随时开玩'));
    await tester.pumpAndSettle();

    expect(find.text('activities-destination'), findsNothing);
    expect(find.text('自玩通行证'), findsOneWidget);
    router.dispose();
  });

  testWidgets('商家不能购买自玩通行证', (WidgetTester tester) async {
    final router = await _pump(
      tester,
      _topic(selfPlay: 1, price: 49),
      role: 'merchant',
    );

    await tester.tap(find.text('¥49.00 随时开玩'));
    await tester.pumpAndSettle();

    expect(find.text('自玩通行证'), findsNothing);
    expect(find.text('商家用户不可购买'), findsOneWidget);
    router.dispose();
  });

  testWidgets('自玩通行证建单成功 → 去票夹', (WidgetTester tester) async {
    final service = _FakeSelfPlayService();
    final router = await _pump(
      tester,
      _topic(selfPlay: 1, price: 0),
      selfPlayService: service,
    );

    await tester.tap(find.text('随时开玩'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('self-play-real-name')), '陈晨');
    await tester.enterText(
      find.byKey(const Key('self-play-phone')),
      '13800000000',
    );
    await tester.tap(find.textContaining('我同意将姓名与手机号用于'));
    await tester.pump();
    await tester.tap(find.widgetWithText(CupertinoButton, '确认购买'));
    await tester.pumpAndSettle();

    expect(service.topicId, 1);
    expect(service.realName, '陈晨');
    expect(service.phone, '13800000000');
    await tester.tap(find.text('查看票夹'));
    await tester.pumpAndSettle();
    expect(find.text('tickets-destination'), findsOneWidget);
    router.dispose();
  });

  testWidgets('查看场次仅有一场 → 直达该活动详情', (WidgetTester tester) async {
    final service = _FakeSelfPlayService()
      ..activityRows = const <TopicActivityEntry>[
        TopicActivityEntry(id: 77, name: '静安夜行场'),
      ];
    final router = await _pump(
      tester,
      _topic(selfPlay: 1, price: 49),
      selfPlayService: service,
    );

    await tester.tap(find.text('查看场次'));
    await tester.pumpAndSettle();

    expect(find.text('activity-77'), findsOneWidget);
    expect(find.text('activities-destination'), findsNothing);
    router.dispose();
  });
}
