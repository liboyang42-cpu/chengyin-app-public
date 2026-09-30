import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

void main() {
  MyProject project({
    required int id,
    required String bizType,
    required String title,
    required String state,
    String ownerType = 'member',
    String? acceptStatus,
  }) {
    return MyProject.fromJson(<String, dynamic>{
      'id': id,
      'bizType': bizType,
      'title': title,
      'state': state,
      'stateText': state,
      'ownerType': ownerType,
      'acceptStatus': acceptStatus,
    });
  }

  Widget app({
    required List<MyProject> projects,
    List<PlayTemplate> templates = const <PlayTemplate>[],
    bool liquidGlassSupported = false,
  }) {
    final router = GoRouter(
      initialLocation: '/my-projects',
      routes: <RouteBase>[
        GoRoute(
          path: '/my-projects',
          builder: (_, _) =>
              MyProjectsPage(liquidGlassSupported: liquidGlassSupported),
        ),
        for (final path in <String>[
          '/publish/pro',
          '/project/home/:id',
          '/activity/:id',
          '/coop/candidates/:id',
          '/template/:id',
        ])
          GoRoute(
            path: path,
            builder: (_, state) => Text(
              'ROUTE ${state.uri.path}?${state.uri.query}',
              textDirection: TextDirection.ltr,
            ),
          ),
      ],
    );
    return ProviderScope(
      overrides: [
        myProjectsProvider.overrideWith((_) async => projects),
        myProjectTemplatesProvider.overrideWith((_) async => templates),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('我的项目以主题/活动/模板三类为主结构', (tester) async {
    await tester.pumpWidget(
      app(
        projects: <MyProject>[
          project(id: 1, bizType: 'topic', title: '路线草稿', state: 'draft'),
          project(id: 2, bizType: 'activity', title: '夜游场次', state: 'running'),
        ],
        templates: const <PlayTemplate>[
          PlayTemplate(id: 3, title: '街头问答', publishStatus: 1, useNum: 8),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的项目'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('活动'), findsOneWidget);
    expect(find.text('模板'), findsOneWidget);
    expect(find.text('路线草稿'), findsOneWidget);
    expect(find.text('夜游场次'), findsNothing);

    await tester.tap(find.text('活动'));
    await tester.pumpAndSettle();
    expect(find.text('夜游场次'), findsOneWidget);
    expect(find.text('路线草稿'), findsNothing);

    await tester.tap(find.text('模板'));
    await tester.pumpAndSettle();
    expect(find.text('街头问答'), findsOneWidget);
    expect(find.text('8 次引用'), findsOneWidget);
  });

  testWidgets('多身份时显示身份筛选，待处理按未通过/草稿/审核中置顶', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        projects: <MyProject>[
          project(
            id: 1,
            bizType: 'topic',
            title: '审核中',
            state: 'pending',
            ownerType: 'club',
          ),
          project(id: 2, bizType: 'topic', title: '未通过', state: 'rejected'),
          project(id: 3, bizType: 'topic', title: '草稿', state: 'draft'),
          project(id: 4, bizType: 'topic', title: '进行中', state: 'running'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('个人'), findsOneWidget);
    expect(find.text('俱乐部'), findsWidgets);
    expect(find.text('待处理 3'), findsOneWidget);

    final rejectedY = tester
        .getTopLeft(find.byKey(const Key('project-card-2')))
        .dy;
    final draftY = tester
        .getTopLeft(find.byKey(const Key('project-card-3')))
        .dy;
    final pendingY = tester
        .getTopLeft(find.byKey(const Key('project-card-1')))
        .dy;
    expect(rejectedY, lessThan(draftY));
    expect(draftY, lessThan(pendingY));

    await tester.tap(find.text('全部状态'));
    await tester.pumpAndSettle();
    expect(find.text('选择项目状态'), findsOneWidget);
    expect(find.text('已下架'), findsOneWidget);
  });

  testWidgets('iOS 26 状态筛选使用原生 UIMenu 并保持原筛选目标', (tester) async {
    await tester.pumpWidget(
      app(
        liquidGlassSupported: true,
        projects: <MyProject>[
          project(id: 1, bizType: 'topic', title: '路线草稿', state: 'draft'),
          project(id: 2, bizType: 'topic', title: '进行中的路线', state: 'running'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final LiquidGlassMenu menu = tester.widget<LiquidGlassMenu>(
      find.byType(LiquidGlassMenu),
    );
    expect(menu.key, const ValueKey<String>('project-state-filter-all'));
    expect(menu.menuTitle, '选择项目状态');
    expect(menu.items.map((LiquidGlassMenuItem item) => item.title), <String>[
      '全部状态',
      '草稿',
      '审核中',
      '未开始',
      '进行中',
      '已完成',
      '已下架',
      '未通过',
    ]);

    menu.onItemSelected('draft');
    await tester.pump();

    expect(find.text('路线草稿'), findsOneWidget);
    expect(find.text('进行中的路线'), findsNothing);
    expect(
      tester.widget<LiquidGlassMenu>(find.byType(LiquidGlassMenu)).label,
      '草稿',
    );
    expect(
      tester.widget<LiquidGlassMenu>(find.byType(LiquidGlassMenu)).key,
      const ValueKey<String>('project-state-filter-draft'),
    );
  });

  testWidgets('草稿续编、主办视图与候选池保持小程序落点', (tester) async {
    await tester.pumpWidget(
      app(
        projects: <MyProject>[
          project(id: 11, bizType: 'topic', title: '草稿 A', state: 'draft'),
          project(
            id: 12,
            bizType: 'topic',
            title: '主办 B',
            state: 'running',
            acceptStatus: 'clubOpen',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('草稿 A'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE /publish/pro?id=11'), findsOneWidget);

    await tester.pumpWidget(
      app(
        projects: <MyProject>[
          project(id: 11, bizType: 'topic', title: '草稿 A', state: 'draft'),
          project(
            id: 12,
            bizType: 'topic',
            title: '主办 B',
            state: 'running',
            acceptStatus: 'clubOpen',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('主办 B'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE /project/home/12?'), findsOneWidget);

    await tester.pumpWidget(
      app(
        projects: <MyProject>[
          project(
            id: 12,
            bizType: 'topic',
            title: '主办 B',
            state: 'running',
            acceptStatus: 'clubOpen',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('候选池'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE /coop/candidates/12?'), findsOneWidget);
  });
}
