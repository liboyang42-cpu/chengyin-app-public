// 帖文作者身份行:实名认证 / 等级 / 身份徽章 / 通知徽章 / 俱乐部归属 / 关注。
//
// 真源:
//   · `components/cy/post-card/index.wxml:22-25`(四个徽章)
//   · `components/cy/post-card/index.wxml:29`(俱乐部,可点)
//   · `pages/square/list/index.js:508-536`(点头像 → 关注 / 访问个人主页)
//   · `pages/square/detail/index.wxml:37`(详情表头「关注」)
//
// ★ 每条都配**负控**:没有这个字段时不许凭空渲染出来 ——
//   否则「徽章出得来」这条断言在字段为空、代码读错 key 时也照样绿。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/square/square_author_identity.dart';
import 'package:chengyin_app/feature/square/square_controller.dart';
import 'package:chengyin_app/feature/square/square_detail_page.dart';
import 'package:chengyin_app/feature/square/square_list_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '我', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _FakeRegistrationApi implements RegistrationApi {
  _FakeRegistrationApi({this.err});
  final Object? err;
  final List<int> followCalls = <int>[];

  @override
  Future<bool> toggleFollow(int followMemberId) async {
    followCalls.add(followMemberId);
    if (err != null) throw err!;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SquarePost _post(Map<String, dynamic> json) =>
    SquarePost.fromJson(<String, dynamic>{'id': 7, 'memberId': 11, ...json});

Widget _wrap(Widget child, List<dynamic> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('作者身份徽章:四个字段各自独立渲染', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        const Scaffold(
          body: SquareAuthorBadges(
            post: SquarePost(
              id: 1,
              memberId: 11,
              memberNickname: '阿兰',
              rz: true,
              memberLevelId: 3,
              authorBadge: '优质创作者',
              noticeBadge: '本周之星',
            ),
          ),
        ),
        const <dynamic>[],
      ),
    );

    expect(find.text('Lv.3'), findsOneWidget);
    expect(find.text('优质创作者'), findsOneWidget);
    expect(find.text('本周之星'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('已实名认证'))
          .getSemanticsData()
          .label,
      '已实名认证',
    );
  });

  test('字段解析:字符串/数字两种写法都认,缺省不当成 0 级', () {
    // ★ 后端这几个字段发过数字也发过字符串;`as num` 撞上字符串会**直接抛**,
    //   一条脏数据能把整页信息流带下水。
    final SquarePost parsed = SquarePost.fromJson(<String, dynamic>{
      'id': 1,
      'memberId': 11,
      'rz': '1',
      'memberLevelId': '3',
      'clubId': '9',
      'authorBadge': '  优质创作者  ',
      'noticeBadge': '',
    });

    expect(parsed.rz, isTrue);
    expect(parsed.memberLevelId, 3);
    expect(parsed.clubId, 9);
    expect(parsed.authorBadge, '优质创作者');
    // 空字符串不是「有徽章」—— 否则会渲出一个空胶囊。
    expect(parsed.noticeBadge, isNull);

    final SquarePost missing = SquarePost.fromJson(<String, dynamic>{
      'id': 2,
      'memberId': 12,
      'memberLevelId': '不是数字',
    });
    expect(missing.memberLevelId, 0);
    expect(missing.clubId, isNull);
    expect(missing.authorBadge, isNull);
  });

  testWidgets('作者身份徽章:字段缺省时一个都不出', (WidgetTester tester) async {
    // 负控:同样的渲染路径,只把四个字段清空 —— 少任何一个断言都会红在这条上。
    await tester.pumpWidget(
      _wrap(
        const Scaffold(
          body: SquareAuthorBadges(
            post: SquarePost(id: 1, memberId: 11, memberNickname: '阿兰'),
          ),
        ),
        const <dynamic>[],
      ),
    );

    expect(find.textContaining('Lv.'), findsNothing);
    expect(find.text('优质创作者'), findsNothing);
    expect(find.text('本周之星'), findsNothing);
    expect(find.bySemanticsLabel('已实名认证'), findsNothing);
    expect(
      SquareAuthorBadges.anyOf(const SquarePost(id: 1, memberId: 11)),
      isFalse,
    );
  });

  testWidgets('俱乐部:有 id 才可点,点了进俱乐部', (WidgetTester tester) async {
    // ★ 判据是「真的落到 /club/9」,不是「有这个按钮」——
    //   按钮在、点了没反应,用户一样进不去。
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SquareClubLink(
                post: _post(<String, dynamic>{'clubName': '静安跑团', 'clubId': 9}),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/club/:id',
          builder: (_, GoRouterState s) =>
              Scaffold(body: Text('俱乐部-${s.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[].cast(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('静安跑团'), findsOneWidget);
    await tester.tap(find.byKey(const Key('square-author-club-link')));
    await tester.pumpAndSettle();

    expect(find.text('俱乐部-9'), findsOneWidget);
    // ★ `context.push` 是命令式跳转,不会改 `routeInformationProvider` 的 uri ——
    //   要读的是当前 matches 的落点,否则这条断言**恒等于**「还在 /」,
    //   跳转其实没生效也照样绿(第一版就是这么写的)。
    expect(
      router.routerDelegate.currentConfiguration.matches
          .map((RouteMatchBase m) => m.matchedLocation)
          .toList(),
      contains('/club/9'),
    );
  });

  testWidgets('俱乐部:只有名字没有 id 时不假装可点', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        SquareClubLink(post: _post(<String, dynamic>{'clubName': '静安跑团'})),
        <dynamic>[],
      ),
    );

    expect(find.text('静安跑团'), findsOneWidget);
    expect(find.byKey(const Key('square-author-club-link')), findsNothing);
    expect(find.byKey(const Key('square-author-club')), findsOneWidget);
  });

  testWidgets('俱乐部:连名字都没有时整行不渲染', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(SquareClubLink(post: _post(<String, dynamic>{})), <dynamic>[]),
    );

    expect(find.byKey(const Key('square-author-club')), findsNothing);
    expect(find.byKey(const Key('square-author-club-link')), findsNothing);
  });

  testWidgets('广场列表卡:徽章挂在昵称后面,俱乐部行也在', (WidgetTester tester) async {
    final _FakeRegistrationApi api = _FakeRegistrationApi();
    await tester.pumpWidget(
      _wrap(const SquareListPage(), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(api),
        squareFeedPageProvider.overrideWith(
          (Ref ref, SquareFeedMode mode) async => SquareFeedPage(
            items: <SquarePost>[
              _post(<String, dynamic>{
                'memberNickname': '阿兰',
                'contents': '一条动态',
                'rz': 1,
                'memberLevelId': 2,
                'clubName': '静安跑团',
              }),
            ],
            hasMore: false,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv.2'), findsOneWidget);
    expect(find.text('静安跑团'), findsOneWidget);
    expect(find.byKey(const Key('square-author-level')), findsOneWidget);
  });

  testWidgets('详情页表头:身份徽章 + 关注按钮都在', (WidgetTester tester) async {
    final _FakeRegistrationApi api = _FakeRegistrationApi();
    await tester.pumpWidget(
      _wrap(const SquareDetailPage(postId: 7), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(api),
        squareDetailProvider(7).overrideWith(
          (Ref ref) async => _post(<String, dynamic>{
            'memberNickname': '阿兰',
            'contents': '一条动态',
            'rz': 1,
            'memberLevelId': 4,
            'authorBadge': '优质创作者',
            'clubName': '静安跑团',
            'clubId': 9,
          }),
        ),
        squareCommentsProvider(7).overrideWith((Ref ref) async => <Comment>[]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lv.4'), findsOneWidget);
    expect(find.text('优质创作者'), findsOneWidget);
    expect(find.text('静安跑团'), findsOneWidget);
    expect(find.byKey(const Key('square-detail-follow')), findsOneWidget);

    await tester.tap(find.byKey(const Key('square-detail-follow')));
    await tester.pumpAndSettle();
    expect(api.followCalls, <int>[11]);
  });

  testWidgets('详情页表头:自己的帖没有关注按钮', (WidgetTester tester) async {
    // 负控:把作者换成当前登录用户(99)→ 关注按钮必须消失。
    await tester.pumpWidget(
      _wrap(const SquareDetailPage(postId: 7), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(_FakeRegistrationApi()),
        squareDetailProvider(7).overrideWith(
          (Ref ref) async => SquarePost.fromJson(<String, dynamic>{
            'id': 7,
            'memberId': 99,
            'memberNickname': '我',
            'contents': '我自己的动态',
          }),
        ),
        squareCommentsProvider(7).overrideWith((Ref ref) async => <Comment>[]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-detail-follow')), findsNothing);
  });

  testWidgets('详情页表头:已关注的帖没有关注按钮', (WidgetTester tester) async {
    // 负控二:作者不是我,但关系是「已关注」(isFollowTheUser = 1)。
    await tester.pumpWidget(
      _wrap(const SquareDetailPage(postId: 7), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(_FakeRegistrationApi()),
        squareDetailProvider(7).overrideWith(
          (Ref ref) async => _post(<String, dynamic>{
            'memberNickname': '阿兰',
            'contents': '一条动态',
            'isFollowTheUser': 1,
          }),
        ),
        squareCommentsProvider(7).overrideWith((Ref ref) async => <Comment>[]),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('square-detail-follow')), findsNothing);
  });

  testWidgets('关注失败:说出来、按钮不消失,还能再点', (WidgetTester tester) async {
    // ★ I2「异步动作三态齐全」的失败态:失败要说出发生了什么,
    //   而且按钮不能因为一次失败就变成「已关注」。
    final _FakeRegistrationApi api = _FakeRegistrationApi(
      err: Exception('关注状态没确认下来'),
    );
    await tester.pumpWidget(
      _wrap(const SquareDetailPage(postId: 7), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(api),
        squareDetailProvider(7).overrideWith(
          (Ref ref) async => _post(<String, dynamic>{
            'memberNickname': '阿兰',
            'contents': '一条动态',
          }),
        ),
        squareCommentsProvider(7).overrideWith((Ref ref) async => <Comment>[]),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-detail-follow')));
    await tester.pumpAndSettle();

    expect(api.followCalls, <int>[11]);
    expect(find.byKey(const Key('square-detail-follow')), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
    expect(find.textContaining('关注状态没确认下来'), findsOneWidget);
  });

  testWidgets('广场列表卡:点头像弹关注 / 访问个人主页,关注会真的调接口', (WidgetTester tester) async {
    final _FakeRegistrationApi api = _FakeRegistrationApi();
    await tester.pumpWidget(
      _wrap(const SquareListPage(), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(api),
        squareFeedPageProvider.overrideWith(
          (Ref ref, SquareFeedMode mode) async => SquareFeedPage(
            items: <SquarePost>[
              _post(<String, dynamic>{
                'memberNickname': '阿兰',
                'contents': '一条动态',
                'isFollowTheUser': 0,
              }),
            ],
            hasMore: false,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-avatar-7')));
    await tester.pumpAndSettle();

    // ★ 必须限定在 action sheet 里:广场的 tab 栏本身就有一个叫「关注」的页签,
    //   `find.text('关注')` 会把它一起数进来 —— 断言就失去意义了。
    Finder inSheet(String label) => find.descendant(
      of: find.byType(CupertinoActionSheet),
      matching: find.text(label),
    );
    expect(inSheet('关注'), findsOneWidget);
    expect(inSheet('访问个人主页'), findsOneWidget);
    await tester.tap(inSheet('关注'));
    await tester.pumpAndSettle();
    expect(api.followCalls, <int>[11]);
  });

  testWidgets('广场列表卡:已关注 / 自己的帖不弹关注项', (WidgetTester tester) async {
    // 负控:真源同一条判断(`isFollowTheUser == 0 && memberId != userId`)。
    final _FakeRegistrationApi api = _FakeRegistrationApi();
    await tester.pumpWidget(
      _wrap(const SquareListPage(), <dynamic>[
        authControllerProvider.overrideWith(_LoggedInAuth.new),
        registrationApiProvider.overrideWithValue(api),
        squareFeedPageProvider.overrideWith(
          (Ref ref, SquareFeedMode mode) async => SquareFeedPage(
            items: <SquarePost>[
              _post(<String, dynamic>{
                'id': 7,
                'memberId': 11,
                'memberNickname': '已关注的人',
                'contents': '一条动态',
                'isFollowTheUser': 1,
              }),
              SquarePost.fromJson(<String, dynamic>{
                'id': 8,
                'memberId': 99,
                'memberNickname': '我自己',
                'contents': '我发的',
              }),
            ],
            hasMore: false,
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    Finder inSheet(String label) => find.descendant(
      of: find.byType(CupertinoActionSheet),
      matching: find.text(label),
    );
    await tester.tap(find.byKey(const Key('square-avatar-7')));
    await tester.pumpAndSettle();
    expect(inSheet('访问个人主页'), findsOneWidget);
    expect(inSheet('关注'), findsNothing);
    await tester.tap(inSheet('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('square-avatar-8')));
    await tester.pumpAndSettle();
    expect(inSheet('访问个人主页'), findsOneWidget);
    expect(inSheet('关注'), findsNothing);
  });
}
