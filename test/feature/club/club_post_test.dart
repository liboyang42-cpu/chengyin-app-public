import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/models/club_post.dart';

void main() {
  ClubPost p(Map<String, dynamic> m) =>
      ClubPost.fromJson(<String, dynamic>{'id': 1, ...m});

  group('图片:分号分隔', () {
    test('切开并去空', () {
      expect(p(<String, dynamic>{'images': 'a.jpg;b.jpg'}).images, <String>[
        'a.jpg',
        'b.jpg',
      ]);
      expect(p(<String, dynamic>{'images': 'a.jpg; ;b.jpg;'}).images, <String>[
        'a.jpg',
        'b.jpg',
      ]);
    });
    test('空串给空表,不给 [\'\']', () {
      expect(p(<String, dynamic>{'images': ''}).images, isEmpty);
      expect(p(<String, dynamic>{}).images, isEmpty);
    });
  });

  group('★ 帖子可以只有图没有字', () {
    test('只有图 → 正文不渲染,但帖子有效', () {
      final x = p(<String, dynamic>{'images': 'a.jpg'});
      expect(x.body, isNull, reason: '空正文渲染出来会把图片顶下去');
      expect(x.hasSomething, isTrue);
    });
    test('只有字 → 同样有效', () {
      expect(p(<String, dynamic>{'content': '今天走了六个点'}).hasSomething, isTrue);
    });
    test('★ 图与字都没有 = 空帖,不进列表', () {
      expect(p(<String, dynamic>{'content': '  '}).hasSomething, isFalse);
      final feed = ClubFeed.fromJson(<String, dynamic>{
        'rows': <dynamic>[
          <String, dynamic>{'id': 1, 'content': 'A'},
          <String, dynamic>{'id': 2},
          <String, dynamic>{'id': 3, 'images': 'x.jpg'},
        ],
      });
      expect(feed.rows.map((ClubPost x) => x.id).toList(), <int>[1, 3]);
    });
  });

  group('★ 互动数全为 0 时整行不显示', () {
    test('刚发的帖不挂「0 赞 0 评论」', () {
      expect(p(<String, dynamic>{'content': 'x'}).statsText, isNull);
    });
    test('只有赞', () {
      expect(
        p(<String, dynamic>{'content': 'x', 'likeCount': 3}).statsText,
        '3 赞',
      );
    });
    test('都有', () {
      expect(
        p(<String, dynamic>{
          'content': 'x',
          'likeCount': 3,
          'commentCount': 2,
        }).statsText,
        '3 赞 · 2 评论',
      );
    });
  });

  group('★ 没加入俱乐部 ≠ 大家都没发帖', () {
    test('clubCount 为 0 → 页面该说"先加入一个俱乐部"', () {
      final f = ClubFeed.fromJson(<String, dynamic>{
        'rows': <dynamic>[],
        'clubCount': 0,
      });
      expect(f.hasNoClub, isTrue, reason: '只显示空列表会让人以为大家都没发帖');
    });
    test('有俱乐部但没帖 → 才是真的空', () {
      final f = ClubFeed.fromJson(<String, dynamic>{
        'rows': <dynamic>[],
        'clubCount': 2,
      });
      expect(f.hasNoClub, isFalse);
      expect(f.rows, isEmpty);
    });
  });

  test('作者名兜底', () {
    expect(p(<String, dynamic>{'nickname': '  '}).authorName, '城瘾用户');
    expect(p(<String, dynamic>{'nickname': ' 阿岚 '}).authorName, '阿岚');
  });

  group('★ 作者主页落点', () {
    test('后端字段叫 authorMemberId,不是 memberId', () {
      expect(
        p(<String, dynamic>{'authorMemberId': 42}).authorRoute,
        '/user/42',
      );
      expect(
        p(<String, dynamic>{'memberId': 42}).authorRoute,
        isNull,
        reason: '拿错字段名会让整列作者都点不动',
      );
    });
    test('★ 拿不到 id 就不给点', () {
      expect(
        p(<String, dynamic>{}).authorRoute,
        isNull,
        reason: '跳 /user/0 会进一个空主页',
      );
      expect(p(<String, dynamic>{'authorMemberId': 0}).authorRoute, isNull);
    });
  });

  test('公告、置顶与乐观锁版本兼容数字和布尔置顶值', () {
    final ClubPost pinned = p(<String, dynamic>{
      'type': 2,
      'isPinned': 1,
      'version': 3,
    });
    expect(pinned.isAnnouncement, isTrue);
    expect(pinned.pinned, isTrue);
    expect(pinned.version, 3);
    expect(pinned.edited, isFalse, reason: 'version 可能只由置顶递增，不能据此伪装成已编辑');
    expect(p(<String, dynamic>{'edited': true}).edited, isTrue);
    expect(
      p(<String, dynamic>{'viewerCanManage': true}).viewerCanManage,
      isTrue,
    );
    expect(p(<String, dynamic>{'isPinned': false}).pinned, isFalse);
  });

  // a2-club-entry 条目14:帖子引用卡的判据字段(后端投影见
  // ApiClubController.java:1470-1492 的 refType/sportName/sportCover/
  // sportTopicId/isTopicTemplate)。
  group('★ 引用卡:完赛分享 / 模板卡 / 试玩落点', () {
    test('refType=1 + 名字 → 完赛分享,不是引用卡', () {
      final x = p(<String, dynamic>{
        'refType': 1,
        'refId': 501,
        'sportName': '周六场',
        'sportCover': 'c.jpg',
        'sportTopicId': 77,
      });
      expect(x.isCompletionShare, isTrue);
      expect(x.hasPlayRefCard, isFalse);
      // 完赛帖没有正文也算「有内容」,不许被 hasSomething 滤掉。
      expect(x.hasSomething, isTrue);
    });
    test('refType=2 + 名字 + 封面 → 引用卡,试玩/模板都落对主题', () {
      final x = p(<String, dynamic>{
        'refType': 2,
        'refId': 77,
        'sportName': ' 静安夜跑 ',
        'sportCover': 'cover.jpg',
        'sportTopicId': 77,
        'isTopicTemplate': 1,
      });
      expect(x.isCompletionShare, isFalse);
      expect(x.hasPlayRefCard, isTrue);
      expect(x.isTopicTemplate, isTrue);
      expect(x.refTopicRoute, '/topic/77');
      expect(x.refPlayRoute, '/play/0?topicId=77');
    });
    test('★ 没封面不出卡(真源 hasFeedPlayCover 同款)', () {
      expect(
        p(<String, dynamic>{
          'refType': 2,
          'sportName': '静安夜跑',
          'sportTopicId': 77,
        }).hasPlayRefCard,
        isFalse,
      );
    });
    test('★ 被引对象已删 → sportName 空,不渲染也不给路由', () {
      final x = p(<String, dynamic>{
        'refType': 2,
        'sportName': '  ',
        'sportCover': 'cover.jpg',
        'sportTopicId': 77,
      });
      expect(x.hasPlayRefCard, isFalse);
      expect(x.isCompletionShare, isFalse);
      expect(x.hasSomething, isFalse);
    });
    test('拿不到 sportTopicId 就不给点(跳 /topic/0 是空页)', () {
      final x = p(<String, dynamic>{
        'refType': 2,
        'sportName': '静安夜跑',
        'sportCover': 'cover.jpg',
      });
      expect(x.hasPlayRefCard, isTrue);
      expect(x.refNavigable, isFalse);
      expect(x.refTopicRoute, isNull);
      expect(x.refPlayRoute, isNull);
    });
    test('无引用的普通帖一切照旧', () {
      final x = p(<String, dynamic>{'content': '今天走了六个点'});
      expect(x.isCompletionShare, isFalse);
      expect(x.hasPlayRefCard, isFalse);
      expect(x.refTopicRoute, isNull);
    });
  });
}
