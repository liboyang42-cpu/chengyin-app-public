// 社交/商城/俱乐部三个列表页的整页快照。
//
// 这三页此前零 golden 覆盖。fixture 都刻意造成**边界形态**而不是漂亮数据 ——
// 拍一屏理想数据只能证明"顺利时长得不难看",证明不了别的:
//   · 广场:无图纯文字 / 多图 / 超长文案 / 零互动数
//   · 商城:无封面 / 有划线原价 / 售罄
//   · 俱乐部:已加入 / 我是主理人 / 零成员
//
// 更新基准图:flutter test --update-goldens test/golden/pages_social_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/product.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/club/club_list_page.dart';
import 'package:chengyin_app/feature/mall/mall_controller.dart';
import 'package:chengyin_app/feature/mall/product_list_page.dart';
import 'package:chengyin_app/feature/profile/profile_controller.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';
import 'package:chengyin_app/feature/square/square_upcoming_events.dart';
import 'golden_theme.dart';

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

class _GoldenAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

void main() {
  testWidgets('广场:纯文字 / 多图 / 超长文案 / 零互动', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // ★ 广场现在会拉 `/api/official/events` 渲染「即将开始」横滑卡。
        //   不 override 的话这条基线图会依赖一次真实网络 —— widget 测试里
        //   它必然失败,还会留下 pending timer 把 `pumpAndSettle` 拖红。
        //   这条基线图记录的是**帖子卡**的形态,所以这里把它钉成空。
        squareUpcomingCardsProvider.overrideWith(
          (Ref ref) async => const <SquareUpcomingCard>[],
        ),
        squareFeedPageProvider.overrideWith(
          (ref, mode) async => SquareFeedPage(
            items: <SquarePost>[
              SquarePost.fromJson(<String, dynamic>{
                'id': 1,
                'memberId': 11,
                'memberNickname': '阿兰',
                'contents': '今晚静安寺这一段人少得不像周五。',
                'likeNum': 12,
                'commentCount': 3,
                'isLiked': 1,
                'address': '静安寺',
              }),
              // ★ 零互动:三个计数都是 0 —— 不该渲成一排孤零零的「0」
              SquarePost.fromJson(<String, dynamic>{
                'id': 2,
                'memberId': 12,
                'memberNickname': '没人理的一条',
                'contents': '刚发的,还没人看到。',
                'pics': <String>['https://example.invalid/square-list.jpg'],
                'likeNum': 0,
                'commentCount': 0,
                'isLiked': 0,
              }),
              // ★ 超长文案:要能截断,不能把卡片撑爆
              SquarePost.fromJson(<String, dynamic>{
                'id': 3,
                'memberId': 13,
                'memberNickname': '话很多的用户',
                'contents':
                    '这是一段特别特别长的动态文案,用来检验列表卡片在遇到'
                    '长文时会不会把整张卡撑爆、会不会挤掉下面的互动行、'
                    '省略号出现的位置对不对,以及行高在多行状态下读起来是否还舒服。',
                'likeNum': 128,
                'commentCount': 41,
              }),
              // ★ 没有昵称:头像不该渲成兜底文案的第一个字
              SquarePost.fromJson(<String, dynamic>{
                'id': 4,
                'memberId': 14,
                'contents': '匿名发的一条。',
                'likeNum': 1,
              }),
            ],
            hasMore: false,
          ),
        ),
      ], const SquareListPage()),
      'goldens/page_square_list.png',
    );
  });

  testWidgets('广场:即将开始横滑卡(多场露出下一张)', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        squareUpcomingCardsProvider.overrideWith(
          (Ref ref) async => const <SquareUpcomingCard>[
            SquareUpcomingCard(
              eventId: 101,
              title: '城市夜跑·静安线',
              sub: '静安寺集合',
              countdown: '2 小时后开始',
              avatars: <String>[],
              overflow: 0,
            ),
            SquareUpcomingCard(
              eventId: 102,
              title: '苏州河晨跑',
              sub: '上海',
              countdown: '5 小时后开始',
              avatars: <String>[],
              overflow: 0,
            ),
            SquareUpcomingCard(
              eventId: 103,
              title: '世纪公园接力',
              sub: '浦东',
              countdown: '1 天后开始',
              avatars: <String>[],
              overflow: 0,
            ),
          ],
        ),
        squareFeedPageProvider.overrideWith(
          (ref, mode) async => SquareFeedPage(
            items: <SquarePost>[
              SquarePost.fromJson(<String, dynamic>{
                'id': 1,
                'memberId': 11,
                'memberNickname': '阿兰',
                'contents': '今晚静安寺这一段人少得不像周五。',
                'likeNum': 12,
                'commentCount': 3,
                'isLiked': 1,
              }),
            ],
            hasMore: false,
          ),
        ),
      ], const SquareListPage()),
      'goldens/page_square_upcoming_track.png',
    );
  });

  testWidgets('商城:无封面 / 划线原价 / 售罄', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        productListProvider.overrideWith(
          (ref) async => <Product>[
            Product.fromJson(<String, dynamic>{
              'id': 1,
              'productName': '城瘾联名帆布包',
              'price': 8900,
              'originalPrice': 12900,
              'stock': 42,
            }),
            // ★ 售罄:价格还在,但不该看起来像能买
            Product.fromJson(<String, dynamic>{
              'id': 2,
              'productName': '限量徽章(已售罄)',
              'price': 3900,
              'stock': 0,
            }),
            // ★ 无封面 + 超长品名
            Product.fromJson(<String, dynamic>{
              'id': 3,
              'productName': '一个名字特别长的周边商品用来检验两行截断与价格行对齐',
              'price': 19900,
              'stock': 7,
            }),
          ],
        ),
      ], const ProductListPage()),
      'goldens/page_product_list.png',
    );
  });

  testWidgets('俱乐部列表:已加入 / 我是主理人 / 零成员', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // ★ 首页现在是**分段**的:我创建的 / 我加入的 / 附近发现 / 俱乐部活动。
        //   原来这里覆盖的是扁平的 clubListProvider,页面早已不看它了 ——
        //   覆盖一个没人读的 provider,页面会落到真网络、骨架屏无限转,
        //   pumpAndSettle 直接超时。
        clubHomeProvider.overrideWith(
          (ref) async => ClubHome(
            owned: <Club>[
              Club.fromJson(<String, dynamic>{
                'id': 2,
                'name': '我自己开的团',
                'description': '主理人视角应该和普通成员看到的不一样。',
                'memberCount': 6,
                'isOwner': true,
              }),
            ],
            joined: <Club>[
              Club.fromJson(<String, dynamic>{
                'id': 1,
                'name': '城市夜骑俱乐部',
                'description': '每周三晚八点,从静安寺出发。',
                'memberCount': 128,
                'isJoined': true,
                'city': '上海',
              }),
            ],
            nearby: <Club>[
              // ★ 零成员:刚建的团 —— 「0 位成员」要说得出口,不能空着
              Club.fromJson(<String, dynamic>{
                'id': 3,
                'name': '还没人加入的新团',
                'memberCount': 0,
              }),
            ],
            events: const <ClubHomeEvent>[
              ClubHomeEvent(id: 9, title: '周末城南夜骑', cover: null, clubId: 2),
            ],
          ),
        ),
        clubFeedProvider.overrideWith((ref) async => const ClubFeed()),
        // 36e0370b 起 ClubListPage 会 watch 站内消息未读角标;不覆盖就打真
        // IM 接口,留一个 pending timer → teardown 报「Timer is still pending」。
        unreadTotalProvider.overrideWith((ref) async => 0),
        authControllerProvider.overrideWith(_GoldenAuthController.new),
      ], const ClubListPage()),
      'goldens/page_club_list.png',
    );
  });
}
