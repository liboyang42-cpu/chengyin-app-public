// 创作者中心:四态各说各的 + 不给一张按下去必失败的表单。

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/widgets/status_view.dart';
import 'package:chengyin_app/data/models/creator_center.dart';
import 'package:chengyin_app/feature/creator/creator_center_page.dart';
import 'package:chengyin_app/feature/creator/creator_controller.dart';

Future<void> _pump(WidgetTester t, CreatorCenter c) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        creatorCenterProvider.overrideWith((Ref ref) async => c),
      ].cast(),
      child: const MaterialApp(home: CreatorCenterPage()),
    ),
  );
  await t.pumpAndSettle();
}

/// 路由版:验页面里的入口真的跳得动(`context.push` 需要真 GoRouter)。
({Widget app, GoRouter router}) _routed(CreatorCenter c) {
  final GoRouter router = GoRouter(
    initialLocation: '/creator',
    routes: <RouteBase>[
      GoRoute(path: '/creator', builder: (_, _) => const CreatorCenterPage()),
      GoRoute(
        path: '/income',
        builder: (_, _) =>
            const Scaffold(key: Key('route-income'), body: Text('收益明细')),
      ),
    ],
  );
  return (
    app: ProviderScope(
      overrides: <dynamic>[
        creatorCenterProvider.overrideWith((Ref ref) async => c),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
    router: router,
  );
}

void main() {
  group('★★ 后端对已有档案一律拒收 ⇒ 被驳回的人按不下去', () {
    test('canReallyApply 只放 not_applied,不放 rejected', () {
      expect(canReallyApply(CreatorApplyStatus.notApplied), isTrue);
      expect(
        canReallyApply(CreatorApplyStatus.rejected),
        isFalse,
        reason:
            'CreatorCenterServiceImpl.apply 开头 '
            '`if (selectByMemberId != null) return 0;` —— 重申请必然失败。'
            '给一张必然失败的表单 = 假保证,本项目最高频的那类问题',
      );
      expect(canReallyApply(CreatorApplyStatus.pending), isFalse);
      expect(canReallyApply(CreatorApplyStatus.approved), isFalse);
    });

    test('★ 与模型的 canApply 有意不一致 —— 那个是「业务上该不该」', () {
      const CreatorCenter c = CreatorCenter(
        status: CreatorApplyStatus.rejected,
      );
      expect(c.canApply, isTrue, reason: '业务语义上驳回后是可以再申请的');
      expect(canReallyApply(c.status), isFalse, reason: '但后端现在收不收是另一回事,以后者为准');
    });

    testWidgets('驳回态:说原因 + 说明按不下去,且不渲染表单', (WidgetTester t) async {
      await _pump(
        t,
        const CreatorCenter(
          status: CreatorApplyStatus.rejected,
          rejectReason: '资料不完整',
        ),
      );
      expect(find.textContaining('资料不完整'), findsOneWidget);
      expect(find.byKey(const Key('creator-reapply-blocked')), findsOneWidget);
      expect(find.byKey(const Key('creator-submit')), findsNothing);
    });

    testWidgets('★ 驳回但后端没给原因 ⇒ 说「未说明原因」,不留空', (WidgetTester t) async {
      await _pump(t, const CreatorCenter(status: CreatorApplyStatus.rejected));
      expect(
        find.textContaining('未说明原因'),
        findsOneWidget,
        reason: '空着用户不知道该改什么',
      );
    });
  });

  testWidgets('未申请:给表单', (WidgetTester t) async {
    await _pump(t, const CreatorCenter(status: CreatorApplyStatus.notApplied));
    expect(find.byKey(const Key('creator-submit')), findsOneWidget);
    expect(find.text('未申请'), findsOneWidget);
  });

  testWidgets('审核中:不给表单,说清在等什么', (WidgetTester t) async {
    await _pump(t, const CreatorCenter(status: CreatorApplyStatus.pending));
    expect(find.byKey(const Key('creator-submit')), findsNothing);
    expect(find.text('审核中'), findsOneWidget);
  });

  testWidgets('★★ 数据概览缺值显示「—」,不兜 0', (WidgetTester t) async {
    // 「今天还没统计」和「一次都没被看过」不是一回事。
    await _pump(t, const CreatorCenter(status: CreatorApplyStatus.approved));
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('有统计就照实显示', (WidgetTester t) async {
    await _pump(
      t,
      const CreatorCenter(
        status: CreatorApplyStatus.approved,
        metric: CreatorMetric(contentCount: 12, viewCount: 3400, likeCount: 0),
      ),
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3400'), findsOneWidget);
    // 真的是 0 就显示 0 —— 和「拿不到」区分开。
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('★ 收益金额原样透出,拿不到给「—」不给 ¥0.00', (WidgetTester t) async {
    await _pump(
      t,
      const CreatorCenter(
        status: CreatorApplyStatus.approved,
        recentIncome: <CreatorIncomeRow>[
          CreatorIncomeRow(source: '主题分润', amount: '128.00'),
          CreatorIncomeRow(source: '拿不到金额那条'),
        ],
      ),
    );
    expect(find.text('128.00'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing);
  });

  testWidgets('加载态是骨架屏(真源 cy-skeleton type=card count=3),不是转圈', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          creatorCenterProvider.overrideWith(
            (Ref ref) async =>
                const CreatorCenter(status: CreatorApplyStatus.approved),
          ),
        ].cast(),
        child: const MaterialApp(home: CreatorCenterPage()),
      ),
    );
    // 只 pump 一帧:provider 还没回来 = 加载态。
    expect(find.byType(CySkeleton), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(StatusView), findsNothing);
    await t.pumpAndSettle();
    expect(find.byType(CySkeleton), findsNothing);
  });

  testWidgets('★★ 承载层异常不把英文原文画在屏幕上', (WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          creatorCenterProvider.overrideWith((Ref ref) async {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/creator/center'),
              type: DioExceptionType.connectionError,
            );
          }),
        ].cast(),
        child: const MaterialApp(home: CreatorCenterPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('创作者中心没能加载出来'), findsOneWidget);
    expect(find.text('网络不稳定，请检查连接后重试'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('connection error'), findsNothing);
  });

  testWidgets('业务拒绝照原话透出 —— 后端 msg 是给用户看的', (WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          creatorCenterProvider.overrideWith((Ref ref) async {
            throw Exception('创作者档案不存在');
          }),
        ].cast(),
        child: const MaterialApp(home: CreatorCenterPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('创作者档案不存在'), findsOneWidget);
  });

  testWidgets('★ 近期收益的「查看全部」跳收益明细(真源 goIncomeAll)', (WidgetTester t) async {
    final routed = _routed(
      const CreatorCenter(
        status: CreatorApplyStatus.approved,
        recentIncome: <CreatorIncomeRow>[CreatorIncomeRow(source: '主题分润')],
      ),
    );
    addTearDown(routed.router.dispose);
    await t.pumpWidget(routed.app);
    await t.pumpAndSettle();

    expect(
      find.byKey(const Key('creator-income-all')),
      findsOneWidget,
      reason: '真源 index.wxml 有这条入口,App 此前漏了 —— 收益明细从这页走不到',
    );
    await t.tap(find.byKey(const Key('creator-income-all')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('route-income')), findsOneWidget);
  });
}
