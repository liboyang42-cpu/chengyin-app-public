import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 1, nickname: '我', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _FakeClubApi implements ClubApi {
  _FakeClubApi({this.error});
  final Object? error;
  int updateCalls = 0;
  final List<String> updateRequestIds = <String>[];

  @override
  Future<String> updatePost({
    required int postId,
    required String content,
    required List<String> images,
    required int version,
    required String requestId,
  }) async {
    updateCalls++;
    updateRequestIds.add(requestId);
    if (error != null) throw error!;
    return '已更新';
  }

  @override
  Future<List<ClubPostRevision>> postHistory(int postId) async {
    if (error != null) throw error!;
    return const <ClubPostRevision>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required ClubPost post,
  required _FakeClubApi api,
  bool admin = false,
  Locale locale = const Locale('zh'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_FixedAuth.new),
        clubApiProvider.overrideWithValue(api),
      ].cast(),
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: ClubPostTile(post: post, viewerIsClubAdmin: admin),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('English post editor keeps backend rejection verbatim', (tester) async {
    final api = _FakeClubApi(error: Exception('版本冲突，请刷新'));
    await _pump(tester, api: api,
      post: const ClubPost(id: 7, authorMemberId: 1, content: '原始正文', version: 3),
      locale: const Locale('en'));
    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-post-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Edit post'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('club-post-edit-input')), '新的原文');
    await tester.tap(find.byKey(const Key('club-post-edit-submit')));
    await tester.pumpAndSettle();
    expect(find.text('版本冲突，请刷新'), findsOneWidget);
    expect(api.updateCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('作者能编辑但不能置顶普通帖，所有人都有公开历史入口', (tester) async {
    await _pump(
      tester,
      api: _FakeClubApi(),
      post: const ClubPost(id: 7, authorMemberId: 1, content: '正文', version: 2),
    );

    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('club-post-edit')), findsOneWidget);
    expect(find.byKey(const Key('club-post-pin')), findsNothing);
    expect(find.byKey(const Key('club-post-history')), findsOneWidget);
  });

  testWidgets('管理员只能对公告获得编辑与置顶入口', (tester) async {
    await _pump(
      tester,
      api: _FakeClubApi(),
      admin: true,
      post: const ClubPost(
        id: 7,
        authorMemberId: 2,
        content: '公告',
        type: 2,
        version: 1,
      ),
    );

    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('club-post-edit')), findsOneWidget);
    expect(find.byKey(const Key('club-post-pin')), findsOneWidget);
    expect(find.text('举报帖文'), findsOneWidget);
  });

  testWidgets('公告原作者失去管理权限后不再显示编辑入口', (tester) async {
    await _pump(
      tester,
      api: _FakeClubApi(),
      post: const ClubPost(id: 7, authorMemberId: 1, content: '公告', type: 2),
    );

    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('club-post-edit')), findsNothing);
    expect(find.byKey(const Key('club-post-pin')), findsNothing);
  });

  testWidgets('历史为空有明确状态', (tester) async {
    await _pump(
      tester,
      api: _FakeClubApi(),
      post: const ClubPost(id: 7, authorMemberId: 2, content: '正文'),
    );
    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-post-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('club-post-history-empty')), findsOneWidget);
  });

  testWidgets('历史加载失败保留原因和重试入口', (tester) async {
    await _pump(
      tester,
      api: _FakeClubApi(error: Exception('历史服务暂不可用')),
      post: const ClubPost(id: 7, authorMemberId: 2, content: '正文'),
    );
    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-post-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('club-post-history-error')), findsOneWidget);
    expect(find.text('历史服务暂不可用'), findsOneWidget);
  });

  testWidgets('编辑失败留在编辑器并展示后端原因', (tester) async {
    final _FakeClubApi api = _FakeClubApi(error: Exception('版本冲突，请刷新'));
    await _pump(
      tester,
      api: api,
      post: const ClubPost(
        id: 7,
        authorMemberId: 1,
        content: '旧正文',
        version: 3,
      ),
    );
    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-post-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('club-post-edit-input')),
      '新正文',
    );
    await tester.tap(find.byKey(const Key('club-post-edit-submit')));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 1);
    expect(find.byKey(const Key('club-post-edit-error')), findsOneWidget);
    expect(find.text('版本冲突，请刷新'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('club-post-edit-input')),
      '又一版正文',
    );
    await tester.tap(find.byKey(const Key('club-post-edit-submit')));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 2);
    expect(
      api.updateRequestIds.toSet(),
      hasLength(2),
      reason: 'payload 改变后必须换 ticket；相同 payload 重试才复用原 ticket',
    );

    await tester.tap(find.byKey(const Key('club-post-edit-submit')));
    await tester.pumpAndSettle();
    expect(api.updateCalls, 3);
    expect(api.updateRequestIds[2], api.updateRequestIds[1]);
  });
}
