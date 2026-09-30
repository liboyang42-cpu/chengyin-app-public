// 俱乐部详情页「开放设置」板块(open-settings 三条端点的 App 落点)的负控门。
//
// 判据对齐小程序 pages/club/detail(@90e66d70):
//   - 三个开关只有主理人看得见、改得动(非主理人整段不画);
//   - 每个开关各写各的端点;写完**回读服务端给的值**再渲染 ——
//     界面上那个「已开启/已关闭」要么是库里的事实,要么是一条明说没保存成的错误;
//   - 服务端回读与点的不一样时明说,不假装点成了。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/models/coop_invite_row.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/coop/coop_list_page.dart'
    show coopInviteListProvider;
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/data/models/club_settlement.dart';
import 'package:chengyin_app/data/models/club_stats.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_detail_page.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

Club _club({
  bool isOwner = true,
  Object? publicVisible = 0,
  Object? memberPostAllowed = 1,
  Object? merchantUndertakeOpen = 1,
}) => Club.fromJson(<String, dynamic>{
  'id': 7,
  'name': '夜行社',
  'isOwner': isOwner,
  'isJoined': true,
  'publicVisible': publicVisible,
  'memberPostAllowed': memberPostAllowed,
  'merchantUndertakeOpen': merchantUndertakeOpen,
});

class _FakeClubTopicOpsApi extends ClubTopicOpsApi {
  _FakeClubTopicOpsApi() : super(_dummyDioClient());

  final List<Map<String, dynamic>> toggles = <Map<String, dynamic>>[];
  Object? toggleError;
  ClubOpenSettingValue Function(String key, bool enabled)? resultBuilder;

  Future<ClubOpenSettingValue> _toggle(
    String key,
    int clubId,
    bool enabled,
  ) async {
    toggles.add(<String, dynamic>{
      'key': key,
      'clubId': clubId,
      'enabled': enabled,
    });
    if (toggleError != null) throw toggleError!;
    final ClubOpenSettingValue Function(String, bool)? builder = resultBuilder;
    if (builder != null) return builder(key, enabled);
    return ClubOpenSettingValue(key: key, enabled: enabled);
  }

  @override
  Future<ClubOpenSettingValue> setPublicVisible({
    required int clubId,
    required bool enabled,
  }) => _toggle('publicVisible', clubId, enabled);

  @override
  Future<ClubOpenSettingValue> setMemberPost({
    required int clubId,
    required bool enabled,
  }) => _toggle('memberPost', clubId, enabled);

  @override
  Future<ClubOpenSettingValue> setMerchantCoop({
    required int clubId,
    required bool enabled,
  }) => _toggle('merchantCoop', clubId, enabled);
}

