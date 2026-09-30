// 半屏 sheet 的呈现基线:弹窗收回 iOS 原生 + 按原生比例放开高度(cy-popup-native)。
//
// ★ 为什么钉这三张:
//   1. 商家半屏原先自绘一张和页面同色的实色卡片(`bgPage` + radius 20),
//      并在 `maxHeight: 屏高 × 0.78` 上被压矮 —— 那是照小程序(要避让胶囊、
//      要给自绘导航栏留位)量出来的。App 没有那些约束,该高就高。
//      现在材质交给 `CupertinoPopupSurface`(系统弹窗材质),停位对齐
//      SDK sheet 的原生 92%(默认 topGap 0.08)。fixture 刻意给 12 家商家,
//      长到一定撞顶 —— 只有这样 0.78 与 0.92 的差别才会**画在图上**;
//      短内容两张图看起来一样,拍不出结论。
//   2. 编辑帖文 / 编辑记录两张:唯一的可点出口必须看得见。
//      编辑帖文是 `enableDrag: false`,而 `CupertinoSheetRoute` 的遮罩点不动
//      (`barrierDismissible => false`)—— 没有「取消」就只剩「保存成功」一条路。
//      门禁只能证明按钮**在**,这张图证明它**看得见、位置对**。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_club_sheet_golden_test.dart

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/models/club_director.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_director_controller.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/club/club_topic_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 1, nickname: '我', avatar: '', role: 'player'),
    initialized: true,
  );
}

/// 导演台在图外:这一张钉的是商家半屏的材质与高度。给一个「还没开局」的
/// 网关,让背景里的导演台停在空态,不挂真网络。
class _NoSessionClubDirector implements ClubDirectorGateway {
  @override
  Future<ClubDirectorProjection> loadClubProjection({
    required int activityId,
  }) async {
    throw const GameSessionContractException(
      '未开局',
      reasonCode: 'SESSION_NOT_FOUND',
    );
  }

  @override
  Future<GameSessionReceipt> submitClubCommand(
    GameSessionCommand command,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<GameSessionReceipt> readClubReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) async {
    throw UnimplementedError();
  }
}

/// 主题详情只要两条读:概览(决定四圆钮在不在)+ 招商名单(半屏内容)。
class _FakeTopicOpsApi extends ClubTopicOpsApi {
  _FakeTopicOpsApi({required this.overviewValue, required this.recruitValue})
    : super(_dummyDioClient());

  final ClubTopicOverview overviewValue;
  final RecruitOverview recruitValue;

  @override
  Future<ClubTopicOverview> overview(int topicId) async => overviewValue;

  @override
  Future<ClubTopicManageStats> manageStats({
    required int clubId,
    required int topicId,
    int? activityId,
  }) async => const ClubTopicManageStats(
    canDirect: true,
    canManageSessions: true,
    canViewVerify: true,
    nodeCount: 7,
    sessionHeadcount: 9,
    pendingVerifyCount: 2,
    verifiedByMeCount: 1,
  );

  @override
  Future<RecruitOverview> recruitOverview({
    required int clubId,
    required int topicId,
  }) async => recruitValue;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被这张半屏调用');
}

/// 帖文读接口:编辑提交失败(留在编辑器),历史给 3 版。
class _FakeClubApi implements ClubApi {
  @override
  Future<String> updatePost({
    required int postId,
    required String content,
    required List<String> images,
    required int version,
    required String requestId,
  }) async => throw Exception('版本冲突，请刷新');

