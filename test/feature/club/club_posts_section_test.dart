// 俱乐部详情页的「圈子」块。
//
// ★★ 这一整块此前**接口写好了、没有任何页面调它**:
//   `/api/club/post/list`、`post/create`、`post/comment/*` 在 club_api.dart
//   里都有,clubPosts()/createPost()/postComments() 全是零调用方。
//   小程序 pages/club/detail 一直有这块 —— 用户点不到就是缺口。
//
// 这里锁三条最容易错的:
//   · 非成员不给发帖入口(后端会拒,摆一个必然报错的按钮是本项目老毛病)
//   · 空态要说清「为什么空」——成员看到的和非成员看到的不是一回事
//   · 空内容不给发

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _FakeClubApi implements ClubApi {
  _FakeClubApi({this.posts = const <ClubPost>[], this.onCreate});
  final List<ClubPost> posts;
  final void Function(int clubId, String content)? onCreate;

  @override
  Future<List<ClubPost>> clubPosts(
    int clubId, {
    int pageNum = 1,
    int pageSize = 20,
  }) async => posts;

  @override
  Future<void> createPost({
    required int clubId,
    required String content,
    List<String> images = const <String>[],
  }) async {
    onCreate?.call(clubId, content);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(
  WidgetTester t,
  _FakeClubApi api, {
  required bool canPost,
  Locale locale = const Locale('zh'),
}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubApiProvider.overrideWithValue(api),
        clubMembersProvider(7).overrideWith((ref) async => <ClubMember>[]),
      ].cast(),
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ClubPostsSection(clubId: 7, canPost: canPost),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('English post empty state respects membership permissions', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pump(tester, _FakeClubApi(), canPost: false, locale: const Locale('en'));
    expect(find.text('This club has no posts yet'), findsOneWidget);
    expect(find.text('Join the club to post'), findsOneWidget);
    expect(find.byKey(const Key('club-post-compose')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('★★ 非成员没有发帖入口 —— 点下去后端必拒', (WidgetTester t) async {
    await _pump(t, _FakeClubApi(), canPost: false);
    expect(find.byKey(const Key('club-post-compose')), findsNothing);
    expect(
      find.text('加入后可以发动态'),
      findsOneWidget,
      reason: '空态要说清为什么发不了,不能只说「没有动态」',
    );
  });

  testWidgets('★ 成员有发帖入口,空态文案也不一样', (WidgetTester t) async {
    await _pump(t, _FakeClubApi(), canPost: true);
    expect(find.byKey(const Key('club-post-compose')), findsOneWidget);
    expect(find.textContaining('发第一条'), findsOneWidget);
  });

  testWidgets('★★ 空内容不给发布', (WidgetTester t) async {
    String? sent;
    await _pump(
      t,
      _FakeClubApi(onCreate: (int _, String c) => sent = c),
      canPost: true,
    );
    await t.tap(find.byKey(const Key('club-post-compose')));
    await t.pumpAndSettle();

    final Finder submit = find.byKey(const Key('club-compose-submit'));
    expect(testerEnabled(t, submit), isFalse, reason: '空内容时发布钮该是禁用的');

    await t.enterText(find.byType(CupertinoTextField), '今晚跑了静安夜行');
    await t.pumpAndSettle();
    expect(testerEnabled(t, submit), isTrue);

    await t.tap(submit);
    await t.pumpAndSettle();
    expect(sent, '今晚跑了静安夜行');
  });

  testWidgets('★ 有动态时渲染成卡片', (WidgetTester t) async {
    await _pump(
      t,
      _FakeClubApi(
        posts: <ClubPost>[
          ClubPost.fromJson(<String, dynamic>{
            'id': 1,
            'content': '周六六点静安寺集合',
            'nickname': '阿兰',
            'likeCount': 3,
            'commentCount': 2,
          }),
        ],
      ),
      canPost: true,
    );
    expect(find.text('周六六点静安寺集合'), findsOneWidget);
    expect(
      find.byKey(const Key('club-post-comment')),
      findsOneWidget,
      reason: '评论入口没了 —— 它原来是只读图标,这一轮才接通',
    );
  });
}

bool testerEnabled(WidgetTester t, Finder f) {
  final Widget w = t.widget(f);
  if (w is FilledButton) return w.onPressed != null;
  if (w is CupertinoButton) return w.onPressed != null;
  throw StateError('不是可识别按钮:${w.runtimeType}');
}
