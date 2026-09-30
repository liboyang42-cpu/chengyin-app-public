// 点赞/收藏的即时反馈与失败回滚(渲染层)。
//
// ★ 判据是「点完立刻可见」:不等接口回来,也不等列表重拉。
//   失败则原样退回服务端数值 —— 不留一个下次刷新才被打回原形的假已赞。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _StubSquareApi implements SquareApi {
  final List<({String action, bool enabled})> actions =
      <({String action, bool enabled})>[];
  final List<int> likes = <int>[];
  final List<({int id, bool enabled})> commentLikes =
      <({int id, bool enabled})>[];
  Completer<void>? pending;
  Object? failure;

  /// 先等 [pending] —— 测试要能自己决定「请求什么时候失败」,
  /// 否则即时反馈那一帧根本来不及渲染。
  Future<void> _respond() async {
    await pending?.future;
    if (failure case final Object error) throw error;
  }

  @override
  Future<void> setAction(int id, String action, {bool enabled = true}) async {
    actions.add((action: action, enabled: enabled));
    await _respond();
  }

  /// 点赞走真实端点 `/api/creativesquare/like`(切换式,只说「翻一次」)。
  @override
  Future<void> like(int id, {int type = 1}) async {
    likes.add(id);
    await _respond();
  }

  @override
  Future<void> setCommentLike(int commentId, {required bool enabled}) async {
    commentLikes.add((id: commentId, enabled: enabled));
    await _respond();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpList(
  WidgetTester tester, {
  required _StubSquareApi api,
  required SquarePost post,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        squareApiProvider.overrideWithValue(api),
        squareFeedPageProvider.overrideWith(
          (ref, mode) async =>
              SquareFeedPage(items: <SquarePost>[post], hasMore: false),
        ),
      ].cast(),
      child: const MaterialApp(home: SquareListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const SquarePost post = SquarePost(
    id: 7,
    memberId: 11,
    contents: '数一下赞',
    likeNum: 12,
  );

  testWidgets('点赞:请求还没回来就已经 +1', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi()..pending = Completer<void>();
    await _pumpList(tester, api: api, post: post);

    await tester.tap(find.byKey(const Key('square-post-like-7')));
    await tester.pump();

    expect(find.text('13'), findsOneWidget);
    expect(api.likes.single, 7);

    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('点赞失败:数字回滚到服务端值', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi()
      ..pending = Completer<void>()
      ..failure = Exception('网络错误');
    await _pumpList(tester, api: api, post: post);

    await tester.tap(find.byKey(const Key('square-post-like-7')));
    await tester.pump();
    expect(find.text('13'), findsOneWidget, reason: '先给即时反馈');

    api.pending!.completeError(Exception('网络错误'));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget, reason: '失败要回滚,不能停在 13');
  });

  testWidgets('详情页点赞同样是即时的,失败同样回滚', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi()
      ..pending = Completer<void>()
      ..failure = Exception('网络错误');
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareApiProvider.overrideWithValue(api),
          squareDetailProvider(7).overrideWith((ref) async => post),
          squareCommentsProvider(7).overrideWith((ref) async => <Comment>[]),
        ].cast(),
        child: const MaterialApp(home: SquareDetailPage(postId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('square-detail-like-action')));
    await tester.pump();
    expect(find.text('13'), findsOneWidget);

    api.pending!.completeError(Exception('网络错误'));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('评论点赞:即时 +1,失败回滚', (WidgetTester tester) async {
    final _StubSquareApi api = _StubSquareApi()
      ..pending = Completer<void>()
      ..failure = Exception('网络错误');
    final Comment comment = Comment(
      id: 3,
      memberId: 11,
      memberNickname: '阿兰',
      contents: '好路线',
      likeCount: 1,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareApiProvider.overrideWithValue(api),
          squareDetailProvider(7).overrideWith(
            (ref) async => const SquarePost(
              id: 7,
              memberId: 11,
              contents: '主帖',
              viewerCanComment: true,
            ),
          ),
          squareCommentsProvider(
            7,
          ).overrideWith((ref) async => <Comment>[comment]),
        ].cast(),
        child: const MaterialApp(home: SquareDetailPage(postId: 7)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('comment-like-3')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    api.pending!.completeError(Exception('网络错误'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });
}
