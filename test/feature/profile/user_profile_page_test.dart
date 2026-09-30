// 他人主页(`/user/:memberId` ↔ 小程序 `pages/userinfo` + `cy-profile viewer=other`)。
//
// ★ 四条判据各自对一条真源:
//   ① 链接里没有 userId → 小程序整页换成 cy-empty(missing-param)+「回到我的主页」,
//      并且**不打任何接口**(拿 0 去问后端只会换来一个看不懂的错误态)。
//   ② 推文那格的赞:小程序打旧路由 `/api/creativesquare/like`,App 侧同一动作走
//      `/api/v1/community/posts/{id}/actions/LIKE`(交接文档 §5.4 的路由换代)。
//   ③ 关于页两块(兴趣标签 / 探索作品):相关字段后端一直在下发、模型也一直在解析,
//      只是没人渲染 —— 判据是「渲染层断了一节」,不是缺接口。
//   ④ 推文空态文案与小程序 cy-empty 逐字一致(主标+副标两行)。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/widgets/cy_net_image.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/api/square_api.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/data/models/square_post.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/profile/user_profile_page.dart';

class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => AuthState(initialized: true);
}

/// 记下有没有人去问「TA 的推文」—— 游客态一次都不该问(那条接口要登录态)。
class _RecordingSquareApi implements SquareApi {
  int listCalls = 0;

