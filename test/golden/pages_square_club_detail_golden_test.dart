// 广场详情 + 俱乐部详情两页快照。
//
// fixture 造边界形态,不造漂亮数据:
//   广场详情:自己的帖 vs 别人的帖(举报入口的可见性不同)、零评论、无正文只有图
//   俱乐部详情:未加入 / 已加入 / 我是主理人 —— 三档的主按钮必须不同
//
// 更新基准图:flutter test --update-goldens test/golden/pages_square_club_detail_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_access.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';
import 'golden_theme.dart';

class _FixedAuth extends AuthController {
  _FixedAuth(this._s);
  final AuthState _s;
  @override
  AuthState build() => _s;
}

AuthState _me(int id) => AuthState(
  user: User(id: id, nickname: '阿兰', avatar: '', role: 'player'),
  initialized: true,
);

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

SquarePost _post(Map<String, dynamic> j) =>
    SquarePost.fromJson(<String, dynamic>{'id': 7, ...j});

void main() {
  testWidgets('★ 广场详情:别人的帖(举报入口应可见)+ 零评论', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        authControllerProvider.overrideWith(() => _FixedAuth(_me(1))),
        squareDetailProvider(7).overrideWith(
          (ref) async => _post(<String, dynamic>{
            'memberId': 99, // 不是我
            'memberNickname': '别人',
            'contents': '今晚这条路灯全亮着,很少见。',
            'likeNum': 8,
            'commentCount': 0,
            'viewerCanComment': true,
          }),
        ),
        squareCommentsProvider(7).overrideWith((ref) async => <Comment>[]),
      ], const SquareDetailPage(postId: 7)),
      'goldens/page_square_detail_other.png',
    );
  });

  testWidgets('广场详情:自己的帖 + 两条评论', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        authControllerProvider.overrideWith(() => _FixedAuth(_me(11))),
        squareDetailProvider(7).overrideWith(
          (ref) async => _post(<String, dynamic>{
            'memberId': 11, // 就是我
            'memberNickname': '阿兰',
            'contents': '发一条自己的。',
            'pics': <String>['https://example.invalid/square-detail.jpg'],
            'likeNum': 3,
            'commentCount': 2,
            'isLiked': 1,
            'viewerCanComment': true,
          }),
        ),
        squareCommentsProvider(7).overrideWith(
          (ref) async => <Comment>[
            Comment.fromJson(<String, dynamic>{
              'id': 1,
              'memberId': 21,
              'memberNickname': '路人甲',
              'contents': '这条我也走过。',
            }),
            // ★ 没有昵称的评论 —— 不该渲成空白的一行
            Comment.fromJson(<String, dynamic>{
              'id': 2,
              'memberId': 22,
              'contents': '匿名评论一条。',
            }),
          ],
        ),
      ], const SquareDetailPage(postId: 7)),
      'goldens/page_square_detail_mine.png',
    );
  });

  // ⚠️ **三档必须拆成三个 testWidgets,不能在一个测试里循环 pumpWidget。**
  //    `pumpWidget` 会复用已有的 ProviderScope,而 Riverpod **不会**用新的
  //    overrides 去重算已经建好的 provider —— 循环里第 2、3 次拿到的还是第 1 次的值。
  //    我第一版就是循环写的,拍出来三张图 md5 完全相同;
  //    差一点把它当成「页面没区分三档」的产品 bug 报出去,其实页面分得好好的
  //    (club_detail_page.dart:136-142 按 isOwner/isJoined 分了三支)。
  //    发现它靠的是「三张图必须互异」这条断言,不是靠看图。
  // ⚠️ goldenPath 必须是**字面量**:`no_orphan_goldens_test` 靠在测试源码里找
  //    文件名字面量判断基线有没有人引用,插值出来的名字它一个都看不见。
  void clubCase(String name, String goldenPath, Map<String, dynamic> extra) {
    testWidgets('俱乐部详情:$name', (WidgetTester tester) async {
      await _shot(
        tester,
        _app([
          authControllerProvider.overrideWith(() => _FixedAuth(_me(1))),
          // ★ 圈子动态区是本页新块;不给替身的话 provider 永远 pending,
          //   pumpAndSettle 直接超时(一个永远转的圈)。
          clubPostsProvider(3).overrideWith(
            (ref) async => <ClubPost>[
              ClubPost.fromJson(<String, dynamic>{
                'id': 1,
                'content': '周六六点静安寺集合,带头灯。',
                'nickname': '阿兰',
                'likeCount': 3,
                'commentCount': 2,
              }),
            ],
          ),
          clubDetailProvider(3).overrideWith(
            (ref) async => Club.fromJson(<String, dynamic>{
              'id': 3,
              'name': '城市夜骑俱乐部',
              'description': '每周三晚八点,从静安寺出发。',
              'memberCount': 128,
              'city': '上海',
              ...extra,
            }),
          ),
          clubMembersProvider(3).overrideWith((ref) async => <ClubMember>[]),
          clubTopicsProvider(3).overrideWith((ref) async => <ClubTopic>[]),
          clubLeaderboardProvider((
            clubId: 3,
            sort: ClubRankSort.composite,
          )).overrideWith((ref) async => <ClubRankRow>[]),
          // 详情页顶部现在会读一次 /access/me 判「管理」tab 可见性(小程序同)。
          // 不给替身就会打真网络留下 pending timer。默认停在 posts,管理体不渲染,
          // 图不受影响;权限空 → 非主理人不显 tab,主理人仍靠 isOwner 显 tab。
          clubAccessProvider(3).overrideWith(
            (ref) async => const ClubAccess(
              active: true,
              clubId: 3,
              permissions: <String>{},
              roleCodes: <String>[],
            ),
          ),
        ], const ClubDetailPage(clubId: 3)),
        goldenPath,
      );
    });
  }

  clubCase(
    '未加入',
    'goldens/page_club_detail_notjoined.png',
    <String, dynamic>{},
  );
  clubCase('已加入', 'goldens/page_club_detail_joined.png', <String, dynamic>{
    'isJoined': true,
  });
  clubCase('我是主理人', 'goldens/page_club_detail_owner.png', <String, dynamic>{
    'isOwner': true,
    'isJoined': true,
  });
}
