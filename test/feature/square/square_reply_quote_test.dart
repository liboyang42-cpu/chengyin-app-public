// 楼中楼:回复要能看出「在回谁」。
//
// ★ 小程序那边回复弹窗发完就没了 —— 列表里一条回复和一条顶层评论
//   长得一模一样,只有发的人自己知道回了谁。App 这边把被回复的人
//   标在回复上方;名字解不出来时**不显示**,不编一个。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_comment_thread.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _NoopSquareApi implements SquareApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Comment _comment({
  required int id,
  required int memberId,
  required String name,
  String? contents,
  int? parentId,
  int? rootId,
  int? repliedToMemberId,
}) => Comment(
  id: id,
  memberId: memberId,
  memberNickname: name,
  contents: contents ?? '内容 $id',
  parentId: parentId,
  rootId: rootId,
  repliedToMemberId: repliedToMemberId,
);

void main() {
  final Comment root = _comment(id: 1, memberId: 11, name: '阿兰');
  final Comment reply = _comment(
    id: 2,
    memberId: 22,
    name: '小林',
    parentId: 1,
    rootId: 1,
    repliedToMemberId: 11,
  );

  group('回复引用解析', () {
    test('父评论在已加载列表里 → 用父评论作者名', () {
      expect(squareReplyToName(reply, <Comment>[root, reply]), '阿兰');
    });

    test('父评论没加载出来 → 退回 repliedToMemberId 的作者名', () {
      expect(
        squareReplyToName(
          _comment(
            id: 9,
            memberId: 22,
            name: '小林',
            parentId: 404,
            repliedToMemberId: 11,
          ),
          <Comment>[root],
        ),
        '阿兰',
      );
    });

    test('解不出来就不显示,不编名字', () {
      expect(squareReplyToName(root, <Comment>[root]), isNull);
      expect(
        squareReplyToName(
          _comment(id: 5, memberId: 22, name: '小林', parentId: 404),
          <Comment>[root],
        ),
        isNull,
      );
    });
  });

  testWidgets('详情页:回复标出「回复 @被回复人」,顶层评论不标', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          authControllerProvider.overrideWith(_LoggedInAuth.new),
          squareApiProvider.overrideWithValue(_NoopSquareApi()),
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
          ).overrideWith((ref) async => <Comment>[root, reply]),
        ].cast(),
        child: const MaterialApp(home: SquareDetailPage(postId: 7)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('comment-reply-quote-2')), findsOneWidget);
    expect(find.text('回复 @阿兰'), findsOneWidget);
    expect(find.byKey(const Key('comment-reply-quote-1')), findsNothing);
  });
}
