// 招商承接页:哪些按钮该出现、哪些绝不能出现。
//
// ★★ 这一页的核心风险是**摆一个点下去必被服务端拒的按钮** ——
//   本项目反复出现的那类缺陷。三处闸各自对应一道服务端校验:
//     · 已申请过的章节不再摆「申请承接」(会撞「已申请」);
//     · 申请没通过 / 已有生效供给 / 档位读不出来时不摆「填实际供给」;
//     · 已报名过的路线不摆「报名承接」(会撞查重)。
//
// ★ 断言一律锚到 Key,不锚到中文标签 —— 标签会被别处的字撞上。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/api/game_session_api.dart';
import 'package:chengyin_app/data/api/coop_api.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/chapter_application.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/merchant/merchant_game_node_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_state.dart';

const int kTopic = 42;

RecruitChapter perkChapter({int id = 7}) =>
    RecruitChapter.fromJson(<String, dynamic>{
      'id': id,
      'name': '第一章 · 咖啡',
      'category': '咖啡',
      'required': 1,
      'recruitStatus': <String, dynamic>{
        'termsMode': 'PERK',
        'perkMinValue': 30,
        'maxMerchant': 4,
        'remainingMerchantCount': 2,
        'allowedValidationMethods': '1,4',
        'maxNodeXp': 30,
        'state': 'OPEN',
      },
    });

ChapterApplication application({
  int id = 100,
  int chapterId = 7,
  int status = 1,
  int source = 0,
  bool offerActive = false,
  int? offerId,
  String? circleThemeCode,
  String? circleSupplyCheckedAt,
}) =>
    ChapterApplication.fromJson(<String, dynamic>{
      'id': id,
      'topicId': kTopic,
      'chapterId': chapterId,
      'chapterName': '第一章 · 咖啡',
      'status': status,
      'source': source,
      'offerActive': offerActive,
      'offerId': offerId,
      'circleThemeCode': circleThemeCode,
      'circleSupplyCheckedAt': circleSupplyCheckedAt,
    });

/// 圈层供给的两个复核动作各自的端点。★ 只记「发了什么 id」——
/// 打错端点或拿申请 id 去调,后端一律回「缺少供给记录」,而那是**不报错**的失败。
class _FakeCoopApi implements CoopApi {
  final List<int> reconfirmed = <int>[];
  final List<int> paused = <int>[];

  @override
  Future<void> reconfirmCircleSupply(int offerId) async =>
      reconfirmed.add(offerId);

  @override
  Future<void> pauseCircleSupply(int offerId) async => paused.add(offerId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget app(
  RecruitState state, {
  List<UpcomingRun> runs = const <UpcomingRun>[],
  CoopApi? coop,
}) {
  return ProviderScope(
    overrides: [
      merchantRecruitProvider(kTopic).overrideWith((ref) async => state),
      merchantUpcomingRunsProvider(kTopic).overrideWith((ref) async => runs),
      coopApiProvider.overrideWithValue(coop ?? _FakeCoopApi()),
    ],
    child: const MaterialApp(home: MerchantRecruitPage(topicId: kTopic)),
  );
}

void main() {
  group('★★ 自由探索:章节承接', () {
    testWidgets('没申请过的章节摆「申请承接」', (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-chapter-7')), findsOneWidget);
      expect(find.text('申请承接并配置点位'), findsOneWidget);
    });

    testWidgets('★ 已申请过的章节不再摆「申请承接」—— 点了必撞「已申请」',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
        applications: <ChapterApplication>[application(status: 0)],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-chapter-7')), findsOneWidget);
      expect(find.text('申请承接并配置点位'), findsNothing);
    });

    testWidgets('已通过 + 档位读得到 → 给「填实际供给」', (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
        applications: <ChapterApplication>[application()],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-offer-100')), findsOneWidget);
      expect(find.byKey(const Key('recruit-withdraw-100')), findsNothing);
    });

    testWidgets('★★ 已通过但章节档位没读出来 → 不给按钮,并说清为什么',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        // 章节列表里没有 id=7 ⇒ 对不出 termsMode。
        chapters: const <RecruitChapter>[],
        applications: <ChapterApplication>[application()],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-offer-100')), findsNothing,
          reason: '档位不明就提交,服务端会判成档位不合法');
      expect(find.textContaining('承接档位暂时没读出来'), findsOneWidget);
    });

    testWidgets('★ 已有生效供给 → 不给「填实际供给」,改说要先撤回',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
        applications: <ChapterApplication>[application(offerActive: true)],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-offer-100')), findsNothing);
      expect(find.textContaining('实际供给已生效'), findsOneWidget);
    });

