import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_creator_api.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/models/club_comment.dart';
import 'package:chengyin_app/feature/club/club_ai_design_sheet.dart';
import 'package:chengyin_app/feature/club/club_comments_sheet.dart';
import 'package:chengyin_app/feature/club/club_posts_section.dart';

class _RecordingAi implements AiCreatorApi {
  String? idea;
  String? clubStyle;
  int? targetDurationMin;

  @override
  Future<Map<String, dynamic>> clubDesign({
    required String idea,
    String? clubStyle,
    int? targetDurationMin,
  }) async {
    this.idea = idea;
    this.clubStyle = clubStyle;
    this.targetDurationMin = targetDurationMin;
    return <String, dynamic>{
      'traceId': 'trace-1',
      'plan': <String, dynamic>{
        'title': '静安夜光',
        'subtitle': '一条夜间 Citywalk',
        'storyline': '从咖啡店出发',
        'tags': <String>['夜间', 'Citywalk'],
        'estDurationMin': 90,
        'fitReason': '适合文艺慢生活俱乐部',
        'risks': <String>['留意夜间交通'],
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{
            'order': 1,
            'merchantName': 'A 咖啡',
            'address': '静安区',
          },
        ],
      },
      'merchantSuggestions': <String>['独立咖啡店'],
      'promoCopy': '周六一起出发',
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingClub implements ClubApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({required List<dynamic> overrides, required Widget button}) {
  return ProviderScope(
    retry: chengyinRetry,
    overrides: overrides.cast(),
    child: MaterialApp(
      home: Scaffold(body: Center(child: button)),
    ),
  );
}

/// 剪贴板是平台通道:不 mock 的话 `Clipboard.setData` 在测试里不落地,
/// 「复制」之后的轻提示(await 在剪贴板之后)就永远不出现。
void _mockClipboard() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async => null,
      );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('AI sheet 保留小程序三个输入和完整结果顺序', (WidgetTester tester) async {
    final _RecordingAi api = _RecordingAi();
    _mockClipboard();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _host(
        overrides: <dynamic>[aiCreatorApiProvider.overrideWithValue(api)],
        button: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showClubAiDesignSheet(context),
            child: const Text('打开 AI'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开 AI'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNWidgets(3));
    expect(find.text('静安 情侣 夜间 Citywalk 90分钟'), findsOneWidget);
    expect(find.text('苏州河 摄影 徒步 2小时'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).at(0), '静安 夜间');
    await tester.enterText(find.byType(CupertinoTextField).at(1), '文艺');
    await tester.enterText(find.byType(CupertinoTextField).at(2), '90');
    await tester.tap(find.byKey(const Key('club-ai-generate')));
    await tester.pumpAndSettle();

    expect(api.idea, '静安 夜间');
    expect(api.clubStyle, '文艺');
    expect(api.targetDurationMin, 90);
    expect(find.text('静安夜光'), findsOneWidget);
    expect(find.text('为什么适合:适合文艺慢生活俱乐部'), findsOneWidget);
    expect(find.text('路线节点 · 1'), findsOneWidget);
    expect(find.text('风险提示'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    // 纯告知不弹 alert(S7):复制成功走页内轻提示,与俱乐部其它「已复制」同一写法。
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(find.text('已复制宣传文案'), findsOneWidget);
    expect(
      find.byType(CupertinoAlertDialog),
      findsNothing,
      reason: '纯告知弹 alert 会被 S7 判违规 —— 页内轻提示即可',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.scrollUntilVisible(
      find.byKey(const Key('club-ai-adopt')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('用这个方案去发布'), findsOneWidget);
  });

  testWidgets('评论 sheet 使用 Cupertino 输入并保留直接举报入口', (WidgetTester tester) async {
    final ClubApi api = _CommentApi();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _host(
        overrides: <dynamic>[clubApiProvider.overrideWithValue(api)],
        button: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showClubCommentsSheet(context, postId: 8),
            child: const Text('打开评论'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开评论'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.text('举报'), findsOneWidget);
    expect(
      find.byIcon(Icons.more_horiz),
      findsNothing,
      reason: '小程序评论行上是直接删除/举报，不应多一次「更多」操作',
    );
  });

  testWidgets('发动态 sheet 使用 Cupertino 输入且空内容不能发', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      _host(
        overrides: <dynamic>[
          clubApiProvider.overrideWithValue(_RecordingClub()),
        ],
        button: Builder(
          builder: (BuildContext context) => CupertinoButton(
            onPressed: () => showClubComposeSheet(context, clubId: 7),
            child: const Text('打开发布'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开发布'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.text('添加图片'), findsOneWidget);
    final CupertinoButton submit = tester.widget<CupertinoButton>(
      find.byKey(const Key('club-compose-submit')),
    );
    expect(submit.onPressed, isNull);
  });
}

class _CommentApi implements ClubApi {
  @override
  Future<List<ClubComment>> postComments(
    int postId, {
    int pageNum = 1,
    int pageSize = 50,
  }) async => <ClubComment>[
    ClubComment.fromJson(<String, dynamic>{
      'id': 1,
      'memberId': 99,
      'nickname': '小静',
      'content': '一起去',
    }),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
