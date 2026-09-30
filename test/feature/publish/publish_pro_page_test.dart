import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/publish_api.dart';
import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/publish_draft.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/publish/publish_pro_page.dart';

/// 专业发布编辑器页面行为测试:
/// - 空草稿三起点 CTA
/// - 城市定向建章 → 直进故事流
/// - 票务页「检查并发布」在必填齐前禁用(不可用动作 = 禁用,不撞后端)
/// - 编辑既有主题:loading / error+重试 / 回填三态
/// - 模式切换
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

  int editDetailCalls = 0;
  bool failEditDetail = false;
  int createdTopicId = 77;

  @override
  Future<(PublishDraft, PublishEditScope)> editDetail(
    int id, {
    String scope = '',
  }) async {
    editDetailCalls++;
    if (failEditDetail) {
      throw Exception('这份主题打不开');
    }
    final draft = PublishDraft()
      ..name = '静安微旅行'
      ..subtitle = '一句话'
      ..description = '完整介绍'
      ..startDate = '2026-09-01'
      ..endDate = '2026-09-02'
      ..imgUrl = 'https://img/c.jpg'
      ..categoryIds = <int>[1]
      ..tickets = <PublishTicket>[
        PublishTicket()
          ..name = '早鸟票'
          ..mode = kProductCity,
      ];
    draft.chapters.add(
      PublishChapter()
        ..name = '第一章'
        ..description = '剧情'
        ..nodes = <PublishNode>[
          PublishNode()
            ..name = '节点一'
            ..longitude = '121.4'
            ..latitude = '31.2',
        ],
    );
    return (draft, PublishEditScope.full);
  }

  @override
  Future<List<AiPrecheckIssue>> safetyPrecheck(
    Map<String, dynamic> req,
  ) async => <AiPrecheckIssue>[];

  @override
  Future<int> createTopicPro(Map<String, dynamic> payload) async =>
      createdTopicId;
}

DioClient _dio() => DioClient(TokenStore(const FlutterSecureStorage()));

AuthState _authed() => AuthState(
  user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
  initialized: true,
);

Future<void> _pump(
  WidgetTester tester, {
  _FakePublishApi? api,
  int? topicId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth(_authed())),
        clubApiProvider.overrideWithValue(_FakeClubApi()),
        publishApiProvider.overrideWithValue(api ?? _FakePublishApi()),
      ].cast(),
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: PublishProPage(topicId: topicId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空草稿:城市定向起点 CTA = 写第一章', (WidgetTester tester) async {
    await _pump(tester);
    expect(find.text('未命名主题'), findsOneWidget);
    expect(find.text('还没有章节'), findsOneWidget);
    expect(find.text('写第一章'), findsOneWidget);
  });

  testWidgets('★ 建章后城市定向直进全屏故事流', (WidgetTester tester) async {
    await _pump(tester);
    // 页面上多了「合作者」入口后,这个钮会被挤出可视区 —— 先滚到它。
    await tester.ensureVisible(find.text('写第一章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写第一章'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chapter-name')), '第一章');
    await tester.tap(find.byKey(const Key('chapter-complete')));
    await tester.pumpAndSettle();
    // 章节卡出现,且故事流已展开。
    expect(find.text('第1章 · 故事流'), findsOneWidget);
    expect(find.textContaining('第1章 第一章'), findsOneWidget);
  });

  testWidgets('★ 必填没齐 → 检查并发布禁用(不撞后端)', (WidgetTester tester) async {
    await _pump(tester);
    // 切到票务页。
    await tester.tap(find.text('票务设置'));
    await tester.pumpAndSettle();
    final CupertinoButton publish = tester.widget(
      find.widgetWithText(CupertinoButton, '检查并发布'),
    );
    expect(publish.onPressed, isNull, reason: '草稿还差必填项,按钮必须禁用');
  });

  testWidgets('模式切换:城市定向 → 自由探索,票务页出现招商截止', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('城市定向'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自由探索'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mode-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('自由探索'), findsWidgets);
    // 票务页出现「招商截止日期」。
    await tester.tap(find.text('票务设置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('招商截止日期'), findsOneWidget);
  });

  testWidgets('编辑既有主题:loading → 错误 + 重试 → 回填', (WidgetTester tester) async {
    final api = _FakePublishApi()..failEditDetail = true;
    await _pump(tester, api: api, topicId: 9);
    // 错误态有重试。
    expect(find.text('这份主题打不开'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    api.failEditDetail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('静安微旅行'), findsOneWidget);
    expect(find.text('已填完'), findsOneWidget, reason: '回填的草稿必需项齐了');
    expect(api.editDetailCalls, 2);
  });
}
