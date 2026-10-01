// 圈子评论半屏。
//
// ★★ 最要紧的一条:**举报只入审核队列,不立即删** ——
//   提示必须按后端原话说,不许自己写「已删除」。
//   (这条在 club_api.reportComment 的注释里已经写死,
//    这里把它钉成行为断言,免得下一个人在 UI 层又编一句。)

import 'package:flutter/cupertino.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club_comment.dart';
import 'package:chengyin_app/feature/club/club_comments_sheet.dart';

class _FakeClubApi implements ClubApi {
  _FakeClubApi({this.rows = const <ClubComment>[], this.onCreate});
  final List<ClubComment> rows;
  final void Function(String)? onCreate;

  @override
  Future<List<ClubComment>> postComments(
    int postId, {
    int pageNum = 1,
    int pageSize = 50,
  }) async => rows;

  @override
  Future<void> createComment({
    required int postId,
    required String content,
  }) async => onCreate?.call(content);

  @override
  Future<String> reportComment(int commentId) async => '举报已提交,将进入审核';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _open(WidgetTester t, _FakeClubApi api, {Locale locale = const Locale('zh')}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[clubApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => TextButton(
              onPressed: () => showClubCommentsSheet(c, postId: 1),
              child: const Text('开'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('English comments preserve submitted content and author fallback', (t) async {
    final sent = <String>[];
    await _open(t, _FakeClubApi(
      rows: [const ClubComment(id: 9, memberId: 999, content: '原始评论')],
      onCreate: sent.add,
    ), locale: const Locale('en'));
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Chengyin user'), findsOneWidget);
    expect(find.text('原始评论'), findsOneWidget);
    await t.enterText(find.byType(CupertinoTextField), '我的原文');
    await t.tap(find.byKey(const Key('club-comment-send')));
    await t.pumpAndSettle();
    expect(sent, ['我的原文']);
    expect(t.takeException(), isNull);
  });

  testWidgets('★ 空态说清楚,不是一片空白', (WidgetTester t) async {
    await _open(t, _FakeClubApi());
    expect(find.text('还没有评论'), findsOneWidget);
  });

  testWidgets('★★ 空内容不发 —— 按了也不该打接口', (WidgetTester t) async {
    final List<String> sent = <String>[];
    await _open(t, _FakeClubApi(onCreate: sent.add));
    await t.tap(find.byKey(const Key('club-comment-send')));
    await t.pumpAndSettle();
    expect(sent, isEmpty, reason: '空评论也发出去了');

    await t.enterText(find.byType(CupertinoTextField), '同去');
    await t.tap(find.byKey(const Key('club-comment-send')));
    await t.pumpAndSettle();
    expect(sent, <String>['同去']);
  });

  testWidgets('★★ 举报提示用后端原话,不许说「已删除」', (WidgetTester t) async {
    await _open(
      t,
      _FakeClubApi(
        rows: <ClubComment>[
          // memberId 与当前登录用户不同 → 走举报分支
          ClubComment.fromJson(<String, dynamic>{
            'id': 9,
            'memberId': 999,
            'content': '这条我要举报',
            'nickname': '别人',
          }),
        ],
      ),
    );
    expect(find.text('这条我要举报'), findsOneWidget);

    await t.tap(find.text('举报'));
    await t.pumpAndSettle();
    // 举报面板:先选理由,再提交(不选理由提交钮是禁用的)
    await t.tap(find.text('含有违法违规内容'));
    await t.pumpAndSettle();
    await t.tap(find.text('提交举报'));
    await t.pumpAndSettle();

    expect(
      find.textContaining('进入审核'),
      findsOneWidget,
      reason: '举报只入队列,提示说成「已删除」就是骗用户',
    );
    expect(find.textContaining('已删除'), findsNothing);
  });
}