  @override
  Future<List<SquarePost>> list({
    int isMy = 0,
    String? keyword,
    int? userId,
    String? cityCode,
    SquareFeedMode feedMode = SquareFeedMode.latest,
    int? cursor,
    int? cursorScore,
    String? topicCode,
    int? communityId,
  }) async {
    listCalls++;
    throw Exception('游客不该打这条必然 401 的社区流接口');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSquareApi implements SquareApi {
  final List<({int id, String action, bool enabled})> actions =
      <({int id, String action, bool enabled})>[];

  @override
  Future<void> setAction(int id, String action, {bool enabled = true}) async {
    actions.add((id: id, action: action, enabled: enabled));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记下有没有人去问「这个人的资料」—— 参数不完整时一次都不该问。
class _RecordingRegistrationApi implements RegistrationApi {
  final List<int> calls;

  _RecordingRegistrationApi(this.calls);

  @override
  Future<ProfileDetail> publicUserInfo(int memberId) async {
    calls.add(memberId);
    throw Exception('参数不完整时不该走到这里');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProfileDetail _profile() => ProfileDetail.fromJson(<String, dynamic>{
  'id': 42,
  'nickname': '小李',
  'avatar': '',
  'introduction': '',
  'followNum': 1,
  'fansNum': 2,
  'likeNum': 3,
  'casePics': 'https://img.example/1.jpg;https://img.example/2.jpg',
  'sysCategoryList': <Map<String, dynamic>>[
    <String, dynamic>{'id': 7, 'categoryName': '咖啡'},
  ],
});

Future<GoRouter> _pump(
  WidgetTester tester, {
  required int memberId,
  ProfileDetail? profile,
  List<SquarePost> posts = const <SquarePost>[],
  _RecordingRegistrationApi? registrationApi,
  SquareApi? squareApi,
  bool loggedIn = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  final GoRouter router = GoRouter(
    initialLocation: '/member',
    routes: <RouteBase>[
      GoRoute(
        path: '/member',
        builder: (_, _) => UserProfilePage(memberId: memberId),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('我的主页面')),
      ),
      GoRoute(
        path: '/square/:postId',
        builder: (_, _) => const Scaffold(body: Text('帖子详情面')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        otherProfileProvider(
          memberId,
        ).overrideWith((ref) async => profile ?? _profile()),
        otherPostsProvider(memberId).overrideWith((ref) async => posts),
        if (registrationApi != null)
          registrationApiProvider.overrideWithValue(registrationApi),
        if (squareApi != null) squareApiProvider.overrideWithValue(squareApi),
        authControllerProvider.overrideWith(
          loggedIn ? _LoggedInAuth.new : _GuestAuth.new,
        ),
      ].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  // ⚠️ 数字断言必须**锚到点赞键上**:同一屏的统计行里也有「获赞 3」这种数字,
  //   裸 find.text('3') 会同时命中它(第一版就是这么假的)。
  Finder likeOf(int postId) => find.byKey(Key('profile-post-like-$postId'));

  String? likeCount(WidgetTester t, int postId) => t
      .widget<Text>(
        find.descendant(of: likeOf(postId), matching: find.byType(Text)),
      )
      .data;

  testWidgets('★ 链接不完整:出小程序那三行文案 + 回到我的主页,且不打接口', (WidgetTester t) async {
    final List<int> asked = <int>[];
    await _pump(
      t,
      memberId: 0,
      registrationApi: _RecordingRegistrationApi(asked),
    );

    expect(find.text('这个主页链接不完整'), findsOneWidget);
    expect(find.text('链接里没有用户信息，暂时无法打开个人主页。'), findsOneWidget);
    expect(asked, isEmpty, reason: '参数都没有,不该拿 0 去问后端');

    await t.tap(find.text('回到我的主页'));
    await t.pumpAndSettle();
    expect(find.text('我的主页面'), findsOneWidget);
  });

  testWidgets('★★ 推文点赞:走社区 actions/LIKE,数字即时变,再点=取消', (WidgetTester t) async {
    final _StubSquareApi api = _StubSquareApi();
    await _pump(
      t,
      memberId: 42,
      squareApi: api,
      posts: <SquarePost>[
        SquarePost(id: 9, memberId: 42, contents: '城市散步日记', likeNum: 3),
      ],
    );

    // ⚠️ CupertinoNavigationBar 的标题会为 Hero 过渡渲两份,所以是 findsWidgets。
    expect(find.text('主页'), findsWidgets, reason: '小程序导航栏标题是「主页」');

    await t.tap(find.byKey(const Key('profile-post-like-9')));
    await t.pumpAndSettle();
    expect(api.actions.single.action, 'LIKE');
    expect(api.actions.single.enabled, isTrue);
    expect(api.actions.single.id, 9);
    expect(likeCount(t, 9), '4', reason: '本地先落预期,不等接口');
    expect(
      find.descendant(
        of: likeOf(9),
        matching: find.byIcon(CupertinoIcons.heart_fill),
      ),
      findsOneWidget,
    );

    await t.tap(find.byKey(const Key('profile-post-like-9')));
    await t.pumpAndSettle();
    expect(api.actions.last.enabled, isFalse, reason: '第二下是取消');
    expect(likeCount(t, 9), '3');
    expect(
      find.descendant(
        of: likeOf(9),
        matching: find.byIcon(CupertinoIcons.heart),
      ),
      findsOneWidget,
    );
  });

  testWidgets('★ 关于页渲染兴趣标签与探索作品(字段一直在下发,之前没人渲染)', (WidgetTester t) async {
    await _pump(t, memberId: 42);

    await t.tap(find.text('关于'));
    await t.pumpAndSettle();
    expect(find.text('兴趣标签'), findsOneWidget);
    expect(find.text('咖啡'), findsOneWidget);
    expect(find.text('探索作品'), findsOneWidget);
    expect(find.byType(CyNetImage), findsNWidgets(2));
  });

  testWidgets('★ 推文空态用小程序原文(主标 + 副标两行)', (WidgetTester t) async {
    await _pump(t, memberId: 42);
    expect(find.text('还没有推文'), findsOneWidget);
    expect(find.text('TA 还没有发布推文'), findsOneWidget);
  });

  // ★★ 游客(P1-1):这条流要登录态(生产实测游客 401),而页面**有意**允许游客
  //    (头部 /api/user/public-info 匿名 200)。所以游客要看到登录出口,
  //    不能是那条「只是这次没取到」+「重试」——重试按多少次都还是 401。
  testWidgets('★★ 游客:推文栏出登录引导,且不发那条必然 401 的请求', (WidgetTester t) async {
    final _RecordingSquareApi api = _RecordingSquareApi();
    await _pump(t, memberId: 42, loggedIn: false, squareApi: api);

    expect(find.text('登录后查看 TA 的动态'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
    expect(find.text('动态没加载出来'), findsNothing, reason: '游客不该看到「重试」那条死路');
    expect(api.listCalls, 0, reason: '游客态一次都不该问 TA 的推文');
  });
}