    testWidgets('待审核 → 只给撤回', (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
        applications: <ChapterApplication>[application(status: 0)],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-withdraw-100')), findsOneWidget);
      expect(find.byKey(const Key('recruit-offer-100')), findsNothing);
    });

    testWidgets('★ 主办方邀请来的不给商家撤回', (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
        applications: <ChapterApplication>[application(status: 0, source: 1)],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-withdraw-100')), findsNothing);
    });

    testWidgets('点位被驳回时把原因摆出来', (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
        chapters: <RecruitChapter>[perkChapter()],
        nodes: <MyChapterNode>[
          MyChapterNode.fromJson(<String, dynamic>{
            'id': 5,
            'name': '南京西路店',
            'nodeAuditStatus': 2,
            'nodeAuditReason': '门头照太糊',
          }),
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-node-5')), findsOneWidget);
      expect(find.text('驳回原因:门头照太糊'), findsOneWidget);
    });
  });

  group('★★ 经典定向:站点报名', () {
    testWidgets('已报名过 → 不摆报名按钮,给去我的报名', (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.nodeRegistration,
        topicName: '老城厢定向',
        registered: true,
        topicChapters: <TopicChapter>[
          TopicChapter(id: 1, title: '第一章', nodes: <TopicNode>[
            TopicNode(id: 11, name: '第一站'),
          ]),
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-already-registered')), findsOneWidget);
      expect(find.byKey(const Key('recruit-register-button')), findsNothing);
    });

    testWidgets('★★ 查不出报没报过 → 说「没查出来」并仍然放行,不装作没报过',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(RecruitState(
        mode: RecruitMode.nodeRegistration,
        topicName: '老城厢定向',
        registered: null,
        topicChapters: <TopicChapter>[
          TopicChapter(id: 1, title: '第一章', nodes: <TopicNode>[
            TopicNode(id: 11, name: '第一站'),
          ]),
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-registered-unknown')), findsOneWidget);
      expect(find.byKey(const Key('recruit-register-button')), findsOneWidget);
    });

    testWidgets('★ 没有可选站点时不摆报名按钮 —— 点开也选不出东西',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(const RecruitState(
        mode: RecruitMode.nodeRegistration,
        topicName: '老城厢定向',
        registered: false,
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-nodes-empty')), findsOneWidget);
      expect(find.byKey(const Key('recruit-register-button')), findsNothing);
    });
  });

  group('★★ 前置态分流:三种处境不能糊成一句「没开招商」', () {
    testWidgets('品类没配 → 给去完善品类', (WidgetTester tester) async {
      await tester.pumpWidget(app(const RecruitState(
        mode: RecruitMode.categoryMissing,
        topicName: '梧桐区寻味',
        blockedMessage: '请先完善商家品类',
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-blocked-category')), findsOneWidget);
      expect(find.text('去完善品类'), findsOneWidget);
    });

    testWidgets('不是商家 → 给去申请入驻', (WidgetTester tester) async {
      await tester.pumpWidget(app(const RecruitState(
        mode: RecruitMode.notMerchant,
        topicName: '梧桐区寻味',
        blockedMessage: '仅商家可查看章节承接',
      )));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('recruit-blocked-not-merchant')), findsOneWidget);
      expect(find.text('去申请入驻'), findsOneWidget);
    });
  });

  group('★★ 场次:读失败不许渲成空态', () {
    testWidgets('读失败 → 说「没读出来」并给重试,不说「暂时没有场次」',
        (WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          merchantRecruitProvider(kTopic).overrideWith((ref) async =>
              const RecruitState(
                  mode: RecruitMode.chapterRecruit, topicName: '梧桐区寻味')),
          merchantUpcomingRunsProvider(kTopic)
              .overrideWith((ref) async => throw Exception('网络异常')),
        ],
        child: const MaterialApp(home: MerchantRecruitPage(topicId: kTopic)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-runs-error')), findsOneWidget);
      expect(find.byKey(const Key('recruit-runs-empty')), findsNothing,
          reason: '「没加载出来」被说成「没有」,商家会照着它撤掉当天的人手');
    });

    testWidgets('真的没有场次才说没有', (WidgetTester tester) async {
      await tester.pumpWidget(app(const RecruitState(
        mode: RecruitMode.chapterRecruit,
        topicName: '梧桐区寻味',
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-runs-empty')), findsOneWidget);
      expect(find.byKey(const Key('recruit-runs-error')), findsNothing);
    });
  });

  // ── 「本站」入口(真源 merchantinfo.js:2629 goStation)────────────────────
  group('★★ 本站入口:按 topicId 过滤站点,空说空、多先选', () {
    testWidgets('纯浏览者看不到「本站」', (WidgetTester tester) async {
      await tester.pumpWidget(stationApp(
        const RecruitState(
            mode: RecruitMode.chapterRecruit, topicName: '梧桐区寻味'),
        _FakeEntriesGateway(const <MerchantGameEntry>[]),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-station-entry')), findsNothing,
          reason: '还没承接就摆「本站」,点下去只会说「还没开出场次」—— 把「还没有」误报成「就是没有」');
    });

    testWidgets('承接方(报过这条路线)看得到「本站」', (WidgetTester tester) async {
      await tester.pumpWidget(stationApp(
        RecruitState(
          mode: RecruitMode.chapterRecruit,
          topicName: '梧桐区寻味',
          applications: <ChapterApplication>[application()],
        ),
        _FakeEntriesGateway(const <MerchantGameEntry>[]),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-station-entry')), findsOneWidget);
    });

    testWidgets('这条路线没有场次 → 说清楚「还没开出场次」,不跳空页',
        (WidgetTester tester) async {
      await tester.pumpWidget(stationApp(
        RecruitState(
          mode: RecruitMode.chapterRecruit,
          topicName: '梧桐区寻味',
          applications: <ChapterApplication>[application()],
        ),
        _FakeEntriesGateway(<MerchantGameEntry>[
          // 别的路线开了场次 ≠ 这条开了 —— 过滤必须按 topicId。
          MerchantGameEntry(
              activityId: 9, topicId: 7, activityName: '别的路线', stationCount: 2),
        ]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recruit-station-entry')));
      await tester.pumpAndSettle();
      expect(find.text('这条路线还没开出场次'), findsOneWidget);
      expect(find.textContaining('node '), findsNothing);
    });

    testWidgets('只有一个场次 → 直接进 game-node', (WidgetTester tester) async {
      await tester.pumpWidget(stationApp(
        RecruitState(
          mode: RecruitMode.chapterRecruit,
          topicName: '梧桐区寻味',
          applications: <ChapterApplication>[application()],
        ),
        _FakeEntriesGateway(<MerchantGameEntry>[
          MerchantGameEntry(
              activityId: 7, topicId: kTopic, activityName: '首场', stationCount: 2),
        ]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recruit-station-entry')));
      await tester.pumpAndSettle();
      expect(find.text('node 7'), findsOneWidget);
    });

    testWidgets('多个场次 → 先选场次,选了才跳', (WidgetTester tester) async {
      await tester.pumpWidget(stationApp(
        RecruitState(
          mode: RecruitMode.chapterRecruit,
          topicName: '梧桐区寻味',
          applications: <ChapterApplication>[application()],
        ),
        _FakeEntriesGateway(<MerchantGameEntry>[
          MerchantGameEntry(
              activityId: 7, topicId: kTopic, activityName: '首场', stationCount: 2),
          MerchantGameEntry(
              activityId: 8, topicId: kTopic, activityName: '第二场', stationCount: 3),
        ]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recruit-station-entry')));
      await tester.pumpAndSettle();
      expect(find.text('选择场次'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recruit-station-option-8')));
      await tester.pumpAndSettle();
      expect(find.text('node 8'), findsOneWidget);
    });

    testWidgets('入口没读出来 → 报错,不当成「没有场次」', (WidgetTester tester) async {
      await tester.pumpWidget(stationApp(
        RecruitState(
          mode: RecruitMode.chapterRecruit,
          topicName: '梧桐区寻味',
          applications: <ChapterApplication>[application()],
        ),
        _FakeEntriesGateway(const <MerchantGameEntry>[],
            error: Exception('本站入口不可用')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recruit-station-entry')));
      await tester.pumpAndSettle();
      expect(find.text('本站入口不可用'), findsOneWidget);
      expect(find.text('这条路线还没开出场次'), findsNothing);
    });
  });

  // ── 圈层供给复核(真源 merchantinfo.js `reconfirmCircleSupply` / `pauseCircleSupply`)──
  //
  // ★★ 风险同型:这两个动作**打的是供给(offerId),不是申请**,而且只对
  //   圈层供给成立(`offerActive && offerId && circleThemeCode`,与小程序一字不差)。
  //   少一个条件就是摆一个点下去必被后端拒的按钮。
  group('★★ 圈层供给:复核与暂停', () {
    RecruitState circleState(ChapterApplication a) => RecruitState(
      mode: RecruitMode.chapterRecruit,
      topicName: '梧桐区寻味',
      chapters: <RecruitChapter>[perkChapter()],
      applications: <ChapterApplication>[a],
    );

    testWidgets('★ 生效供给 + 圈层编号 → 两个动作都摆,并回显最近确认日期',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(circleState(application(
        offerActive: true,
        offerId: 55,
        circleThemeCode: 'CIRCLE-9',
        circleSupplyCheckedAt: '2026-08-01T10:00:00',
      ))));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('recruit-reconfirm-supply-100')), findsOneWidget);
      expect(find.byKey(const Key('recruit-pause-supply-100')), findsOneWidget);
      expect(find.textContaining('最近确认 2026-08-01'), findsOneWidget);
    });

    testWidgets('★★ 生效但不是圈层供给 → 不摆 —— 点下去必被「缺少供给记录」拒',
        (WidgetTester tester) async {
      await tester.pumpWidget(app(circleState(application(
        offerActive: true,
        offerId: 55,
      ))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recruit-reconfirm-supply-100')), findsNothing);
      expect(find.byKey(const Key('recruit-pause-supply-100')), findsNothing);
      // 日期没给就不缀;但「实际供给已生效」照说 —— 不缀日期 ≠ 从没确认过。
      expect(find.textContaining('最近确认'), findsNothing);
      expect(find.textContaining('实际供给已生效'), findsOneWidget);
    });

    testWidgets('★★ 暂停:先说清后果,确认后发的键是 offerId', (WidgetTester tester) async {
      final _FakeCoopApi coop = _FakeCoopApi();
      await tester.pumpWidget(app(
        circleState(application(
          offerActive: true,
          offerId: 55,
          circleThemeCode: 'CIRCLE-9',
        )),
        coop: coop,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recruit-pause-supply-100')));
      await tester.pumpAndSettle();
      expect(find.text('暂停后不会再进入新的圈层探索；历史记录不会删除。'), findsOneWidget);
      expect(coop.paused, isEmpty, reason: '还没确认就不许发出去');

      await tester.tap(find.text('确认暂停'));
      await tester.pumpAndSettle();
      expect(coop.paused, <int>[55]);
      expect(find.text('供给已暂停'), findsOneWidget);
    });

    testWidgets('★★ 重新确认:不弹表单,直接拿现有快照刷新', (WidgetTester tester) async {
      final _FakeCoopApi coop = _FakeCoopApi();
      await tester.pumpWidget(app(
        circleState(application(
          offerActive: true,
          offerId: 55,
          circleThemeCode: 'CIRCLE-9',
        )),
        coop: coop,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recruit-reconfirm-supply-100')));
      await tester.pumpAndSettle();
      expect(coop.reconfirmed, <int>[55]);
      expect(find.text('已重新确认'), findsOneWidget);
    });
  });
}

class _FakeEntriesGateway implements GameSessionGateway {
  _FakeEntriesGateway(this.entries, {this.error});

  final List<MerchantGameEntry> entries;
  final Object? error;
  int calls = 0;

  @override
  Future<List<MerchantGameEntry>> loadMerchantEntries() async {
    calls++;
    if (error != null) throw error!;
    return entries;
  }

  @override
  Future<MerchantGameProjection> loadMerchantView({required int activityId}) =>
      throw UnimplementedError();

  @override
  Future<GameSessionReceipt> submitAndReadReceipt(GameSessionCommand command) =>
      throw UnimplementedError();

  @override
  Future<GameSessionReceipt> readReceipt({
    required int activityId,
    required String requestId,
    required String expectedAction,
  }) => throw UnimplementedError();
}

Widget stationApp(RecruitState state, GameSessionGateway gateway) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const MerchantRecruitPage(topicId: kTopic),
      ),
      GoRoute(
        path: '/merchant/game-node/:activityId',
        builder: (_, GoRouterState state) =>
            Scaffold(body: Text('node ${state.pathParameters['activityId']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      merchantRecruitProvider(kTopic).overrideWith((ref) async => state),
      merchantUpcomingRunsProvider(kTopic)
          .overrideWith((ref) async => const <UpcomingRun>[]),
      gameSessionApiProvider.overrideWithValue(gateway),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}
