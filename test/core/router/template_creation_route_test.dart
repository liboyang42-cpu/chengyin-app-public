import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/data/api/category_api.dart';
import 'package:chengyin_app/data/models/category.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/legal/legal_doc_page.dart';
import 'package:chengyin_app/feature/template/template_edit_page.dart';
import 'package:chengyin_app/feature/template/template_intro_page.dart';
import 'package:chengyin_app/feature/template/template_name_page.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 7, nickname: '测试玩家', avatar: '', role: 'player'),
    initialized: true,
  );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('默认新建落在独立命名页，不直接进编辑器', (WidgetTester tester) async {
    final _Harness harness = await _pumpApp(tester);

    harness.router.push('/template/new');
    await _pumpRoute(tester);

    expect(find.byType(TemplateNamePage), findsOneWidget);
    expect(
      _stateOf(tester, find.byType(TemplateNamePage)).matchedLocation,
      '/template/new',
    );
    expect(find.byType(TemplateEditPage), findsNothing);
    expect(find.text('给节点玩法起个名字'), findsOneWidget);
    expect(
      tester
          .widget<CyNativeButton>(
            find.byKey(const Key('template-name-confirm')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('template-name-field')), '   ');
    await tester.pump();
    expect(
      tester
          .widget<CyNativeButton>(
            find.byKey(const Key('template-name-confirm')),
          )
          .onPressed,
      isNull,
      reason: '小程序 templateadd 只在 trim 后非空时允许确认',
    );
    expect(
      ModalRoute.of(tester.element(find.byType(TemplateNamePage)))?.settings,
      isA<CupertinoPage<void>>(),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'intro → 命名 → 编辑器都替换当前页，编辑器返回原调用页',
    (WidgetTester tester) async {
      final _Harness harness = await _pumpApp(tester);

      final Future<Object?> flowResult = harness.router.push('/template/intro');
      bool flowCompleted = false;
      Object? flowValue = Object();
      unawaited(
        flowResult.then((Object? value) {
          flowCompleted = true;
          flowValue = value;
        }),
      );
      await _pumpRoute(tester);
      expect(find.byType(TemplateIntroPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('template-intro-create')));
      await _pumpRoute(tester);
      expect(find.byType(TemplateIntroPage), findsNothing);
      expect(find.byType(TemplateNamePage), findsOneWidget);
      expect(
        _stateOf(tester, find.byType(TemplateNamePage)).matchedLocation,
        '/template/new',
      );

      await tester.enterText(
        find.byKey(const Key('template-name-field')),
        ' 夜游苏河 ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('template-name-confirm')));
      await _pumpRoute(tester);

      final GoRouterState editState = _stateOf(
        tester,
        find.byType(TemplateEditPage),
      );
      expect(editState.matchedLocation, '/template/edit');
      expect(editState.uri.queryParameters, <String, String>{
        'templateName': ' 夜游苏河 ',
      });
      expect(find.byType(TemplateNamePage), findsNothing);
      expect(find.byType(TemplateEditPage), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(TemplateEditPage)))?.settings,
        isA<CupertinoPage<void>>(),
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.descendant(
                of: find.byKey(const Key('template-field-title')),
                matching: find.byType(CupertinoTextField),
              ),
            )
            .controller
            ?.text,
        ' 夜游苏河 ',
      );

      await _edgeSwipeBack(tester, find.byType(TemplateEditPage));

      expect(harness.location, '/legal/privacy');
      expect(find.byType(LegalDocPage), findsOneWidget);
      expect(find.byType(TemplateIntroPage), findsNothing);
      expect(find.byType(TemplateNamePage), findsNothing);
      expect(
        flowCompleted,
        isTrue,
        reason: '两次 replace 后返回仍必须完成原调用方的 push Future',
      );
      expect(flowValue, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  // ★ 2026-09-18 模拟器实拍 t12→t13:游客在引导页点「开始创建」**静默落回首页**,
  //   创建流程第 0 步就断。根因:出口 replace 到 `/template/new`,那是整页需登录
  //   路由,守卫不弹登录、直接把整页换成首页。
  //   口径与「发布 FAB」一致:先弹登录弹窗,登完留在本页继续。
  testWidgets(
    '游客点「开始创建」先弹登录,不静默回首页',
    (WidgetTester tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final _Harness harness = await _pumpApp(tester, loggedIn: false);

      harness.router.push('/template/intro');
      await _pumpRoute(tester);
      expect(find.byType(TemplateIntroPage), findsOneWidget);

      // 测试 binding 对未注册插件不会抛 MissingPluginException(通道会挂起),
      // 显式 mock「iOS 上插件未注册/不支持」,走 showCyNativeSheet 的真回退分支
      // (判据同 test/widgets/cy_native_sheet_test.dart;#213 起登录门经此)。
      const MethodChannel sheetChannel = MethodChannel(
        'native_liquid_glass/native_flutter_sheet',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sheetChannel, (MethodCall call) async {
            throw MissingPluginException();
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sheetChannel, null),
      );

      await tester.tap(find.byKey(const Key('template-intro-create')));
      await tester.pumpAndSettle();

      expect(
        find.text('登录城瘾'),
        findsOneWidget,
        reason: '游客点创建必须弹登录弹窗,不能什么都不说就把人丢回首页',
      );
      expect(
        find.byType(TemplateIntroPage),
        findsOneWidget,
        reason: '弹窗期间留在引导页(登录完还要继续创建)',
      );
      expect(find.byType(TemplateNamePage), findsNothing, reason: '没登录不该进命名页');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Future<_Harness> _pumpApp(WidgetTester tester, {bool loggedIn = true}) async {
  final ProviderContainer container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(
        loggedIn ? _FixedAuth.new : _GuestAuth.new,
      ),
      categoryApiProvider.overrideWithValue(_CategoryApi()),
      templateIntroCardsProvider.overrideWith((ref) async => const []),
    ].cast(),
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ChengyinApp()),
  );
  await _pumpRoute(tester);

  final GoRouter router = container.read(appRouterProvider);
  router.go('/legal/privacy');
  await _pumpRoute(tester);
  return _Harness(router);
}

Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

GoRouterState _stateOf(WidgetTester tester, Finder page) =>
    GoRouterState.of(tester.element(page));

Future<void> _edgeSwipeBack(WidgetTester tester, Finder activePage) async {
  final ModalRoute<dynamic>? route = ModalRoute.of(tester.element(activePage));
  expect((route! as PageRoute<dynamic>).popGestureEnabled, isTrue);

  final TestGesture gesture = await tester.startGesture(const Offset(5, 300));
  await gesture.moveBy(const Offset(20, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(500, 0));
  await tester.pump();
  await gesture.up();
  await _pumpRoute(tester);
}

class _Harness {
  const _Harness(this.router);

  final GoRouter router;

  String get location => router.routeInformationProvider.value.uri.path;
}
