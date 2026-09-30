// Beta 转正(`POST /api/topic/beta/graduate`)。
//
// 快照 `pages/topic/index/index.wxml:73-82`:
//   · `betaFlag==1` 才挂「Beta 试玩」标识 —— 所有玩家都看得到;
//   · 「转为正式主题」只有作者(isOwner)看得到;
//   · 转正不可逆(清 beta_flag),所以必须先二次确认。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/topic.dart';
import 'package:chengyin_app/feature/topic/topic_detail_controller.dart';
import 'package:chengyin_app/feature/topic/topic_detail_page.dart';

class _FakeTopicApi implements TopicApi {
  int graduateCalls = 0;
  int? topicSeen;
  bool fail = false;

  @override
  Future<void> graduateBetaTopic(int topicId) async {
    graduateCalls += 1;
    topicSeen = topicId;
    if (fail) throw Exception('该主题不在 Beta 期');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TopicDetail _topic({int betaFlag = 0, bool isOwner = false}) =>
    TopicDetail.fromJson(<String, dynamic>{
      'id': 9,
      'name': '静安夜行',
      'chaptersList': <dynamic>[],
      'betaFlag': betaFlag,
      'isOwner': isOwner ? 1 : 0,
    });

Future<void> _pump(WidgetTester t, TopicDetail d, _FakeTopicApi api) async {
  await t.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        topicDetailProvider(9).overrideWith((ref) async => d),
        topicApiProvider.overrideWithValue(api),
      ].cast(),
      child: const MaterialApp(home: TopicDetailPage(topicId: 9)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('betaFlag 走 0/1 数字解析,缺失按 0(不是 Beta)', () {
    expect(_topic(betaFlag: 1).betaFlag, 1);
    expect(_topic().betaFlag, 0);
  });

  testWidgets('★★ 只有作者 + Beta 期才出现转正入口', (WidgetTester t) async {
    final _FakeTopicApi api = _FakeTopicApi();
    await _pump(t, _topic(betaFlag: 1, isOwner: true), api);
    expect(find.byKey(const Key('topic-graduate-beta')), findsOneWidget);
  });

  testWidgets('★★ 非作者看得到 Beta 标识,但没有转正入口', (WidgetTester t) async {
    final _FakeTopicApi api = _FakeTopicApi();
    await _pump(t, _topic(betaFlag: 1), api);
    expect(find.text('Beta 试玩'), findsOneWidget);
    expect(
      find.byKey(const Key('topic-graduate-beta')),
      findsNothing,
      reason: '后端只认创建者 —— 入口就不给',
    );
  });

  testWidgets('★ 不是 Beta 期,整块不显示', (WidgetTester t) async {
    final _FakeTopicApi api = _FakeTopicApi();
    await _pump(t, _topic(isOwner: true), api);
    expect(find.text('Beta 试玩'), findsNothing);
    expect(find.byKey(const Key('topic-graduate-beta')), findsNothing);
  });

  testWidgets('★★ 转正是不可逆写:先二次确认,确认后才调接口', (WidgetTester t) async {
    final _FakeTopicApi api = _FakeTopicApi();
    await _pump(t, _topic(betaFlag: 1, isOwner: true), api);

    await t.tap(find.byKey(const Key('topic-graduate-beta')));
    await t.pumpAndSettle();
    // 弹窗标题和页面按钮同名,认「确认转正」这颗键。
    expect(find.text('确认转正'), findsOneWidget);
    expect(api.graduateCalls, 0, reason: '确认之前不许调');

    await t.tap(find.text('确认转正'));
    await t.pumpAndSettle();
    expect(api.graduateCalls, 1);
    expect(api.topicSeen, 9);
  });

  testWidgets('★ 后端拒了(不在 Beta 期)就原话透传,不假装成功', (WidgetTester t) async {
    final _FakeTopicApi api = _FakeTopicApi()..fail = true;
    await _pump(t, _topic(betaFlag: 1, isOwner: true), api);

    await t.tap(find.byKey(const Key('topic-graduate-beta')));
    await t.pumpAndSettle();
    await t.tap(find.text('确认转正'));
    await t.pumpAndSettle();
    expect(api.graduateCalls, 1);
    expect(find.text('该主题不在 Beta 期'), findsOneWidget);
    expect(find.text('已转为正式主题'), findsNothing);
  });
}
