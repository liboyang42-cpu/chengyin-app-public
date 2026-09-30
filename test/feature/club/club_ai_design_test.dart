// AI 策划俱乐部活动。
//
// ★★★ 后端返回体有**三种"失败"**,合并任何两种都会误导主理人:
//   ① parseError != null → AI 的回答**解析炸了**,plan/建议/文案**全不可信**
//      (后端 VO javadoc)⇒ 一个字段都不许渲染
//   ② plan == null 且无 parseError → AI **没给出方案**(静默空成功)。
//      和①是两回事:①是我们没读懂它,②是它没说
//   ③ code != 200 → 身份 / 配额 / 故障三分,前两种给重试钮都是骗人

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_creator_api.dart';
import 'package:chengyin_app/feature/club/club_ai_design_sheet.dart';

class _FakeAi implements AiCreatorApi {
  _FakeAi({this.data, this.err});
  final Map<String, dynamic>? data;
  final Object? err;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> clubDesign({
    required String idea,
    String? clubStyle,
    int? targetDurationMin,
  }) async {
    calls++;
    if (err != null) throw err!;
    return data ?? <String, dynamic>{};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _open(WidgetTester t, _FakeAi api, {String idea = '周六夜骑'}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  await t.pumpWidget(
    ProviderScope(
      retry: chengyinRetry,
      overrides: <dynamic>[aiCreatorApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) => TextButton(
              onPressed: () => showClubAiDesignSheet(c),
              child: const Text('开'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('开'));
  await t.pumpAndSettle();
  await t.enterText(find.byType(CupertinoTextField).first, idea);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('club-ai-generate')));
  await t.pumpAndSettle();
}

void main() {
  test('★★ 解析:plan 为空即不合法,不编内容', () {
    expect(ClubAiDesign.tryParse(<String, dynamic>{}), isNull);
    expect(ClubAiDesign.tryParse(<String, dynamic>{'plan': '   '}), isNull);
    final ClubAiDesign? d = ClubAiDesign.tryParse(<String, dynamic>{
      'plan': '沿苏州河骑 12km',
      'merchantSuggestions': <dynamic>['静安咖啡', '  ', '愚园书店'],
      'promoCopy': '  ',
    });
    expect(d!.merchantSuggestions, <String>[
      '静安咖啡',
      '愚园书店',
    ], reason: '空白项要滤掉,渲出来是个空条目');
    expect(d.promoCopy, isNull, reason: '只有空白 = 没有');
  });

  test('★★★ 身份问题和配额用尽都不值得重试', () {
    expect(aiDesignRetryable('当前身份暂不支持AI创作,请切换到俱乐部或商家身份'), isFalse);
    expect(
      aiDesignRetryable('今日AI次数已用完,明天再来'),
      isFalse,
      reason: '配额用尽给重试钮 = 让人一直点一个不会成功的按钮',
    );
    expect(aiDesignRetryable('AI 服务暂时不可用,请稍后重试'), isTrue);
  });

  testWidgets('★★★ parseError:一个字段都不许渲染', (WidgetTester t) async {
    await _open(
      t,
      _FakeAi(
        data: <String, dynamic>{
          'parseError': 'AI 返回的不是合法方案',
          // ⚠️ 这些字段后端 javadoc 说"不可信" —— 有值也不能显示。
          'plan': '看起来像方案但不可信',
          'promoCopy': '也不可信',
        },
      ),
    );
    expect(find.text('AI 返回的不是合法方案'), findsOneWidget);
    expect(
      find.text('看起来像方案但不可信'),
      findsNothing,
      reason: 'parseError 时 plan 不可信,渲出来就是把垃圾当方案给主理人',
    );
    expect(find.text('也不可信'), findsNothing);
  });

  testWidgets('★★★ AI 没给方案 ≠ 解析炸了,两句话要分开', (WidgetTester t) async {
    await _open(t, _FakeAi(data: <String, dynamic>{}));
    expect(find.textContaining('没给出方案'), findsOneWidget);
    expect(find.textContaining('不是合法方案'), findsNothing);
  });

  testWidgets('★★ 配额用尽:不给重试钮', (WidgetTester t) async {
    final api = _FakeAi(err: Exception('今日AI次数已用完,明天再来'));
    await _open(t, api);
    expect(find.byKey(const Key('club-ai-retry')), findsNothing);
    expect(api.calls, 1);
  });

  testWidgets('★★ 服务故障:给重试钮且真的再调', (WidgetTester t) async {
    final api = _FakeAi(err: Exception('AI 服务暂时不可用,请稍后重试'));
    await _open(t, api);
    expect(find.byKey(const Key('club-ai-retry')), findsOneWidget);
    await t.tap(find.byKey(const Key('club-ai-retry')));
    await t.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('★ 成功:三块都出来,并说清这只是草稿', (WidgetTester t) async {
    await _open(
      t,
      _FakeAi(
        data: <String, dynamic>{
          'plan': '沿苏州河骑 12km,中途歇脚',
          'merchantSuggestions': <dynamic>['静安咖啡'],
          'promoCopy': '这周六,我们去追一条河',
        },
      ),
    );
    expect(find.text('沿苏州河骑 12km,中途歇脚'), findsOneWidget);
    expect(find.textContaining('静安咖啡'), findsOneWidget);
    expect(find.text('这周六,我们去追一条河'), findsOneWidget);
    expect(
      find.textContaining('不会自动创建活动'),
      findsOneWidget,
      reason: '不说清楚,主理人会以为活动已经建好了',
    );
  });
}
