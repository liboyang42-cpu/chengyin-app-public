// 移交主题给俱乐部承接。
//
// ★★★ 这**不是「改个归属」**。后端 summary 原话:
//   「复制一份新草稿挂该俱乐部,**原主题下架**;发起人保留所有权」。
//   三件事同时发生,文案少说一件都会让用户误判 ——
//   只说「已移交」会让人以为原主题还在、只是换了个人管,而它已经下架了。
//
// ★★ 入口判据是 `TopicDetail.isOwner`(后端 ApiTopicController:996
//   `isOwner = memberId == 我 ? 1 : 0`,**发的是 0/1 数字不是布尔**)。
//
// ⚠️ 小程序把候选俱乐部 `slice(0, 6)` —— 那是**微信 ActionSheet 只能放 6 项**
//   的平台限制,不是产品规则。App 不抄:照抄会把第 7 个之后的静默藏掉。
//   (与「App 不给微信胶囊让位」同一类。)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';
import 'package:chengyin_app/feature/topic/transfer_to_club_sheet.dart';

class _FakeClubApi implements ClubApi {
  _FakeClubApi(this.count);
  final int count;
  @override
  Future<List<Club>> my() async => List<Club>.generate(
    count,
    (int i) =>
        Club.fromJson(<String, dynamic>{'id': i + 1, 'name': '俱乐部${i + 1}'}),
  );
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RetryClubApi implements ClubApi {
  int calls = 0;
  bool failing = true;

  @override
  Future<List<Club>> my() async {
    calls += 1;
    if (failing) {
      throw Exception('断网');
    }
    return <Club>[Club(id: 41, name: '重试后俱乐部')];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTopicApi implements TopicApi {
  _FakeTopicApi({this.result = 88});

  final int result;
  int calls = 0;
  int? topicSeen;
  int? clubSeen;

  @override
  Future<int> transferToClub({
    required int topicId,
    required int clubId,
  }) async {
    calls += 1;
    topicSeen = topicId;
    clubSeen = clubId;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TopicDetail _topic({Object? isOwner}) => TopicDetail.fromJson(<String, dynamic>{
  'id': 9,
  'name': '静安夜行',
  'chaptersList': <dynamic>[],
  'isOwner': ?isOwner,
});

Future<void> _pumpDetail(WidgetTester t, TopicDetail d) async {
  await t.binding.setSurfaceSize(const Size(390, 1000));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        topicDetailProvider(9).overrideWith((ref) async => d),
      ].cast(),
      child: const MaterialApp(home: TopicDetailPage(topicId: 9)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('★★ isOwner 是 0/1 数字,不是布尔', () {
    expect(_topic(isOwner: 1).isOwner, isTrue);
    expect(_topic(isOwner: 0).isOwner, isFalse);
    expect(_topic().isOwner, isFalse, reason: '拿不到就按"不是"处理 —— 移交会把原主题下架');
    // 后端将来改发布尔也别炸。
    expect(_topic(isOwner: true).isOwner, isTrue);
  });

  testWidgets('★★ 非创建者没有移交入口', (WidgetTester t) async {
    await _pumpDetail(t, _topic(isOwner: 0));
    expect(
      find.byKey(const Key('topic-transfer-to-club')),
      findsNothing,
      reason: '后端会拒「无权移交该主题」',
    );
  });

  testWidgets('★ 创建者有入口', (WidgetTester t) async {
    await _pumpDetail(t, _topic(isOwner: 1));
    expect(find.byKey(const Key('topic-transfer-to-club')), findsOneWidget);
  });

  testWidgets('★★★ 候选俱乐部全部列出,不截断到 6 个', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 1200));
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi(9)),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext c) => TextButton(
                onPressed: () => showTransferToClubSheet(c, topicId: 9),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('开'));
    await t.pumpAndSettle();

    // ⚠️ ListView 懒加载:第 7 项在屏外就不会被 build,直接 findsNothing
    //   会让这条断言分不清「被截断」和「没滚到」。先滚过去。
    await t.scrollUntilVisible(
      find.byKey(const Key('transfer-club-9')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    // 小程序那个 6 项上限是微信 ActionSheet 的限制,不是产品规则。
    expect(
      find.byKey(const Key('transfer-club-7')),
      findsOneWidget,
      reason: '第 7 个被截掉了 —— 那是微信的限制,不是我们的',
    );
    expect(find.byKey(const Key('transfer-club-9')), findsOneWidget);
    await t.tap(find.byKey(const Key('transfer-club-cancel')));
    await t.pumpAndSettle();
  });

  testWidgets('★★ 一个可承接俱乐部都没有时,保持小程序空态', (WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(390, 900));
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi(0)),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext c) => TextButton(
                onPressed: () => showTransferToClubSheet(c, topicId: 9),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('开'));
    await t.pumpAndSettle();
    expect(find.text('你还没有可承接的俱乐部'), findsOneWidget);
    expect(
      find.textContaining('主理人'),
      findsNothing,
      reason: '小程序当前空态只有这一句,不额外增加模块',
    );
    await t.tap(find.byKey(const Key('transfer-club-cancel')));
    await t.pumpAndSettle();
  });

  testWidgets('iOS 原生 Sheet 保持 API 行序、VoiceOver 与 Reduce Motion', (
    WidgetTester t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    MethodCall? nativeCall;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      nativeCall = call;
      return true;
    });
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi(3)),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showTransferToClubSheet(context, topicId: 9),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('开'));
    await t.pumpAndSettle();

    expect(nativeCall?.method, 'showTemplateSheet');
    final Map<Object?, Object?> arguments =
        nativeCall!.arguments! as Map<Object?, Object?>;
    expect(arguments['backgroundZoomScale'], 1.0);
    final Map<Object?, Object?> content =
        arguments['content']! as Map<Object?, Object?>;
    expect(content['title'], '选择承接俱乐部');
    expect(content['doneSemanticLabel'], '取消移交给俱乐部承接');
    final List<Object?> sections = content['sections']! as List<Object?>;
    final List<Object?> rows =
        (sections.single! as Map<Object?, Object?>)['rows']! as List<Object?>;
    expect(
      rows.map((Object? row) => (row! as Map<Object?, Object?>)['title']),
      <String>['俱乐部1', '俱乐部2', '俱乐部3'],
    );
    final Map<Object?, Object?> second = rows[1]! as Map<Object?, Object?>;
    expect(second['buttonDismissesSheet'], isTrue);
    expect(second['buttonSemanticLabel'], '选择俱乐部：俱乐部2');
    final Map<Object?, Object?> style =
        second['buttonStyle']! as Map<Object?, Object?>;
    expect(style['buttonHeight'], 48.0);
    expect(style['titleFontSize'], isNull, reason: '留空才会由原生 Dynamic Type 接管');
    expect(style['pressedScale'], 1.0);
    expect(style['pressAnimationDuration'], 0.0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('加载失败保留 Sheet 并能重试，不冒充空态', (WidgetTester t) async {
    final _RetryClubApi clubs = _RetryClubApi();
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[clubApiProvider.overrideWithValue(clubs)].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showTransferToClubSheet(context, topicId: 9),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('开'));
    await t.pumpAndSettle();
    final int callsBeforeRetry = clubs.calls;
    expect(callsBeforeRetry, greaterThanOrEqualTo(1));
    expect(find.text('网络错误,请重试'), findsOneWidget);
    expect(find.text('你还没有可承接的俱乐部'), findsNothing);
    clubs.failing = false;
    await t.tap(find.text('重试'));
    await t.pumpAndSettle();

    expect(clubs.calls, greaterThan(callsBeforeRetry));
    expect(find.byKey(const Key('transfer-club-41')), findsOneWidget);
    await t.tap(find.byKey(const Key('transfer-club-cancel')));
    await t.pumpAndSettle();
  });

  for (final MapEntry<String, Object> failure in <String, Object>{
    'MissingPlugin': MissingPluginException('sheet unavailable'),
    'PlatformException': PlatformException(
      code: 'presentation_failed',
      message: 'sheet unavailable',
    ),
  }.entries) {
    testWidgets('原生 Sheet ${failure.key} 时回退 Cupertino 且保留 44pt/语义', (
      WidgetTester t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall call,
      ) async {
        throw failure.value;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await t.pumpWidget(
        ProviderScope(
          overrides: <dynamic>[
            clubApiProvider.overrideWithValue(_FakeClubApi(1)),
          ].cast(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showTransferToClubSheet(context, topicId: 9),
                  child: const Text('开'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('开'));
      await t.pumpAndSettle();

      final Finder row = find.byKey(const Key('transfer-club-1'));
      expect(row, findsOneWidget);
      expect(t.getSize(row).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('选择俱乐部：俱乐部1'), findsOneWidget);
      await t.tap(find.byKey(const Key('transfer-club-cancel')));
      await t.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('原生行回传真实 club ID，并发展示只提交一次', (WidgetTester t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const MethodChannel channel = MethodChannel('mjn_liquid_ui/sheets');
    final Completer<bool> nativeShow = Completer<bool>();
    String? secondActionId;
    int nativeShowCalls = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      if (call.method != 'showTemplateSheet') return null;
      nativeShowCalls += 1;
      final Map<Object?, Object?> arguments =
          call.arguments! as Map<Object?, Object?>;
      final Map<Object?, Object?> content =
          arguments['content']! as Map<Object?, Object?>;
      final List<Object?> sections = content['sections']! as List<Object?>;
      final List<Object?> rows =
          (sections.single! as Map<Object?, Object?>)['rows']! as List<Object?>;
      secondActionId =
          (rows[1]! as Map<Object?, Object?>)['buttonActionId'] as String?;
      return nativeShow.future;
    });
    addTearDown(() {
      if (!nativeShow.isCompleted) nativeShow.complete(false);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    final _FakeTopicApi topic = _FakeTopicApi(result: 88);
    late Future<int?> first;
    late Future<int?> second;
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_FakeClubApi(2)),
          topicApiProvider.overrideWithValue(topic),
        ].cast(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () {
                  first = showTransferToClubSheet(context, topicId: 9);
                  second = showTransferToClubSheet(context, topicId: 9);
                },
                child: const Text('开'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('开'));
    for (int i = 0; i < 6; i += 1) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(nativeShowCalls, 1);

    await _sendPlatformMethodCall(channel, 'buttonPressed', <String, Object?>{
      'actionId': secondActionId,
    });
    nativeShow.complete(true);
    await t.pumpAndSettle();
    expect(find.text('移交给俱乐部承接'), findsOneWidget);
    expect(
      find.text(
        '将复制一份新的城市定向主题(有人带),挂到「俱乐部2」承接;'
        '原主题会下架,历史票不受影响。',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('确认移交'));
    await t.pumpAndSettle();

    expect(await Future.wait<int?>(<Future<int?>>[first, second]), <int?>[
      88,
      88,
    ]);
    expect(nativeShowCalls, 1);
    expect(topic.calls, 1);
    expect(topic.topicSeen, 9);
    expect(topic.clubSeen, 2);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _sendPlatformMethodCall(
  MethodChannel channel,
  String method,
  Object? arguments,
) async {
  final ByteData message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, arguments),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channel.name, message, (_) {});
}