Future<void> _reveal(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  final Finder scrollableFinder = find.byType(Scrollable).first;
  final ScrollPosition position = tester
      .state<ScrollableState>(scrollableFinder)
      .position;

  void jump(double delta) {
    position.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  for (int pass = 0; pass < 2 && target.evaluate().isEmpty; pass += 1) {
    if (pass == 1) {
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
    }
    for (int step = 0; step < 40 && target.evaluate().isEmpty; step += 1) {
      final double before = position.pixels;
      jump(400);
      await tester.pumpAndSettle();
      if (position.pixels == before) break;
    }
  }
  if (target.evaluate().isEmpty) return;
  for (int step = 0; step < 10; step += 1) {
    final Rect viewport = tester.getRect(scrollableFinder);
    final Rect rect = tester.getRect(target);
    if (rect.top >= viewport.top + 8 && rect.bottom <= viewport.bottom - 8) {
      break;
    }
    jump(
      rect.top < viewport.top + 8
          ? rect.top - viewport.top - 60
          : rect.bottom - viewport.bottom + 60,
    );
    await tester.pumpAndSettle();
  }
}

Finder _switchIn(Key rowKey) => find.descendant(
  of: find.byKey(rowKey),
  matching: find.byType(CupertinoSwitch),
);

Future<void> _pumpManage(
  WidgetTester tester, {
  required Club club,
  required _FakeClubTopicOpsApi fake,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        clubDetailProvider(club.id).overrideWith((ref) async => club),
        clubPostsProvider(club.id).overrideWith((ref) async => <ClubPost>[]),
        clubMembersProvider(
          club.id,
        ).overrideWith((ref) async => <ClubMember>[]),
        clubTopicsProvider(club.id).overrideWith((ref) async => <ClubTopic>[]),
        clubLeaderboardProvider((
          clubId: club.id,
          sort: ClubRankSort.composite,
        )).overrideWith((ref) async => <ClubRankRow>[]),
        clubCoopMerchantsProvider(
          club.id,
        ).overrideWith((ref) async => <Map<String, dynamic>>[]),
        clubOwnerProjectsProvider(
          club.id,
        ).overrideWith((ref) async => <MyProject>[]),
        // 阶段机还要读一次发出邀约(/api/coop/list);不 override 同样会打真网络。
        coopInviteListProvider.overrideWith(
          (ref) async => const CoopInviteList(),
        ),
        // 管理 tab 里那三格(客户数 / 分润 / 看板)各取一次数;
        // 不 override 就会去打真网络,pumpAndSettle 直接超时。
        clubCustomerCountProvider(club.id).overrideWith((ref) async => 0),
        clubSettlementSummaryProvider(club.id).overrideWith(
          (ref) async => const ClubSettlementSummary(
            settledAmountText: '¥0.00',
            settledAmountStatus: 'verified',
            unverifiedSettledCount: 0,
            pendingAdjustment: null,
            topics: <ClubSettlementTopic>[],
          ),
        ),
        clubStatsProvider(club.id).overrideWith(
          (ref) async => ClubStats(
            clubId: club.id,
            topicCount: 0,
            participants: 0,
            completed: 0,
            overallRate: 0,
            topics: const <ClubTopicStats>[],
          ),
        ),
        clubTopicOpsApiProvider.overrideWithValue(fake),
      ].cast(),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        debugShowCheckedModeBanner: false,
        home: ClubDetailPage(clubId: club.id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.text('管理').evaluate().isNotEmpty) {
    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('主理人:三个开关都在,值来自俱乐部回执(0/1 → 关/开)', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi();
    await _pumpManage(tester, club: _club(), fake: fake);

    await _reveal(tester, const Key('club-open-public-visible'));
    expect(find.text('开放设置'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoSwitch>(
            _switchIn(const Key('club-open-public-visible')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<CupertinoSwitch>(
            _switchIn(const Key('club-open-member-post')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CupertinoSwitch>(
            _switchIn(const Key('club-open-merchant-coop')),
          )
          .value,
      isTrue,
    );
    expect(fake.toggles, isEmpty, reason: '读不写');
  });

  testWidgets('非主理人:整段不画,不给只读开关', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi();
    await _pumpManage(tester, club: _club(isOwner: false), fake: fake);

    expect(find.text('开放设置'), findsNothing);
    expect(find.byKey(const Key('club-open-public-visible')), findsNothing);
  });

  testWidgets('拨公开可见:写 public-visible 端点,值取反,写完回读', (
    WidgetTester tester,
  ) async {
    final fake = _FakeClubTopicOpsApi();
    await _pumpManage(tester, club: _club(), fake: fake);
    await _reveal(tester, const Key('club-open-public-visible'));

    await tester.tap(_switchIn(const Key('club-open-public-visible')));
    await tester.pumpAndSettle();

    expect(fake.toggles, hasLength(1));
    expect(fake.toggles.single, <String, dynamic>{
      'key': 'publicVisible',
      'clubId': 7,
      'enabled': true,
    });
  });

  testWidgets('拨允许成员发帖:写 member-post 端点,值取反,写完回读', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi();
    await _pumpManage(tester, club: _club(), fake: fake);
    await _reveal(tester, const Key('club-open-member-post'));

    await tester.tap(_switchIn(const Key('club-open-member-post')));
    await tester.pumpAndSettle();

    expect(fake.toggles, hasLength(1));
    expect(fake.toggles.single, <String, dynamic>{
      'key': 'memberPost',
      'clubId': 7,
      'enabled': false,
    });
  });

  testWidgets('存不上:明说没保存成 + 给重试,不把开关留在新位置', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi()
      ..toggleError = ClubApiException('当前岗位没有这个权限');
    await _pumpManage(tester, club: _club(), fake: fake);
    await _reveal(tester, const Key('club-open-merchant-coop'));

    await tester.tap(_switchIn(const Key('club-open-merchant-coop')));
    await tester.pumpAndSettle();

    expect(find.textContaining('开关没有保存成功：当前岗位没有这个权限'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoSwitch>(
            _switchIn(const Key('club-open-merchant-coop')),
          )
          .value,
      isTrue,
      reason: '写失败不假装关掉了',
    );

    // 重试还是同一条端点、同一个目标值。
    fake.toggleError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(fake.toggles, hasLength(2));
    expect(fake.toggles.last['key'], 'merchantCoop');
    expect(fake.toggles.last['enabled'], isFalse);
  });

  testWidgets('服务端回读与点的不一样:说清楚,不假装点成了', (WidgetTester tester) async {
    final fake = _FakeClubTopicOpsApi()
      ..resultBuilder = (String key, bool enabled) =>
          ClubOpenSettingValue(key: key, enabled: !enabled);
    await _pumpManage(tester, club: _club(), fake: fake);
    await _reveal(tester, const Key('club-open-member-post'));

    await tester.tap(_switchIn(const Key('club-open-member-post')));
    await tester.pumpAndSettle();

    expect(find.textContaining('服务端回读到的是「已开启」'), findsOneWidget);
  });
}
