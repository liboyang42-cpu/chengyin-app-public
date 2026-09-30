import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_topic_template_remix.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this.value);

  final AuthState value;

  @override
  AuthState build() => value;
}

class _FakeSquareApi implements SquareApi {
  final List<int> topics = <int>[];
  Completer<int>? pending;
  Object? failure;

  @override
  Future<int> remixTopicTemplate(int topicId) async {
    topics.add(topicId);
    if (failure case final Object error) throw error;
    return pending?.future ?? 9302;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const SquarePost remixable = SquarePost(
  id: 7,
  memberId: 9,
  sportName: '梧桐城市定向',
  sportCover: 'https://img.test/cover.jpg',
  isTopicTemplate: true,
  sportTopicId: 9201,
);

AuthState _auth(bool loggedIn) => AuthState(
  initialized: true,
  user: loggedIn
      ? User(id: 1, nickname: '阿兰', avatar: '', role: 'player')
      : null,
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  required SquarePost post,
  required _FakeSquareApi api,
  bool loggedIn = true,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: SquareTopicTemplateRemix(post: post)),
      ),
      GoRoute(
        path: '/publish/pro',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('编辑 ${state.uri.queryParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_auth(loggedIn))),
        squareApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('缺少模板标记或 sportTopicId 时完全不显示', (WidgetTester tester) async {
    for (final SquarePost post in <SquarePost>[
      const SquarePost(id: 1, memberId: 2, sportTopicId: 9201),
      const SquarePost(id: 1, memberId: 2, isTopicTemplate: true),
    ]) {
      await _pump(tester, post: post, api: _FakeSquareApi());
      expect(
        find.byKey(const Key('square-topic-template-remix')),
        findsNothing,
      );
    }
  });

  testWidgets('登录后改编防重，只读服务端新 id 进既有编辑路由', (WidgetTester tester) async {
    final _FakeSquareApi api = _FakeSquareApi()..pending = Completer<int>();
    await _pump(tester, post: remixable, api: api);

    final Finder action = find.byKey(const Key('square-topic-template-remix'));
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.tap(action);
    await tester.pump();

    expect(api.topics, <int>[9201]);
    expect(find.text('正在创建副本…'), findsOneWidget);

    api.pending!.complete(9302);
    await tester.pumpAndSettle();
    expect(find.text('编辑 9302'), findsOneWidget);
  });

  testWidgets('未登录先打开登录门，不发改编请求', (WidgetTester tester) async {
    final _FakeSquareApi api = _FakeSquareApi();
    await _pump(tester, post: remixable, api: api, loggedIn: false);

    await tester.tap(find.byKey(const Key('square-topic-template-remix')));
    await tester.pumpAndSettle();

    expect(find.text('登录城瘾'), findsOneWidget);
    expect(api.topics, isEmpty);
  });

  testWidgets('改编失败显示后端原话且恢复可点', (WidgetTester tester) async {
    final _FakeSquareApi api = _FakeSquareApi()..failure = Exception('模板已停用');
    await _pump(tester, post: remixable, api: api);

    await tester.tap(find.byKey(const Key('square-topic-template-remix')));
    await tester.pump();

    expect(find.text('模板已停用'), findsOneWidget);
    expect(find.text('改编同款'), findsOneWidget);
    expect(api.topics, <int>[9201]);
  });

  testWidgets('200% 系统字号时改编卡片自适应纵向排版', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(() => _FixedAuth(_auth(true))),
          squareApiProvider.overrideWithValue(_FakeSquareApi()),
        ].cast(),
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: SizedBox(
                width: 343,
                child: SquareTopicTemplateRemix(post: remixable),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const Key('square-topic-template-remix')))
          .height,
      greaterThanOrEqualTo(44),
    );
  });
}
