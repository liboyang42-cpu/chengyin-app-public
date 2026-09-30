// a1 收口 · 发布/创作域接线测试(盘点 gap-spec-publish):
//   ① /publish/pro 解析并生效 ?scope=MERCHANT(盘点行 1369/1357/1356);
//   ② 俱乐部「编辑主题」按编辑器现契约传 ?id=(盘点行 1351,不再复刻真源 bug);
//   ③ AI 方案交接草稿的 clubId 不再被编辑器丢弃(盘点行 1350);
//   ④ 本地草稿自动保存移植(盘点行 1370-1373):保存→杀进程重进→恢复、
//      memberId 防串号、服务端版本冲突三问。

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/route_paths.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/data/models/merchant_marketing.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/club/club_ai_design_sheet.dart';
import 'package:chengyin_app/feature/club/club_topic_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_marketing_page.dart';
import 'package:chengyin_app/feature/publish/pro_editor_draft_store.dart';
import 'package:chengyin_app/feature/publish/publish_pro_page.dart';

import '../../support/fake_publisher_identity.dart';

/// 内存版密钥链:测试要能直接看桶内容(杀进程 = 新建页面实例、不换这张 map)。
class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map<String, String>.of(values);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.clear();
}

class _FixedAuth extends AuthController {
  _FixedAuth(this._state);
  final AuthState _state;
  @override
  AuthState build() => _state;
}

class _FakeClubApi extends ClubApi {
  _FakeClubApi() : super(_dio());
  @override
  Future<List<Club>> my() async => <Club>[];
}

class _FakePublishApi extends PublishApi {
  _FakePublishApi() : super(_dio());

  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];
  String? lastEditDetailScope;
  String editBaseRevision = '';

  @override
  Future<(PublishDraft, PublishEditScope)> editDetail(
    int id, {
    String scope = '',
  }) async {
    lastEditDetailScope = scope;
    final draft = PublishDraft()
      ..name = '服务端版主题'
      ..productType = kProductCity
      ..baseRevision = editBaseRevision
      ..tickets = <PublishTicket>[PublishTicket()..name = '早鸟票'];
    return (draft, PublishEditScope.full);
  }

  @override
  Future<List<AiPrecheckIssue>> safetyPrecheck(
    Map<String, dynamic> req,
  ) async => <AiPrecheckIssue>[];

  @override
  Future<int> createTopicPro(Map<String, dynamic> payload) async {
    created.add(payload);
    return 88;
  }
}

class _FakeClubTopicOpsApi extends ClubTopicOpsApi {
  _FakeClubTopicOpsApi() : super(_dio());

  @override
  Future<ClubTopicOverview> overview(int topicId) async =>
      ClubTopicOverview.tryFromJson(<String, dynamic>{
        'id': 12,
        'name': '静安夜行',
        'status': 'preparing',
        'chapterCount': 2,
        'nodeCount': 7,
        'gameConfiguredCount': 3,
        'storyReady': true,
        'playModeText': '经典定向',
        'startDate': '2026-09-01 19:00:00',
        'endDate': '2026-09-30 22:00:00',
        'sessions': <dynamic>[],
        'activityList': <dynamic>[],
      })!;

  @override
  Future<ClubTopicManageStats> manageStats({
    required int clubId,
    required int topicId,
    int? activityId,
  }) async => ClubTopicManageStats(
    canDirect: true,
    canManageSessions: true,
    canViewVerify: true,
    nodeCount: 7,
    sessionHeadcount: 9,
    pendingVerifyCount: 2,
    verifiedByMeCount: 1,
  );

  @override
  Future<TopicSetting> settingDetail({
    required int clubId,
    required int topicId,
  }) async => TopicSetting(
    topicName: '静安夜行',
    lifecycleText: '准备中 · 9月1日开跑',
    coopOpen: false,
    pinned: true,
    memberOnly: false,
    canManage: true,
    chapters: const <TopicSettingChapter>[],
  );
}

DioClient _dio() => DioClient(TokenStore(const FlutterSecureStorage()));

AuthState _authed(int id) => AuthState(
  user: User(id: id, nickname: '阿兰', avatar: '', role: 'player'),
  initialized: true,
);

late _MemoryStorage _storage;

List<dynamic> _overrides({required _FakePublishApi api, int userId = 1}) =>
    <dynamic>[
      authControllerProvider.overrideWith(() => _FixedAuth(_authed(userId))),
      clubApiProvider.overrideWithValue(_FakeClubApi()),
      publishApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_storage),
      // main RUN-52(#463)后「检查并发布」先过发布者实名闸:本用例测的是
      // clubId/scope 透传,不是实名闸 —— 按「已登记」直通。
      publisherIdentityApiProvider.overrideWithValue(
        FakePublisherIdentityApi(registered: true),
      ),
    ];

