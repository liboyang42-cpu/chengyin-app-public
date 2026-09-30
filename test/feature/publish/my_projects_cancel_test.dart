// 我的项目卡片「取消并退款」链路(端点对齐 A1:topic/cancel + 两个 cancel_preview)。
//
// 小程序真源 subpackageA/pages/myproject/index.js 的三条硬约束:
//   ① 确认框必须写明「将给 N 位已付款玩家全额退款」—— N 问后端预览接口,
//      **拿不到就不弹确认、不发取消**(paidPlayersOrToast)。
//   ② 入口判据 1:1 decorate 的 canCancel:主题看主办者(俱乐部主题走
//      俱乐部「结束主题」),活动必须已有人买票且不是商家承接场次。
//   ③ 列表快捷取消走固定原因「主办方取消主题 / 主办方取消活动」;
//      主题成功原样显示后端 msg(dc.done(res.msg)),活动用固定结果文案。

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/topic_api.dart';
import 'package:chengyin_app/data/models/my_project.dart';
import 'package:chengyin_app/feature/publish/my_projects_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTopicApi implements TopicApi {
  _FakeTopicApi({this.paidPlayers});
  final int? paidPlayers;
  final String msg = '主题已取消,已为 2 笔订单全额退款';
  int previewCalls = 0;
  String? cancelledId;
  String? sentReason;

  @override
  Future<int> cancelPreview({required int topicId, String? scope}) async {
    previewCalls++;
    if (paidPlayers == null) {
      throw Exception('暂时算不出退款人数，请稍后重试');
    }
    return paidPlayers!;
  }

  @override
  Future<String> cancel({
    required int topicId,
    required String reason,
    String? scope,
  }) async {
    cancelledId = '$topicId/$reason';
    sentReason = reason;
    return msg;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeActivityApi implements ActivityApi {
  _FakeActivityApi({this.paidPlayers});
  final int? paidPlayers;
  int previewCalls = 0;
  String? sentReason;

  @override
  Future<int> cancelPreview({required int activityId, String? scope}) async {
    previewCalls++;
    if (paidPlayers == null) {
      throw Exception('暂时算不出退款人数，请稍后重试');
    }
    return paidPlayers!;
  }

  @override
  Future<String> cancelActivity({
    required int activityId,
    required String reason,
  }) async {
    sentReason = reason;
    return '活动已取消,已为 3 笔订单全额退款(原路退回,预计1-3个工作日)';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

MyProject _project({
  required int id,
  required String bizType,
  required String state,
  String title = '测试项目',
  String ownerType = 'member',
  int signupCount = 0,
}) => MyProject.fromJson(<String, dynamic>{
  'id': id,
  'bizType': bizType,
  'title': title,
  'state': state,
  'stateText': state,
  'ownerType': ownerType,
  'signupCount': signupCount,
});

Future<void> _pump(
  WidgetTester t, {
  required List<MyProject> projects,
  _FakeTopicApi? topicApi,
  _FakeActivityApi? activityApi,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 800));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        myProjectsProvider.overrideWith((_) async => projects),
        myProjectTemplatesProvider.overrideWith((_) async => const []),
        if (topicApi != null) topicApiProvider.overrideWithValue(topicApi),
        if (activityApi != null)
          activityApiProvider.overrideWithValue(activityApi),
      ],
      child: const MaterialApp(
        home: MyProjectsPage(liquidGlassSupported: false),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  group('canCancel 入口判据(1:1 decorate)', () {
    test('主题:个人/商家主办可取消,俱乐部主题不给入口', () {
      expect(
        _project(id: 1, bizType: 'topic', state: 'running').canCancel,
        isTrue,
      );
      expect(
        _project(
          id: 1,
          bizType: 'topic',
          state: 'running',
          ownerType: 'club',
        ).canCancel,
        isFalse,
        reason: '俱乐部主题有岗位权限,走俱乐部「结束主题」',
      );
      expect(
        _project(
          id: 1,
          bizType: 'topic',
          state: 'offline',
          ownerType: 'merchant',
        ).canCancel,
        isTrue,
      );
    });

    test('活动:必须已有人买票,商家承接场次保持只读', () {
      expect(
        _project(id: 1, bizType: 'activity', state: 'running').canCancel,
        isFalse,
        reason: '没人买票不存在退款,下架/删除即可',
      );
      expect(
        _project(
          id: 1,
          bizType: 'activity',
          state: 'running',
          signupCount: 5,
        ).canCancel,
        isTrue,
      );
      expect(
        _project(
          id: 1,
          bizType: 'activity',
          state: 'running',
          ownerType: 'merchant',
          signupCount: 5,
        ).canCancel,
        isFalse,
        reason: '取消/删除涉及全额退款权限,商家承接的 activity 只读',
      );
      expect(
        _project(id: 1, bizType: 'topic', state: 'draft').canCancel,
        isFalse,
      );
    });

    testWidgets('入口按判据出现/消失', (WidgetTester t) async {
      await _pump(
        t,
        projects: <MyProject>[
          _project(
            id: 11,
            bizType: 'topic',
            state: 'running',
            ownerType: 'club',
          ),
          _project(
            id: 12,
            bizType: 'activity',
            state: 'running',
            signupCount: 5,
          ),
        ],
      );
      // 默认在「主题」分段:俱乐部主题不给取消入口
      expect(find.byKey(const Key('project-cancel-11')), findsNothing);
      // 切到「活动」分段:已有人买票的非商家场次给入口
      await t.tap(find.text('活动'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('project-cancel-12')), findsOneWidget);
      expect(find.text('取消活动'), findsOneWidget);
    });
  });

  group('取消主题:预览 → 确认写明 N → 固定原因取消', () {
    testWidgets('确认后调 /api/topic/cancel 带原因「主办方取消主题」,成功原样显示后端 msg', (
      WidgetTester t,
    ) async {
      final topic = _FakeTopicApi(paidPlayers: 7);
      await _pump(
        t,
        projects: <MyProject>[
          _project(id: 21, bizType: 'topic', state: 'running', title: '雨夜城市定向'),
        ],
        topicApi: topic,
      );

      await t.tap(find.byKey(const Key('project-cancel-21')));
      await t.pumpAndSettle();
      expect(topic.previewCalls, 1, reason: '确认框的人数来自 cancel_preview,不自己推');

      expect(
        find.textContaining('将给 7 位已付款玩家全额退款'),
        findsOneWidget,
        reason: '9-18 拍板:确认框必须写明退款人数',
      );
      expect(find.textContaining('取消「雨夜城市定向」并退款'), findsOneWidget);

      await t.tap(find.text('取消并退款'));
      await t.pumpAndSettle();
      expect(topic.cancelledId, '21/主办方取消主题');
      expect(
        find.textContaining('主题已取消,已为 2 笔订单全额退款'),
        findsOneWidget,
        reason: 'dc.done(res.msg) —— 退款明细那句话以后端为准',
      );
    });

    testWidgets('预览拿不到 N ⇒ 不弹确认、不发取消,toast 说明', (WidgetTester t) async {
      final topic = _FakeTopicApi();
      await _pump(
        t,
        projects: <MyProject>[
          _project(id: 22, bizType: 'topic', state: 'running'),
        ],
        topicApi: topic,
      );

      await t.tap(find.byKey(const Key('project-cancel-22')));
      await t.pumpAndSettle();
      expect(topic.previewCalls, 1);
      expect(
        find.text('暂时算不出退款人数，请稍后重试'),
        findsOneWidget,
        reason: 'paidPlayersOrToast:拿不到就把原因 toast 出来',
      );
      expect(find.text('取消并退款'), findsNothing);
      expect(topic.cancelledId, isNull);
    });
  });

  group('取消活动(列表快捷入口):预览 → 确认 → 固定原因取消', () {
    testWidgets('确认后调 cancelActivity 带原因「主办方取消活动」', (WidgetTester t) async {
      final activity = _FakeActivityApi(paidPlayers: 4);
      await _pump(
        t,
        projects: <MyProject>[
          _project(
            id: 31,
            bizType: 'activity',
            state: 'running',
            signupCount: 4,
          ),
        ],
        activityApi: activity,
      );

      await t.tap(find.text('活动'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('project-cancel-31')));
      await t.pumpAndSettle();
      expect(activity.previewCalls, 1);
      expect(find.textContaining('将给 4 位已付款玩家全额退款'), findsOneWidget);
      expect(
        find.textContaining('活动同时下架'),
        findsOneWidget,
        reason: '活动与主题的确认文案各是各的,不共用',
      );

      await t.tap(find.text('取消并退款'));
      await t.pumpAndSettle();
      expect(activity.sentReason, '主办方取消活动');
      expect(find.textContaining('活动已取消'), findsOneWidget);
    });
  });
}
