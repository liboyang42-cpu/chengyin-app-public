// 广场互动:点一下到底打到哪个接口、失败了跟用户说什么。
//
// ★ 为什么单独立一条:上一代 `SquareApi` 的互动全打在 `/api/v1/community/*`,
//   而后端 `github/master`(与冻结契约 `contract/openapi-v1.json`)里**没有**
//   这些路由 —— 按钮都在、点了没人接,和「没做」在用户那边是一回事。
//   这里锁的是**真实端点**:帖文/评论的读、赞、举报、删、发。
//
// 断言只看 wire(调到哪个方法、带什么参)+ 用户看得见的回执/错误,
// 不锁渲染细节 —— 渲染在 square_like_feedback_test / 视觉对照里管。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _StubSquareApi implements SquareApi {
  final List<String> calls = <String>[];
  final List<int> commentPages = <int>[];
  Object? failure;

  void _maybeFail() {
    final Object? error = failure;
    if (error != null) throw error;
  }

  @override
  Future<SquarePost> info(int id) async => throw UnimplementedError();

  @override
  Future<void> like(int id, {int type = 1}) async {
    calls.add('like:$id');
    _maybeFail();
  }

  @override
  Future<String> report(int id) async {
    calls.add('report:$id');
    _maybeFail();
    return '举报已提交，内容将进入审核';
  }

  @override
  Future<String> reportComment(int commentId) async {
    calls.add('reportComment:$commentId');
    _maybeFail();
    return '举报已提交，评论将进入审核';
  }

  @override
  Future<String> delete(int id) async {
    calls.add('delete:$id');
    _maybeFail();
    return '删除成功';
  }

  @override
  Future<void> deleteComment(int commentId) async {
    calls.add('deleteComment:$commentId');
    _maybeFail();
  }

  @override
  Future<void> addComment(int postId, String body, {int? replyToId}) async {
    calls.add('addComment:$postId:$body:${replyToId ?? 0}');
    _maybeFail();
  }

  @override
  Future<void> setCommentLike(int commentId, {required bool enabled}) async {
    calls.add('setCommentLike:$commentId:$enabled');
    _maybeFail();
  }

  @override
  Future<List<Comment>> comments(
    int postId, {
    int page = 1,
    int limit = 50,
  }) async {
    commentPages.add(page);
    _maybeFail();
    return <Comment>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const SquarePost _otherPost = SquarePost(
  id: 7,
  memberId: 11,
  contents: '别人的动态',
  viewerCanComment: true,
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required _StubSquareApi api,
  SquarePost post = _otherPost,
  List<Comment> comments = const <Comment>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        squareApiProvider.overrideWithValue(api),
        squareDetailProvider(7).overrideWith((ref) async => post),
        squareCommentsProvider(7).overrideWith((ref) async => comments),
      ].cast(),
      // 与 `lib/main.dart` 的根一致:CupertinoApp + DefaultMaterialLocalizations。
      // 少了它,页内 RefreshIndicator.adaptive 会因拿不到 localizations 直接断言崩。
      child: const CupertinoApp(
        localizationsDelegates: <LocalizationsDelegate<dynamic>>[
          DefaultMaterialLocalizations.delegate,
        ],
        home: SquareDetailPage(postId: 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 确认弹窗里的那颗按钮。页面上常有同名文案(导航栏图标、列表行),
/// 只认对话框里的那一颗,别点到别处去。
Future<void> _tapDialogAction(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoAlertDialog),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('举报帖文:确认后打到 /api/creativesquare/report 的对应方法', (
    WidgetTester tester,
  ) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(tester, api: api);

    await tester.tap(find.bySemanticsLabel('举报'));
    await tester.pumpAndSettle();
    expect(find.text('确认举报这条内容？举报后将提交平台审核。'), findsOneWidget);

    await _tapDialogAction(tester, '举报');

    expect(api.calls, <String>['report:7']);
    expect(find.text('举报已提交，内容将进入审核'), findsOneWidget);
  });

  testWidgets('举报帖文失败:把后端/网络的失败原话摆出来,不假装已处理', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi()
      ..failure = Exception('网络错误，请重试');
    await _pumpDetail(tester, api: api);

    await tester.tap(find.bySemanticsLabel('举报'));
    await tester.pumpAndSettle();
    await _tapDialogAction(tester, '举报');

    expect(find.text('网络错误，请重试'), findsOneWidget);
  });

  testWidgets('举报取消:一个请求都不发', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(tester, api: api);

    await tester.tap(find.bySemanticsLabel('举报'));
    await tester.pumpAndSettle();
    await _tapDialogAction(tester, '取消');

    expect(api.calls, isEmpty);
  });

  testWidgets('删自己的帖文:确认后打到 /api/creativesquare/delete 的对应方法', (
    WidgetTester tester,
  ) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(
      tester,
      api: api,
      post: const SquarePost(id: 7, memberId: 99, contents: '我自己的动态'),
    );

    await tester.tap(find.bySemanticsLabel('删除'));
    await tester.pumpAndSettle();
    await _tapDialogAction(tester, '删除');

    expect(api.calls, <String>['delete:7']);
  });

  testWidgets('举报评论:确认后打到评论自己的举报', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(
      tester,
      api: api,
      comments: <Comment>[
        Comment(id: 3, memberId: 11, memberNickname: '阿兰', contents: '好路线'),
      ],
    );

    // 导航栏那颗 flag 是举报**帖文**的;评论行那颗才是举报评论 —— 按语义标签点。
    await tester.tap(find.bySemanticsLabel('举报这条评论'));
    await tester.pumpAndSettle();
    expect(find.text('确认举报这条评论？举报后将提交平台审核。'), findsOneWidget);

    await _tapDialogAction(tester, '举报');

    expect(api.calls, <String>['reportComment:3']);
    expect(find.text('举报已提交，评论将进入审核'), findsOneWidget);
  });

  testWidgets('删自己的评论:确认后打到评论删除', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(
      tester,
      api: api,
      comments: <Comment>[
        Comment(id: 3, memberId: 99, memberNickname: '我', contents: '我写的'),
      ],
    );

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await _tapDialogAction(tester, '删除');

    expect(api.calls, <String>['deleteComment:3']);
    expect(find.text('评论已删除'), findsOneWidget);
  });

  testWidgets('发评论带 owner 归属;回复带 reply_id', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(
      tester,
      api: api,
      comments: <Comment>[
        Comment(id: 3, memberId: 11, memberNickname: '阿兰', contents: '好路线'),
      ],
    );

    await tester.enterText(find.byKey(const Key('square-comment-input')), '顶');
    await tester.tap(find.byKey(const Key('square-comment-send')));
    await tester.pumpAndSettle();
    expect(api.calls, <String>['addComment:7:顶:0']);
    expect(find.text('评论成功'), findsOneWidget);

    await tester.tap(find.byKey(const Key('comment-reply-3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('square-comment-input')), '回你');
    await tester.tap(find.byKey(const Key('square-comment-send')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'addComment:7:回你:3');
    expect(find.text('回复成功'), findsOneWidget);
  });

  testWidgets('真实契约的帖文(没有 viewerCanComment)照样能评论', (WidgetTester tester) async {
    // ★ 回执≠观测:`/api/creativesquare/info` 不投影 viewerCanComment,
    //   模型默认 false 的话输入框整块消失 —— 那是「评论功能没了」,
    //   而不是一个字段的解析细节。所以这里按真实响应构造,断言输入框在。
    final SquarePost post = SquarePost.fromJson(<String, dynamic>{
      'id': 7,
      'memberId': 11,
      'contents': '真实契约的帖文',
      'likeCount': 3,
      'isLiked': 1,
      'commentCount': 2,
    });
    expect(post.viewerCanComment, isTrue);
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(tester, api: api, post: post);

    expect(find.byKey(const Key('square-comment-input')), findsOneWidget);
    expect(find.byKey(const Key('square-comment-disabled')), findsNothing);
  });

  testWidgets('楼主的帖文下,别人的评论只给举报不给删除', (WidgetTester tester) async {
    // 后端 `/api/comment/delete` 只允许评论作者本人删;给楼主一个必失败的
    // 删除入口,等于点一次报一次「无权删除该评论」。小程序也只给作者。
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(
      tester,
      api: api,
      post: const SquarePost(id: 7, memberId: 99, contents: '我自己的动态'),
      comments: <Comment>[
        Comment(id: 3, memberId: 11, memberNickname: '阿兰', contents: '好路线'),
      ],
    );

    expect(find.text('删除'), findsNothing);
    expect(find.bySemanticsLabel('举报这条评论'), findsOneWidget);
  });

  testWidgets('评论续页按页码拉,不是游标', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pumpDetail(
      tester,
      api: api,
      comments: List<Comment>.generate(
        50,
        (int i) => Comment(id: 100 + i, memberId: 11, contents: '第 $i 条'),
      ),
    );

    final Finder loadMore = find.byKey(const Key('square-comments-load-more'));
    expect(loadMore, findsOneWidget);
    // 50 条评论把按钮推到屏幕外,先滚到它脸上再点。
    await tester.ensureVisible(loadMore);
    await tester.pumpAndSettle();
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(api.commentPages, <int>[2]);
  });
}
