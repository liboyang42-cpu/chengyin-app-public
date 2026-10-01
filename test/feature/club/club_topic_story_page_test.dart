// 剧情与玩法页(topic-story)的负控门:两个 tab 的陈列、主理人看答案的
// 「点 → 请求 → 重试」三段式、没有治理身份时不发请求。
//
// 判据对齐小程序 pages/club/topic-story(@90e66d70):
//   - 陈列源是 `/api/topic/info-to-user` 的玩家公开投影(答案不在里面);
//   - 答案另走 `/api/club/topic-node-answer`(服务端 canGovernClub),
//     只有 1/3 两类玩法卡才有「查看答案」;
//   - 徽标:不可作答的玩法挂「· 无答案」;
//   - 步行段只有章内第二站起才画,拿不到坐标整行不画。

import 'package:flutter/cupertino.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dio/dio.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/club_topic_ops_api.dart';
import 'package:chengyin_app/data/models/club_topic_ops.dart';
import 'package:chengyin_app/feature/club/club_topic_story_page.dart';

Widget _app(Widget home, List<dynamic> overrides, {Locale locale = const Locale('zh')}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

DioClient _dummyDioClient() =>
    DioClient(TokenStore(const FlutterSecureStorage()));

DioException _networkFailure() => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  type: DioExceptionType.connectionError,
);

DioException _forbidden() => DioException(
  requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: RequestOptions(path: '/api/topic/info-to-user'),
    statusCode: 403,
  ),
);

Map<String, dynamic> _templateJson({
  required int id,
  required String title,
  Object? validationMethod,
  String? validationMethodStr,
}) => <String, dynamic>{
  'id': id,
  'title': title,
  if (validationMethod != null) 'validationMethod': validationMethod,
  if (validationMethodStr != null) 'validationMethodStr': validationMethodStr,
};

/// 一份可裁剪的公开投影回执(章节 → 站点 → 模板)。
Map<String, dynamic> _overviewJson({
  String name = '静安夜行',
  List<Map<String, dynamic>> chapters = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': 12,
  'name': name,
  'status': 'preparing',
  'nodeCount': 4,
  'storyReady': true,
  'gameConfiguredCount': 2,
  'chaptersList': chapters,
};

List<Map<String, dynamic>> _twoChapterChapters() => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 1,
    'title': '古城',
    'totalTime': 200,
    'description': '沿着城墙走一圈，把故事一段段捡回来。',
    'nodes': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 11,
        'name': '钟楼',
        'address': '环城西路 1 号',
        'businessTime': '09:00',
        'latitude': 31.2300,
        'longitude': 121.4700,
        'cmsMemberTemplate': _templateJson(
          id: 101,
          title: '登楼答题',
          validationMethod: 1,
        ),
      },
      <String, dynamic>{
        'id': 12,
        'name': '城墙',
        'address': '环城西路 9 号',
        'businessTime': '10:30',
        'latitude': 31.2400,
        'longitude': 121.4800,
        'cmsMemberTemplate': _templateJson(
          id: 102,
          title: '找砖上的字',
          validationMethod: 0,
        ),
      },
    ],
  },
  <String, dynamic>{
    'id': 2,
    'title': '夜市',
    'nodes': <Map<String, dynamic>>[
      <String, dynamic>{'id': 21, 'name': '小吃街'},
    ],
  },
];

/// 记录调用、可挂错误与重试应答的 ClubTopicOpsApi 假实现。
class _FakeClubTopicOpsApi extends ClubTopicOpsApi {
  _FakeClubTopicOpsApi() : super(_dummyDioClient());

  ClubTopicOverview? overviewValue;
  Object? overviewError;
  int overviewCalls = 0;

  final List<Map<String, dynamic>> answerCalls = <Map<String, dynamic>>[];
  final List<Object> answerResponses = <Object>[];

  @override
  Future<ClubTopicOverview> overview(int topicId) async {
    overviewCalls += 1;
    if (overviewError != null) throw overviewError!;
    return overviewValue!;
  }

  @override
  Future<TopicNodeAnswer> nodeAnswer({
    required int clubId,
    required int topicId,
    required int nodeId,
  }) async {
    answerCalls.add(<String, dynamic>{
      'clubId': clubId,
      'topicId': topicId,
      'nodeId': nodeId,
    });
    if (answerResponses.isEmpty) {
      throw ClubApiException('假实现没有准备应答');
    }
    final Object next = answerResponses.removeAt(0);
    if (next is Exception) throw next;
    return next as TopicNodeAnswer;
  }
}