  @override
  Future<List<ClubPostRevision>> postHistory(int postId) async =>
      const <ClubPostRevision>[
        ClubPostRevision(
          id: 3,
          snapshotVersion: 3,
          content: '第三版正文',
          createTime: '2026-09-18 20:03',
        ),
        ClubPostRevision(
          id: 2,
          snapshotVersion: 2,
          content: '第二版正文',
          createTime: '2026-09-12 20:02',
        ),
        ClubPostRevision(
          id: 1,
          snapshotVersion: 1,
          content: '第一版正文',
          createTime: '2026-09-05 20:01',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被这两张半屏调用');
}

/// 12 家长名单 —— 短名单在 0.78 和 0.92 下都装得下,拍不出高度差。
RecruitOverview _longRecruit() => RecruitOverview.tryFromJson(<String, dynamic>{
  'nodes': <Map<String, dynamic>>[
    for (int i = 0; i < 12; i++)
      <String, dynamic>{
        'nodeId': i + 1,
        'name': '第 ${i + 1} 站',
        'merchantName': '甲店 $i',
        'phone': '1380000000$i',
        'state': 'ACCEPTED',
      },
  ],
})!;

ClubTopicOverview _overview() =>
    ClubTopicOverview.tryFromJson(<String, dynamic>{
      'id': 12,
      'name': '静安夜行',
      'status': 'running',
      'chapterCount': 2,
      'nodeCount': 7,
      'gameConfiguredCount': 3,
      'storyReady': true,
      'playModeText': '经典定向',
      'startDate': '2026-09-01 19:00:00',
      'endDate': '2026-09-30 22:00:00',
      'sessions': <Map<String, dynamic>>[],
      'activityList': <Map<String, dynamic>>[],
    })!;

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  List<dynamic> overrides,
) async {
  setGoldenViewport(tester, const Size(390, 844));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const ClubPost _post = ClubPost(
  id: 7,
  authorMemberId: 1,
  content: '旧正文',
  version: 3,
);

void main() {
  testWidgets('商家半屏:系统弹窗材质 + 原生 92% 停位', (WidgetTester tester) async {
    await _pump(
      tester,
      ClubTopicDetailPage(clubId: 1, topicId: 12, activityId: 41),
      <dynamic>[
        clubTopicOpsApiProvider.overrideWithValue(
          _FakeTopicOpsApi(
            overviewValue: _overview(),
            recruitValue: _longRecruit(),
          ),
        ),
        clubDirectorApiProvider.overrideWithValue(_NoSessionClubDirector()),
        clubDirectorPendingStoreProvider.overrideWith(
          (ref) => ClubDirectorPendingStore.memory(),
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('topic-detail-quick-merchant')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-merchants-sheet')), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_topic_merchants_sheet.png'),
    );
    // 长名单撞到顶部才说明高度真的放开了:12 行时旧的 0.78 会把尾部截掉。
    expect(
      tester.getTopLeft(find.byKey(const Key('topic-merchants-sheet'))).dy,
      lessThan(844 * 0.10),
      reason: '半屏顶部应停在原生 92% 以内(留白 ≈ 一个状态栏)',
    );
  });

  testWidgets('编辑帖文:顶部有可点的「取消」', (WidgetTester tester) async {
    await _pump(
      tester,
      Scaffold(body: ClubPostTile(post: _post, viewerIsClubAdmin: true)),
      <dynamic>[
        authControllerProvider.overrideWith(_FixedAuth.new),
        clubApiProvider.overrideWithValue(_FakeClubApi()),
      ],
    );

    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-post-edit')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_post_edit_sheet.png'),
    );
    expect(find.byKey(const Key('club-post-edit-cancel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('club-post-edit-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('club-post-edit-input')),
      findsNothing,
      reason: '「取消」必须真的关得掉 —— 这张 sheet 既不能拖也点不动遮罩',
    );
  });

  testWidgets('编辑记录:关闭钉在标题行,任何状态下都点得到', (WidgetTester tester) async {
    await _pump(
      tester,
      Scaffold(body: ClubPostTile(post: _post, viewerIsClubAdmin: true)),
      <dynamic>[
        authControllerProvider.overrideWith(_FixedAuth.new),
        clubApiProvider.overrideWithValue(_FakeClubApi()),
      ],
    );

    await tester.tap(find.byKey(const Key('club-post-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('club-post-history')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/club_post_history_sheet.png'),
    );
    expect(find.byKey(const Key('club-post-history-list')), findsOneWidget);

    await tester.tap(find.byKey(const Key('club-post-history-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('club-post-history-list')), findsNothing);
  });
}
