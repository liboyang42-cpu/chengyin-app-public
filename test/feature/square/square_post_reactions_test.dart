// 点赞 / 收藏的乐观更新与失败回滚(纯逻辑,不含渲染)。

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/feature/square/square_post_reactions.dart';

void main() {
  const SquarePost post = SquarePost(
    id: 7,
    memberId: 9,
    likeNum: 4,
    isLiked: 0,
  );

  test('点赞:立刻 +1 并置为已赞,取消失效/重复点不会连加', () {
    final SquarePostReactions reactions = SquarePostReactions();
    final SquarePost liked = reactions.applyLike(post, liked: true);
    expect(liked.liked, isTrue);
    expect(liked.likeNum, 5);
    expect(reactions.display(post).likeNum, 5, reason: '渲染要看到本地预期');

    final SquarePost again = reactions.applyLike(post, liked: true);
    expect(again.likeNum, 5, reason: '重复点已赞不该再加一次');

    final SquarePost unliked = reactions.applyLike(post, liked: false);
    expect(unliked.liked, isFalse);
    expect(unliked.likeNum, 4);
  });

  test('取消赞不会被减成负数', () {
    final SquarePostReactions reactions = SquarePostReactions();
    const SquarePost one = SquarePost(id: 8, memberId: 9, likeNum: 0);
    final SquarePost result = reactions.applyLike(
      one.copyWith(isLiked: 1),
      liked: false,
    );
    expect(result.likeNum, 0);
  });

  test('收藏:本地立刻翻转', () {
    final SquarePostReactions reactions = SquarePostReactions();
    expect(reactions.applyBookmark(post, bookmarked: true).bookmarked, isTrue);
    expect(
      reactions.applyBookmark(post, bookmarked: false).bookmarked,
      isFalse,
    );
  });

  test('失败回滚:覆盖撤掉,回到服务端原值', () {
    final SquarePostReactions reactions = SquarePostReactions();
    reactions.applyLike(post, liked: true);
    reactions.rollback(post.id);
    expect(reactions.display(post).likeNum, 4);
    expect(reactions.display(post).liked, isFalse);
    expect(reactions.hasPending, isFalse);
  });

  test('服务端追上本地预期后撤覆盖;没追上则保留', () {
    final SquarePostReactions reactions = SquarePostReactions();
    reactions.applyLike(post, liked: true);

    expect(
      reactions.reconcile(<SquarePost>[post]),
      isFalse,
      reason: '服务端还是旧的 4 赞,覆盖要留着,否则会闪回',
    );
    expect(reactions.display(post).likeNum, 5);

    expect(
      reactions.reconcile(<SquarePost>[post.copyWith(isLiked: 1, likeNum: 5)]),
      isTrue,
    );
    expect(reactions.hasPending, isFalse);
  });

  test('评论点赞:同样的即时反馈与回滚', () {
    final SquareCommentReactions reactions = SquareCommentReactions();
    final Comment comment = Comment(id: 3, memberId: 9, likeCount: 1);
    final Comment liked = reactions.applyLike(comment, liked: true);
    expect(liked.liked, isTrue);
    expect(liked.likeCount, 2);
    reactions.rollback(3);
    expect(reactions.display(comment).likeCount, 1);

    reactions.applyLike(comment, liked: true);
    expect(
      reactions.reconcile(<Comment>[
        comment.copyWith(isLiked: 1, likeCount: 2),
      ]),
      isTrue,
    );
    // 覆盖撤掉后,渲染回到服务端那一份(而不是这个旧的入参)。
    expect(reactions.hasPending, isFalse);
    expect(
      reactions.display(comment.copyWith(isLiked: 1, likeCount: 2)).likeCount,
      2,
    );
  });
}