/// 长列表是懒构建的:把目标滚进可见视口中央附近再操作。
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

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeClubTopicOpsApi fake,
  int? clubId = 1,
  Locale locale = const Locale('zh'),
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1100));
  await tester.pumpWidget(
    _app(
      ClubTopicStoryPage(key: ObjectKey(fake), topicId: 12, clubId: clubId),
      <dynamic>[clubTopicOpsApiProvider.overrideWithValue(fake)],
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _switchToPlayTab(WidgetTester tester) async {
  await tester.tap(find.text('玩法'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('English story labels preserve authored names and answer access', (tester) async {
    final fake = _FakeClubTopicOpsApi()
      ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson(chapters: _twoChapterChapters()))!;
    await _pumpPage(tester, fake: fake, clubId: null, locale: const Locale('en'));
    expect(find.text('Story and gameplay'), findsOneWidget);
    expect(find.text('Chapter 1 · 古城'), findsOneWidget);
    expect(find.text('钟楼'), findsOneWidget);
    await tester.tap(find.text('Gameplay'));
    await tester.pumpAndSettle();
    expect(find.text('Chapter story'), findsOneWidget);
    expect(find.text('沿着城墙走一圈，把故事一段段捡回来。'), findsOneWidget);
    await _reveal(tester, const Key('topic-story-answer-11'));
    await tester.tap(find.byKey(const Key('topic-story-answer-11')));
    await tester.pumpAndSettle();
    expect(find.text('Open this page from the club to view answers'), findsOneWidget);
    expect(fake.answerCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  group('topic-story:路线 tab', () {
    testWidgets('章节标题/时长/站点序号与地名,第二站起画步行段', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(chapters: _twoChapterChapters()),
        )!;
      await _pumpPage(tester, fake: fake);

      expect(fake.overviewCalls, 1);
      expect(find.byKey(const Key('topic-story-chapter-1')), findsOneWidget);
      expect(find.byKey(const Key('topic-story-chapter-2')), findsOneWidget);
      expect(find.text('第一章 · 古城'), findsOneWidget);
      expect(find.text('3h 20min · 2 站'), findsOneWidget);
      expect(find.text('钟楼'), findsOneWidget);
      expect(find.text('09:00 · 环城西路 1 号'), findsOneWidget);

      // 步行段只在两站之间画一次,且算不出来就不编数字。
      expect(find.textContaining('步行'), findsOneWidget);

      // 第二站的「4 站」只在路线里数得上,序号跨章连续由契约测试钉住;
      // 这里确认第二站照常出现。
      expect(find.byKey(const Key('topic-story-stop-21')), findsOneWidget);
    });

    testWidgets('空章节 → 空态,不给空白时间轴', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(_overviewJson())!;
      await _pumpPage(tester, fake: fake);

      expect(find.text('还没有章节'), findsOneWidget);
      expect(find.text('这个团还没有排出路线。'), findsOneWidget);
    });

    testWidgets('读不到公开投影:403 按权限拒绝,网络失败按网络态可重试', (WidgetTester tester) async {
      final _FakeClubTopicOpsApi denied = _FakeClubTopicOpsApi()
        ..overviewError = _forbidden();
      await _pumpPage(tester, fake: denied);
      expect(find.text('你看不到这条路线'), findsOneWidget);

      final _FakeClubTopicOpsApi offline = _FakeClubTopicOpsApi()
        ..overviewError = _networkFailure();
      await _pumpPage(tester, fake: offline);
      expect(find.text('网络连接失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('topic-story:玩法 tab', () {
    testWidgets('章节 chip + 剧情折叠 + 玩法卡徽标(可作答/无答案)', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(chapters: _twoChapterChapters()),
        )!;
      await _pumpPage(tester, fake: fake);
      await _switchToPlayTab(tester);

      expect(find.byKey(const Key('topic-story-chip-0')), findsOneWidget);
      expect(find.byKey(const Key('topic-story-chip-1')), findsOneWidget);
      // 剧情默认折叠,点开才给「收起」。
      expect(find.byKey(const Key('topic-story-story-toggle')), findsOneWidget);
      await tester.tap(find.byKey(const Key('topic-story-story-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('收起 ▴'), findsOneWidget);

      // 玩法卡:文字作答有答案;码 0 的挂「· 无答案」且不给「查看答案」。
      expect(find.byKey(const Key('topic-story-play-11')), findsOneWidget);
      expect(find.byKey(const Key('topic-story-play-12')), findsOneWidget);
      expect(find.text('文字作答'), findsOneWidget);
      expect(find.text('无需验证 · 无答案'), findsOneWidget);
      expect(find.byKey(const Key('topic-story-answer-11')), findsOneWidget);
      expect(find.byKey(const Key('topic-story-answer-12')), findsNothing);
      expect(find.text('看看模板'), findsNWidgets(2));

      // 切到第二章:第一章的玩法卡收走。
      await tester.tap(find.byKey(const Key('topic-story-chip-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topic-story-play-11')), findsNothing);
      expect(find.text('这一章还没有玩法'), findsOneWidget);
      // 空态副标逐字取小程序 pages/club/topic-story 的 cy-empty sub。
      expect(find.text('承接商家补齐模板后会出现在这里。'), findsOneWidget);
    });
  });

  group('topic-story:主理人看答案', () {
    testWidgets('点「查看答案」→ nodeAnswer(clubId, topicId, nodeId) → 题面/答案/提示都上屏', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(chapters: _twoChapterChapters()),
        )!
        ..answerResponses.add(
          const TopicNodeAnswer(
            question: '钟楼几层？',
            answerReveal: '七层',
            hints: <String>['数一数窗'],
            feedbackText: '再走近看看',
          ),
        );
      await _pumpPage(tester, fake: fake);
      await _switchToPlayTab(tester);

      await _reveal(tester, const Key('topic-story-answer-11'));
      await tester.tap(find.byKey(const Key('topic-story-answer-11')));
      await tester.pumpAndSettle();

      expect(fake.answerCalls, hasLength(1));
      expect(fake.answerCalls.single, <String, dynamic>{
        'clubId': 1,
        'topicId': 12,
        'nodeId': 11,
      });
      expect(find.byKey(const Key('topic-story-answer-sheet')), findsOneWidget);
      expect(find.text('钟楼几层？'), findsOneWidget);
      final Text reveal = tester.widget<Text>(
        find.byKey(const Key('topic-story-answer-reveal')),
      );
      expect(reveal.data, '七层');
      expect(find.text('1 · 数一数窗'), findsOneWidget);
      expect(find.text('再走近看看'), findsOneWidget);
    });

    testWidgets('答案取不到 → 弹层里给重试,重试成功后才算看到答案', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(chapters: _twoChapterChapters()),
        )!
        ..answerResponses.addAll(<Object>[
          ClubApiException('这个玩法没有答案'),
          const TopicNodeAnswer(
            question: '',
            answerReveal: '1896',
            hints: <String>[],
            feedbackText: '',
          ),
        ]);
      await _pumpPage(tester, fake: fake);
      await _switchToPlayTab(tester);

      await _reveal(tester, const Key('topic-story-answer-11'));
      await tester.tap(find.byKey(const Key('topic-story-answer-11')));
      await tester.pumpAndSettle();

      expect(find.text('这个玩法没有答案'), findsOneWidget);
      expect(find.byKey(const Key('topic-story-answer-reveal')), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(fake.answerCalls, hasLength(2));
      expect(fake.answerCalls[1]['nodeId'], 11, reason: '重试要记得看的是哪一站');
      final Text reveal = tester.widget<Text>(
        find.byKey(const Key('topic-story-answer-reveal')),
      );
      expect(reveal.data, '1896');
    });

    testWidgets('没有 clubId(从玩家入口进来)→ 不发请求,明说从俱乐部进来才看得了', (WidgetTester tester) async {
      final fake = _FakeClubTopicOpsApi()
        ..overviewValue = ClubTopicOverview.tryFromJson(
          _overviewJson(chapters: _twoChapterChapters()),
        )!;
      await _pumpPage(tester, fake: fake, clubId: null);
      await _switchToPlayTab(tester);

      await _reveal(tester, const Key('topic-story-answer-11'));
      await tester.tap(find.byKey(const Key('topic-story-answer-11')));
      await tester.pumpAndSettle();

      expect(fake.answerCalls, isEmpty);
      expect(find.text('要从俱乐部里进来才能看答案'), findsOneWidget);
      expect(find.byKey(const Key('topic-story-answer-sheet')), findsNothing);
    });
  });
}
