// 模板详情的「套用」入口**真的渲染在页面上**。
//
// ★★ 这条测试是被一次真实的漏接逼出来的:2026-09-05 加「套用」时,
//   构造草稿的 _adopt 方法写好了、单测也绿了,但把按钮插进 widget 树的那一步
//   **没落进文件**。单测只测了 _adopt 的产物,测不出「页面上没有这个按钮」。
//   CI 的 `dart analyze lib test` 才抓到(报 _adopt 未被引用)。
//
//   ⇒ 只测「点了以后会怎样」的逻辑,测不出「压根点不到」。
//     入口类改动必须有一条断言「这个入口在屏幕上」。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/api/template_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/template/template_detail_page.dart';
import 'package:chengyin_app/feature/template/template_edit_page.dart';
import 'package:chengyin_app/feature/template/template_intro_page.dart';
import 'package:chengyin_app/main.dart';

class _FakeTemplateApi implements TemplateApi {
  _FakeTemplateApi(this.template);

  final PlayTemplate template;

  @override
  Future<PlayTemplate> info(int id) async => template;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

class _CategoryApi implements CategoryApi {
  @override
  Future<List<Category>> list({String? type}) async => const <Category>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpDetail(WidgetTester tester, PlayTemplate t) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        templateApiProvider.overrideWithValue(_FakeTemplateApi(t)),
      ],
      child: const MaterialApp(home: TemplateDetailPage(id: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

/// 游客态 + 真路由:套用这条路是**跨页**动作,只在裸 MaterialApp 里测不出
/// 「点完被守卫换成首页」这类事(那是 GoRouter redirect 干的)。
Future<void> _pumpGuestDetail(WidgetTester tester) async {
  final ProviderContainer container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(_GuestAuth.new),
      categoryApiProvider.overrideWithValue(_CategoryApi()),
      templateApiProvider.overrideWithValue(
        _FakeTemplateApi(
          const PlayTemplate(id: 1, title: '隐藏菜单', description: '到店说出暗号'),
        ),
      ),
      templateIntroCardsProvider.overrideWith((ref) async => const []),
    ].cast(),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  final GoRouter router = container.read(appRouterProvider);
  // 先落在公开页再 push:冷启动首页(动态流)会去打生产接口,与本用例无关。
  router.go('/legal/privacy');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  router.push('/template/1');
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('★★ 详情页必须有「套用」入口 —— 库里的东西看得见拿不走等于一本画册', (
    WidgetTester tester,
  ) async {
    await _pumpDetail(
      tester,
      const PlayTemplate(id: 1, title: '隐藏菜单', description: '到店说出暗号'),
    );

    expect(
      find.byKey(const Key('template-adopt')),
      findsOneWidget,
      reason: '套用按钮必须真的渲染在页面上,不是只有一个 _adopt 方法',
    );
    expect(find.text('套用这个玩法'), findsOneWidget);
  });

  testWidgets('形态标签跟着模板走,认不出的形态不显示标签', (WidgetTester tester) async {
    // 这里只断言页面能带着各种 packType 正常渲染 + 套用入口恒在 ——
    // 标签文案本身由 PlayTemplate.packTypeLabel 的单测钉住,不重复断言。
    for (final int packType in <int>[0, 1, 2, 9]) {
      await _pumpDetail(
        tester,
        PlayTemplate(id: 1, title: '某玩法', packType: packType),
      );
      expect(
        find.byKey(const Key('template-adopt')),
        findsOneWidget,
        reason: 'packType=$packType 时套用入口同样要在',
      );
    }
  });

  // ★ 2026-09-18 模拟器实拍 t06→t07:游客点「套用这个玩法」**静默落在首页**,
  //   没有登录引导、没有提示、草稿一起丢。根因是 `_adopt` 直接 push
  //   `/template/edit`(整页需登录路由),守卫把整页换成首页。
  //   口径与「发布 FAB」一致:先弹登录,登完留在详情页继续。
  testWidgets('★ 游客点「套用这个玩法」先弹登录,不静默回首页', (WidgetTester tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await _pumpGuestDetail(tester);
    expect(
      find.byKey(const Key('template-adopt')),
      findsOneWidget,
      reason: '前置条件:详情页已经渲染出来了',
    );

    await tester.tap(find.byKey(const Key('template-adopt')));
    await tester.pumpAndSettle();

    expect(
      find.text('登录城瘾'),
      findsOneWidget,
      reason: '游客点套用必须弹登录弹窗,不能什么都不说就把人丢回首页',
    );
    expect(
      find.byType(TemplateDetailPage),
      findsOneWidget,
      reason: '弹窗期间留在详情页(回来还要继续套用)',
    );
    expect(
      find.byType(TemplateEditPage),
      findsNothing,
      reason: '没登录不该进编辑器',
    );
  });
}
