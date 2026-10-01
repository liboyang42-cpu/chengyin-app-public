import 'package:chengyin_app/core/widgets/cy_confirm.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/feature/club/club_member_actions.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/source_text.dart';

class _ConfirmPresenter implements CyNativeConfirmPresenter {
  CyNativeConfirmRequest? request;

  @override
  Future<CyNativeConfirmResult> show(
    BuildContext context,
    CyNativeConfirmRequest request,
  ) async {
    this.request = request;
    return CyNativeConfirmResult.cancelled;
  }
}

ClubMember _member({int id = 7, int role = 0, bool owner = false}) =>
    ClubMember.fromJson(<String, dynamic>{
      'memberId': id,
      'nickname': '小李',
      'role': role,
      if (owner) 'isOwner': true,
    });

Future<void> _pumpAction(
  WidgetTester tester, {
  required ClubMember member,
  bool viewerIsCreator = true,
  bool canGovernMembers = false,
  CyNativeConfirmPresenter? confirmPresenter,
  Locale locale = const Locale('zh'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: ClubMemberActions(
            clubId: 3,
            member: member,
            viewerIsCreator: viewerIsCreator,
            canGovernMembers: canGovernMembers,
            confirmPresenter: confirmPresenter,
          ),
        ),
      ),
    ),
  );
}

/// 带路由的一版:「临时封禁」是导航入口,要能看见它 push 的 URL。
Future<void> _pumpActionRouted(
  WidgetTester tester, {
  required ClubMember member,
  bool viewerIsCreator = true,
  bool canGovernMembers = false,
}) async {
  final router = GoRouter(
    initialLocation: '/host',
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (_, _) => Scaffold(
          body: Center(
            child: ClubMemberActions(
              clubId: 3,
              member: member,
              viewerIsCreator: viewerIsCreator,
              canGovernMembers: canGovernMembers,
            ),
          ),
        ),
      ),
      // 回显 memberId,钉「入口带了人」。
      GoRoute(
        path: '/club/:id/governance',
        builder: (_, state) => Scaffold(
          body: Text('governance-${state.uri.queryParameters['memberId']}'),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp.router(routerConfig: router)),
  );
}

void main() {
  testWidgets('English member actions wrap at large text and retain confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final confirm = _ConfirmPresenter();
    await _pumpAction(
      tester, member: _member(role: 1), canGovernMembers: true,
      confirmPresenter: confirm, locale: const Locale('en'), textScale: 1.8,
    );
    await tester.pumpAndSettle();
    expect(find.text('Remove admin role'), findsOneWidget);
    expect(find.text('Temporary ban'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('member-role-7')));
    await tester.pumpAndSettle();
    expect(confirm.request?.title, 'Remove administrator role');
    expect(confirm.request?.content, contains('no longer be able'));
    expect(tester.takeException(), isNull);
  });

  test('成员行不得把两个源入口折叠成 ellipsis 菜单', () {
    final String code = codeOf('lib/feature/club/club_member_actions.dart');
    expect(code.contains('CupertinoIcons.ellipsis'), isFalse);
    expect(code.contains('LiquidGlassAlertStyle.actionSheet'), isFalse);
  });

  testWidgets('创建者直接看到“设管理/移除”两个 44pt 入口', (WidgetTester tester) async {
    await _pumpAction(tester, member: _member());

    final Finder role = find.byKey(const Key('member-role-7'));
    final Finder remove = find.byKey(const Key('member-remove-7'));
    expect(role, findsOneWidget);
    expect(remove, findsOneWidget);
    expect(find.text('设管理'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
    expect(tester.getSize(role).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('设管理'), findsOneWidget);
    expect(find.bySemanticsLabel('移除'), findsOneWidget);
  });

  testWidgets('管理员行的直接入口文案是小程序“取消管理”', (WidgetTester tester) async {
    await _pumpAction(tester, member: _member(role: 1));
    expect(find.text('取消管理'), findsOneWidget);
    expect(find.byKey(const Key('member-role-7')), findsOneWidget);
  });

  testWidgets('设管理直接进原生确认，不多一层菜单', (WidgetTester tester) async {
    final _ConfirmPresenter confirm = _ConfirmPresenter();
    await _pumpAction(tester, member: _member(), confirmPresenter: confirm);

    await tester.tap(find.byKey(const Key('member-role-7')));
    await tester.pumpAndSettle();

    expect(confirm.request?.title, '设为管理员');
    expect(confirm.request?.content, '管理员可协助删除违规内容、现场出示团码。确认设置？');
    expect(confirm.request?.confirmText, '确定');
  });

  testWidgets('移除直接进破坏性原生确认', (WidgetTester tester) async {
    final _ConfirmPresenter confirm = _ConfirmPresenter();
    await _pumpAction(tester, member: _member(), confirmPresenter: confirm);

    await tester.tap(find.byKey(const Key('member-remove-7')));
    await tester.pumpAndSettle();

    expect(confirm.request?.title, '移除成员');
    expect(confirm.request?.content, '确定将该成员移出俱乐部?');
    expect(confirm.request?.danger, isTrue);
  });

  testWidgets('临时封禁:没给治理权就不出现;给了才出现', (WidgetTester tester) async {
    await _pumpAction(tester, member: _member());
    expect(find.byKey(const Key('member-governance-7')), findsNothing);

    await _pumpAction(tester, member: _member(), canGovernMembers: true);
    expect(find.text('临时封禁'), findsOneWidget);

    // 创建者本人不能被临时封(js:2080 拿 club.memberId 比对)。
    await _pumpAction(
      tester,
      member: _member(owner: true),
      canGovernMembers: true,
    );
    expect(find.byKey(const Key('member-governance-7')), findsNothing);
  });

  testWidgets('临时封禁点下去 → 治理页带 memberId', (WidgetTester tester) async {
    await _pumpActionRouted(tester, member: _member(), canGovernMembers: true);
    await tester.tap(find.byKey(const Key('member-governance-7')));
    await tester.pumpAndSettle();
    expect(find.text('governance-7'), findsOneWidget);
  });

  testWidgets('非创建者与创建者本人都不出现管理入口', (WidgetTester tester) async {
    await _pumpAction(tester, member: _member(), viewerIsCreator: false);
    expect(find.byKey(const Key('member-role-7')), findsNothing);
    expect(find.byKey(const Key('member-remove-7')), findsNothing);

    await _pumpAction(tester, member: _member(owner: true));
    expect(find.byKey(const Key('member-role-7')), findsNothing);
    expect(find.byKey(const Key('member-remove-7')), findsNothing);
  });
}