Widget _wrap(Widget home, List<dynamic> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(home: home),
);

Future<void> _settleAutosave(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 100));
}

String _draftName(WidgetTester tester) => tester
    .widget<CupertinoTextField>(find.byKey(const Key('publish-pro-name')))
    .controller!
    .text;

Map<String, dynamic> _stateWith({required String name, int productType = 1}) =>
    (PublishDraft()
          ..name = name
          ..productType = productType
          ..tickets = <PublishTicket>[PublishTicket()..name = '早鸟票'])
        .toDraftState();

void main() {
  setUp(() {
    _storage = _MemoryStorage();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('scope 生效(盘点 1369/1357)', () {
    testWidgets('merchantScope=true:edit-detail 带 scope=MERCHANT', (
      WidgetTester tester,
    ) async {
      final api = _FakePublishApi();
      await tester.pumpWidget(
        _wrap(
          PublishProPage(topicId: 5, merchantScope: true),
          _overrides(api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.lastEditDetailScope, 'MERCHANT');
    });

    testWidgets('不传 scope 时走玩家空串(不误伤个人链路)', (WidgetTester tester) async {
      final api = _FakePublishApi();
      await tester.pumpWidget(
        _wrap(PublishProPage(topicId: 5), _overrides(api: api)),
      );
      await tester.pumpAndSettle();
      expect(api.lastEditDetailScope, '');
    });

    test('路由参数口径:scope/draftUuid 生效,id 只认 id=', () {
      // 与 app_router `/publish/pro` 同款解析。
      final uri = Uri.parse('/publish/pro?scope=MERCHANT&draftUuid=abc');
      final proPage = PublishProPage(
        topicId: publishEditTopicId(uri),
        merchantScope: uri.queryParameters['scope'] == 'MERCHANT',
        resumeDraftUuid: uri.queryParameters['draftUuid'],
      );
      expect(proPage.merchantScope, isTrue);
      expect(proPage.resumeDraftUuid, 'abc');
      expect(proPage.topicId, isNull);
      // 编辑器契约不变:只认 id=。
      expect(publishEditTopicId(Uri.parse('/publish/pro?id=11')), 11);
      expect(publishEditTopicId(Uri.parse('/publish/pro?topicId=11')), isNull);
    });
  });

  group('本地草稿自动保存(盘点 1370-1373)', () {
    test('存储层:保存→读取→删除;跨账号拒恢复;版本冲突可判', () async {
      final store = ProEditorDraftStore(_storage);
      const identity = ProEditorDraftIdentity(draftUuid: 'u1');

      expect(
        await store.save(
          identity: identity,
          memberId: '1',
          state: _stateWith(name: '夜行'),
          baseRevision: 'r1',
        ),
        isTrue,
      );
      final hit = await store.load(
        identity: identity,
        memberId: '1',
        currentBaseRevision: 'r1',
      );
      expect(hit.status, kProEditorDraftStatusReady);
      expect(hit.envelope!.state['name'], '夜行');
      expect(await store.activeNewDraftUuid('1'), 'u1');

      final stolen = await store.load(identity: identity, memberId: '2');
      expect(stolen.status, kProEditorDraftStatusMemberMismatch);
      expect(stolen.envelope, isNull);

      final conflict = await store.load(
        identity: identity,
        memberId: '1',
        currentBaseRevision: 'r2',
      );
      expect(conflict.status, kProEditorDraftStatusConflict);
      expect(conflict.envelope, isNotNull);

      expect(await store.remove(identity: identity, memberId: '1'), isTrue);
      final gone = await store.load(identity: identity, memberId: '1');
      expect(gone.status, kProEditorDraftStatusMissing);
      expect(await store.activeNewDraftUuid('1'), isEmpty);
    });

    test('草稿态序列化无损:章节/故事块/票/俱乐部全回来', () {
      final d = PublishDraft()
        ..name = '河边的风'
        ..subtitle = '副'
        ..description = '介'
        ..categoryIds = <int>[3, 4]
        ..categoryNames = <String>['悬疑', '夜行']
        ..productType = kProductCity
        ..clubId = 9
        ..collaboratorIds = <int>[1, 2]
        ..publishToCreative = true
        ..recruitDeadline = '2026-09-30 12:00:00';
      final chapter = PublishChapter()
        ..name = '第一章'
        ..localId = 'c1'
        ..audioUrl = 'a.m4a'
        ..allowedValidationMethods = '1,3'
        ..nodes = <PublishNode>[
          PublishNode()
            ..name = '节点'
            ..templateId = 7
            ..templateInfo = <String, dynamic>{'hint1': 'x'}
            ..businessTime = '09:00-18:00'
            ..localId = 'c1-n1',
        ];
      chapter.blocks = <StoryBlock>[
        StoryBlock.text('b1', '开场'),
        StoryBlock.node('b2', 'c1-n1'),
        StoryBlock.image('b3', 'i.jpg'),
        StoryBlock.audio('b4', 's.m4a'),
      ];
      d.chapters = <PublishChapter>[chapter];
      d.tickets = <PublishTicket>[
        PublishTicket()
          ..name = '早鸟'
          ..price = 0
          ..saleStartTime = '2026-09-28'
          ..syncWithTheme = true,
      ];

      final r = PublishDraft.fromDraftState(d.toDraftState());
      expect(r.name, '河边的风');
      expect(r.categoryIds, <int>[3, 4]);
      expect(r.categoryNames, <String>['悬疑', '夜行']);
      expect(r.clubId, 9);
      expect(r.publishToCreative, isTrue);
      expect(r.recruitDeadline, '2026-09-30 12:00:00');
      final rc = r.chapters.single;
      expect(rc.audioUrl, 'a.m4a');
      expect(rc.allowedValidationMethods, '1,3');
      expect(rc.nodes.single.templateInfo['hint1'], 'x');
      expect(rc.nodes.single.businessTime, '09:00-18:00');
      expect(rc.blocks!.map((b) => b.type).toList(), <String>[
        'text',
        'node',
        'image',
        'audio',
      ]);
      expect(rc.blocks![1].nodeKey, 'c1-n1');
      expect(r.tickets.single.price, 0);
      expect(r.tickets.single.syncWithTheme, isTrue);
    });

    testWidgets('保存→杀进程重进→恢复:active 桶自动续写', (WidgetTester tester) async {
      final api = _FakePublishApi();
      await tester.pumpWidget(
        _wrap(
          PublishProPage(key: const ValueKey('run1')),
          _overrides(api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('publish-pro-name')),
        '苏州河夜走',
      );
      await _settleAutosave(tester);

      final uuid = await ProEditorDraftStore(_storage).activeNewDraftUuid('1');
      expect(uuid, isNotEmpty);
      expect(
        _storage.values[ProEditorDraftIdentity(draftUuid: uuid).storageKey!],
        contains('苏州河夜走'),
      );

      // 杀进程重进:同一账号再次新建 → 恢复并提示。
      await tester.pumpWidget(
        _wrap(
          PublishProPage(key: const ValueKey('run2')),
          _overrides(api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已恢复上次本地草稿'), findsOneWidget);
      expect(_draftName(tester), '苏州河夜走');
    });

    testWidgets('草稿属于其他账号:不恢复,新建桶并明说', (WidgetTester tester) async {
      final store = ProEditorDraftStore(_storage);
      await store.save(
        identity: const ProEditorDraftIdentity(draftUuid: 'old'),
        memberId: '999',
        state: _stateWith(name: '别人的草稿'),
      );
      _storage.values['pro_editor_active_1'] = 'old';
      await tester.pumpWidget(
        _wrap(PublishProPage(), _overrides(api: _FakePublishApi())),
      );
      await tester.pumpAndSettle();
      expect(find.text('草稿属于其他账号，已新建草稿'), findsOneWidget);
      expect(_draftName(tester), isEmpty);
    });

    testWidgets('编辑态版本冲突:问「用本地草稿覆盖」,选本地则恢复', (WidgetTester tester) async {
      final store = ProEditorDraftStore(_storage);
      await store.save(
        identity: const ProEditorDraftIdentity(topicId: '5'),
        memberId: '1',
        state: _stateWith(name: '本地更深的内容'),
        baseRevision: 'r1',
      );
      final api = _FakePublishApi()..editBaseRevision = 'r2';
      await tester.pumpWidget(
        _wrap(PublishProPage(topicId: 5), _overrides(api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('服务端草稿已更新'), findsOneWidget);
      await tester.tap(find.text('使用本地草稿'));
      await tester.pumpAndSettle();
      expect(_draftName(tester), '本地更深的内容');
    });

    testWidgets('编辑态版本冲突:选服务端则删本地桶', (WidgetTester tester) async {
      final store = ProEditorDraftStore(_storage);
      await store.save(
        identity: const ProEditorDraftIdentity(topicId: '5'),
        memberId: '1',
        state: _stateWith(name: '本地草稿'),
        baseRevision: 'r1',
      );
      final api = _FakePublishApi()..editBaseRevision = 'r2';
      await tester.pumpWidget(
        _wrap(PublishProPage(topicId: 5), _overrides(api: api)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用服务端版本'));
      await tester.pumpAndSettle();
      expect(
        _storage.values[ProEditorDraftIdentity(topicId: '5').storageKey!],
        isNull,
        reason: '选了服务端版本,本地信封必须作废(真源 removeDraft 同款)',
      );
    });
  });

  group('AI 方案 clubId 透传(盘点 1350)', () {
    test('toPublishDraft 带 clubId', () {
      final draft = (ClubAiDesign.tryParse(<String, dynamic>{
        'plan': '沿苏州河夜跑',
        'nodes': <dynamic>[
          <String, dynamic>{
            'name': '起点',
            'address': '外滩',
            'longitude': '121.49',
            'latitude': '31.24',
            'order': 1,
          },
        ],
      }))!.toPublishDraft(clubId: 42);
      expect(draft.clubId, 42);
    });

    testWidgets('编辑器消费交接草稿时保留 clubId,发布载荷带 clubId+scope', (
      WidgetTester tester,
    ) async {
      final seed = PublishDraft()
        ..name = '夜方案'
        ..productType = kProductCity
        ..clubId = 42
        ..categoryIds = <int>[1]
        ..imgUrl = 'c.jpg'
        ..description = '介绍'
        ..startDate = '2026-10-01'
        ..endDate = '2026-10-02'
        ..tickets = <PublishTicket>[
          PublishTicket()
            ..name = '票'
            ..price = 10
            ..meetingPoint = '外滩'
            ..startTime = '2026-10-01'
            ..endTime = '2026-10-02',
        ];
      seed.chapters.add(
        PublishChapter()
          ..name = '第1章'
          ..description = '开场剧情'
          ..nodes = <PublishNode>[
            PublishNode()
              ..name = '点'
              ..description = '桥头旧事'
              ..templateId = 7
              ..longitude = '121.4'
              ..latitude = '31.2',
          ],
      );
      final api = _FakePublishApi();
      await tester.pumpWidget(
        _wrap(
          PublishProPage(initialDraft: seed, merchantScope: true),
          _overrides(api: api),
        ),
      );
      await tester.pumpAndSettle();
      // 一进页就把带 clubId 的草稿落进本地桶(真源 onLoad 末尾 _persistDraftEnvelope
      // 「立刻接力」语义)—— 提交成功后桶会被清,所以这里先断言。
      expect(
        _storage.values.values.join(),
        allOf(contains('clubId'), contains('夜方案')),
      );
      // 真实提交链路:票务页「检查并发布」→ create 载荷(不手搓 payload 假装)。
      await tester.tap(find.text('票务设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查并发布'));
      await tester.pumpAndSettle();
      expect(api.created, hasLength(1));
      expect(api.created.single['clubId'], 42, reason: 'AI 方案的俱乐部归属不能掉');
      expect(api.created.single['scope'], 'MERCHANT');
      // 发布成功 → 本地桶清掉(存上了就没有未保存内容)。
      expect(
        _storage.values.keys.where((k) => k.startsWith('pro_editor_draft_')),
        isEmpty,
      );
    });
  });

  group('俱乐部「编辑主题」参数对齐(盘点 1351)', () {
    testWidgets('更多半屏「编辑主题」跳 ?id=(不再是 topicId=)', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi();
      Uri? landed;
      final router = GoRouter(
        initialLocation: '/t',
        routes: <RouteBase>[
          GoRoute(
            path: '/t',
            builder: (_, _) =>
                const ClubTopicDetailPage(clubId: 1, topicId: 12),
          ),
          GoRoute(
            path: '/publish/pro',
            builder: (context, state) {
              landed = state.uri;
              return const Scaffold(body: Text('编辑器替身'));
            },
          ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(390, 1100));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            clubTopicOpsApiProvider.overrideWithValue(fake),
          ].cast(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-detail-quick-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('topic-setting-edit')));
      await tester.pumpAndSettle();
      expect(landed!.queryParameters['id'], '12');
      expect(landed!.queryParameters.containsKey('topicId'), isFalse);
    });
  });

  group('商家营销中心发布入口(盘点 1356)', () {
    testWidgets('发主题/发自由探索带 scope=MERCHANT', (WidgetTester tester) async {
      final seen = <String>[];
      final router = GoRouter(
        initialLocation: '/m',
        routes: <RouteBase>[
          GoRoute(path: '/m', builder: (_, _) => const MerchantMarketingPage()),
          GoRoute(
            path: '/publish/pro',
            builder: (context, state) {
              seen.add(state.uri.query);
              return const Scaffold(body: Text('编辑器替身'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            merchantMarketingProvider.overrideWith(
              (ref) async => const MerchantMarketing(couponCount: 0),
            ),
          ].cast(),
          child: MaterialApp.router(
            theme: AppTheme.merchantLight(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发主题'));
      await tester.pumpAndSettle();
      expect(seen.single, 'scope=MERCHANT');
      // 替身页没有返回键,直接经 router 退(不走 pageBack 的返回键假设)。
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('发自由探索'));
      await tester.pumpAndSettle();
      expect(seen, <String>['scope=MERCHANT', 'mode=2&scope=MERCHANT']);
    });
  });
}
