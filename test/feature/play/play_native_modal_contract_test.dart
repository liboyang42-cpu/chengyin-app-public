import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_lead_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/club_lead.dart';
import 'package:chengyin_app/feature/play/classic_game_task_sheet.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/team_lead_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LeadApi implements ClubLeadApi {
  int unlockCalls = 0;
  int settleCalls = 0;

  @override
  Future<void> unlockChapter(int activityId) async {
    unlockCalls += 1;
  }

  @override
  Future<void> settle(int activityId) async {
    settleCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuestionApi implements PlayApi {
  _QuestionApi(this.node);

  final PlayNode node;

  @override
  Future<PlayNodesResult> fetchTopicNodes(int topicId) async => PlayNodesResult(
    topicId: topicId,
    mode: 1,
    playable: true,
    total: 1,
    doneCount: 0,
    nodes: <PlayNode>[node],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _leadApp(_LeadApi api, {double textScale = 1}) {
  const TeamProgress progress = TeamProgress(
    exists: true,
    isLeader: true,
    arrived: 1,
    members: <TeamMember>[
      TeamMember(memberId: 1, nickname: '队长', arrived: true, isLeader: true),
    ],
  );
  return ProviderScope(
    overrides: <dynamic>[
      clubLeadApiProvider.overrideWithValue(api),
      teamProgressProvider(7).overrideWith((Ref ref) async => progress),
    ].cast(),
    child: MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const TeamLeadPage(activityId: 7),
    ),
  );
}

Widget _playApp(PlayNode node) => ProviderScope(
  overrides: <dynamic>[
    playApiProvider.overrideWithValue(_QuestionApi(node)),
  ].cast(),
  child: const MaterialApp(home: PlaySessionPage(activityId: 0, topicId: 23)),
);

void main() {
  testWidgets('带队页的可见操作使用至少 44pt 的 Cupertino 按钮', (WidgetTester tester) async {
    await tester.pumpWidget(_leadApp(_LeadApi()));
    await tester.pumpAndSettle();

    for (final String key in <String>[
      'team-lead-arrive',
      'team-lead-action-broadcast',
      'team-lead-action-verifyMemberTicket',
      'team-lead-action-unlockChapter',
      'team-lead-action-settle',
    ]) {
      final Finder action = find.byKey(Key(key));
      expect(action, findsOneWidget);
      expect(tester.widget(action), isA<CupertinoButton>());
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('队员票手工回落用 Cupertino 短输入和 ASCII 系统键盘', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_leadApp(_LeadApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫成员票核销'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    final CupertinoTextField field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('cy-system-input-alert-field')),
    );
    expect(field.keyboardType, TextInputType.visiblePassword);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('队长广播用可拖拽 Cupertino Sheet 和多行系统键盘', (WidgetTester tester) async {
    await tester.pumpWidget(_leadApp(_LeadApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('发广播'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CupertinoPopupSurface), findsWidgets);
    final CupertinoTextField field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('team-lead-broadcast-input')),
    );
    expect(field.maxLines, 3);
    expect(field.textInputAction, TextInputAction.newline);
    expect(field.textCapitalization, TextCapitalization.sentences);
    expect(
      tester.getSize(find.byKey(const Key('team-lead-broadcast-send'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('队长广播在 200% Dynamic Type 下仍可滚动编辑和发送', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_leadApp(_LeadApi(), textScale: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('发广播'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('team-lead-broadcast-input')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(
      tester.getSize(find.byKey(const Key('team-lead-broadcast-send'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('解锁章节和全团结算在请求前保留小程序二次确认', (WidgetTester tester) async {
    final _LeadApi api = _LeadApi();
    await tester.pumpWidget(_leadApp(api));
    await tester.pumpAndSettle();

    // 动作键与确认框标题现在同名(照真源「解锁下一章节」),按 key 点、按对话框找。
    await tester.tap(find.byKey(const Key('team-lead-action-unlockChapter')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(CupertinoAlertDialog),
        matching: find.text('解锁下一章节'),
      ),
      findsOneWidget,
    );
    expect(find.text('确认让全队进入下一章节?'), findsOneWidget);
    expect(api.unlockCalls, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.unlockCalls, 0);

    await tester.tap(find.byKey(const Key('team-lead-action-unlockChapter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认解锁'));
    await tester.pumpAndSettle();
    expect(api.unlockCalls, 1);

    await tester.tap(find.byKey(const Key('team-lead-action-settle')));
    await tester.pumpAndSettle();
    expect(find.text('全团结算'), findsOneWidget);
    expect(find.textContaining('到场已购票的全体队员'), findsOneWidget);
    expect(api.settleCalls, 0);
    await tester.tap(find.text('结算全团'));
    await tester.pumpAndSettle();
    expect(api.settleCalls, 1);
  });

  testWidgets('带积分提示的站点用 Cupertino Action Sheet 保留两个打开目标', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _playApp(
        const PlayNode(
          nodeId: 9,
          name: '梧桐线索',
          address: '衡山路',
          sortId: 1,
          done: false,
          needAnswer: true,
          hintLocked: true,
          hintCost: 12,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('梧桐线索'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('解锁提示 · 12 积分'), findsOneWidget);
    expect(find.text('直接答题'), findsOneWidget);
  });

  testWidgets('文字答题走 Cupertino 任务页(不是 Alert),Return 直接提交', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _playApp(
        const PlayNode(
          nodeId: 10,
          name: '门牌线索',
          address: '康平路',
          sortId: 1,
          done: false,
          needAnswer: true,
          question: '这条街最常见的树是什么?',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('门牌线索'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byKey(const Key('classic-answer-task')), findsOneWidget);
    final CupertinoTextField field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('play-answer-text-input')),
    );
    expect(field.keyboardType, TextInputType.text);
    expect(field.textInputAction, TextInputAction.done);
    // mp-sheet 原文:placeholder「写下你的答案」+ aria-label「填写任务答案」。
    expect(field.placeholder, '写下你的答案');
    expect(
      find.ancestor(
        of: find.byKey(const Key('play-answer-text-input')),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.label == '填写任务答案',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('解谜答题输入保留 gp2 原文,不加 mp-sheet 的 aria-label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClassicAnswerTaskView(
            node: const PlayNode(
              nodeId: 11,
              name: '刻痕解谜',
              address: '湖南路',
              sortId: 1,
              done: false,
              needAnswer: true,
              question: '石阶上刻着哪个字?',
              puzzleScoring: true,
            ),
            usedHints: const <String>[],
            onSubmit: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final CupertinoTextField field = tester.widget<CupertinoTextField>(
      find.byKey(const Key('play-answer-text-input')),
    );
    expect(field.placeholder, '把你找到的字填在这里');
    expect(
      find.ancestor(
        of: find.byKey(const Key('play-answer-text-input')),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.label == '填写任务答案',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('发奖的徽章列表用 Cupertino Sheet，不硬塞进 Alert', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    final BuildContext context = tester.element(find.byType(Scaffold));

    showRewardDialog(
      context,
      const CheckinReward(
        nodeId: 7,
        firstTime: true,
        doneCount: 1,
        total: 2,
        completed: false,
        newBadges: <PlayBadge>[
          PlayBadge(code: 'first', name: '首枚徽章', iconUrl: ''),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CupertinoPopupSurface), findsWidgets);
    expect(find.text('打卡成功'), findsOneWidget);
    expect(find.text('首枚徽章'), findsOneWidget);
  });
}
