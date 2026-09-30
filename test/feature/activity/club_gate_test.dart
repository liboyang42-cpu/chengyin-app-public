// gap-spec-player #5:俱乐部门禁 gate。非成员访问 /api/activity/info 拿到的
// 不是详情而是 `gate=true` + clubId + message,这不是加载失败(重试无意义),
// 唯一出口是去加入俱乐部;拿不到 clubId 时退回活动列表,不给无目的按钮。
//
// 真源 components/cy/scene-play-activity-detail/index.js:182-190(gate 终态)、
//     :503-509(goGateClub),index.wxml:7(cta 文案二选一)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/activity/activity_controller.dart';
import 'package:chengyin_app/feature/activity/activity_detail_page.dart';

ActivityDetail _from(Map<String, dynamic> json) =>
    ActivityDetail.fromJson(json);

void main() {
  group('模型契约', () {
    test('gate=true → 清空详情,只留 clubId/message', () {
      final d = _from(<String, dynamic>{
        'gate': true,
        'clubId': '88',
        'message': '这家俱乐部的私密活动',
        // 门禁响应里后端不下发这些;即便误带也应被忽略。
        'id': 5,
        'name': '不该出现',
        'omsTicketList': <dynamic>[
          <String, dynamic>{'id': 1},
        ],
      });
      expect(d.isGate, isTrue);
      expect(d.gateClubId, 88, reason: '字符串 clubId 也要认');
      expect(d.gateMessage, '这家俱乐部的私密活动');
      expect(d.id, 0);
      expect(d.name, isEmpty);
      expect(d.tickets, isEmpty);
    });

    test('gate 缺 message → 用固定话术;缺 clubId → 0', () {
      final d = _from(<String, dynamic>{'gate': true});
      expect(d.isGate, isTrue);
      expect(d.gateClubId, 0);
      expect(d.gateMessage, '来自俱乐部的活动，加入后查看');
    });

    test('非 gate 响应照常解析', () {
      final d = _from(<String, dynamic>{'id': 5, 'name': '夜行外滩'});
      expect(d.isGate, isFalse);
      expect(d.id, 5);
      expect(d.name, '夜行外滩');
    });
  });

  group('门禁态渲染', () {
    Future<void> pump(
      WidgetTester tester,
      ActivityDetail d, {
      List<String>? landed,
    }) async {
      final router = GoRouter(
        initialLocation: '/activity/7',
        routes: <RouteBase>[
          GoRoute(
            path: '/activity/:id',
            builder: (_, _) => const ActivityDetailPage(activityId: 7),
          ),
          GoRoute(
            path: '/club/:id',
            builder: (_, state) {
              landed?.add('/club/${state.pathParameters['id']}');
              return const Scaffold(body: Text('俱乐部'));
            },
          ),
          GoRoute(
            path: '/activities',
            builder: (_, _) {
              landed?.add('/activities');
              return const Scaffold(body: Text('活动列表'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            activityDetailProvider(7).overrideWith((ref) async => d),
          ].cast(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('有 clubId → CTA「去加入俱乐部」,点击跳 /club/:id', (tester) async {
      final landed = <String>[];
      await pump(
        tester,
        _from(<String, dynamic>{
          'gate': true,
          'clubId': 88,
          'message': '会员限定活动',
        }),
        landed: landed,
      );
      expect(find.text('会员限定活动'), findsOneWidget);
      expect(find.text('加入俱乐部后即可查看活动详情与票种'), findsOneWidget);
      expect(find.text('去加入俱乐部'), findsOneWidget);
      expect(find.text('返回活动列表'), findsNothing);
      await tester.tap(find.text('去加入俱乐部'));
      await tester.pumpAndSettle();
      expect(landed, <String>['/club/88']);
    });

    testWidgets('无 clubId → CTA「返回活动列表」,不给人家俱乐部页', (tester) async {
      await pump(tester, _from(<String, dynamic>{'gate': true}));
      expect(find.text('去加入俱乐部'), findsNothing);
      expect(find.text('返回活动列表'), findsOneWidget);
    });
  });
}
