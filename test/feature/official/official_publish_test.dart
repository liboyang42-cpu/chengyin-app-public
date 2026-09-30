// 官方活动发布:白名单闸必须在**入口和页里都生效**。
//
// ★★★ 后端 `canPublish(memberId)` 读 sys_config 的
//   `official_publish_whitelist`(逗号分隔 memberId,**空 = 全部拒绝**),
//   非白名单一律 `error("无官方发布权限")`。
//   ⇒ 只在页里挡、入口照放,等于让绝大多数人点进去撞一句权限错误 ——
//     那比没有按钮更坏。
//
// ★★ 拿不到权限时按**没有**处理:官方活动是对外承诺,
//   宁可让真白名单用户少一个入口(他还能从后台发)。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/feature/official/official_publish_page.dart';

class _FakeApi implements OfficialApi {
  _FakeApi({this.can = true, this.canError, this.publishError});
  final bool can;
  final Object? canError;
  final Object? publishError;
  Map<String, dynamic>? sent;
  Map<String, dynamic>? broadcastSent;

  @override
  Future<bool> canPublish() async {
    if (canError != null) throw canError!;
    return can;
  }

  @override
  Future<int> publishEvent(Map<String, dynamic> e) async {
    sent = e;
    if (publishError != null) throw publishError!;
    return 77;
  }

  @override
  Future<int> broadcast(Map<String, dynamic> body) async {
    broadcastSent = body;
    return 88;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, _FakeApi api) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('官方页')),
      ),
      GoRoute(
        path: '/official/publish',
        builder: (_, _) => const OfficialPublishPage(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.binding.setSurfaceSize(const Size(390, 1400));
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[officialApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await t.pumpAndSettle();
  router.push('/official/publish');
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★★ 非白名单:整页是权限说明,没有表单', (WidgetTester t) async {
    await _pump(t, _FakeApi(can: false));
    expect(find.text('你还没有官方发布权限'), findsOneWidget);
    expect(find.byKey(const Key('official-publish')), findsNothing);
    // 说清怎么才能有,不是只说不行。
    expect(find.textContaining('联系平台'), findsOneWidget);
  });

  testWidgets('★★★ 权限查不到时按「没有」处理', (WidgetTester t) async {
    await _pump(t, _FakeApi(canError: Exception('网络超时')));
    expect(
      find.text('你还没有官方发布权限'),
      findsOneWidget,
      reason: '官方活动是对外承诺 —— 判不准时宁可少一个入口',
    );
    expect(find.byKey(const Key('official-publish')), findsNothing);
  });

  testWidgets('★ 白名单:有表单,没写名字时按钮说清差什么', (WidgetTester t) async {
    await _pump(t, _FakeApi());
    final Finder btn = find.byKey(const Key('official-publish'));
    expect(btn, findsOneWidget);
    expect(t.widget<CupertinoButton>(btn).onPressed, isNull);
    expect(find.text('输入活动标题'), findsOneWidget);
  });

  testWidgets('★★★ 发布活动的 payload 完整且成功回执对齐', (WidgetTester t) async {
    final api = _FakeApi();
    await _pump(t, api);
    await t.enterText(find.byKey(const Key('official-title')), '城市漫游月');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('official-publish')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(api.sent?['title'], '城市漫游月');
    expect(api.sent?['category'], 'city_light');
    expect(api.sent?['rewardJson'], '{"settleXp":0,"settleBadge":true}');
    expect(api.broadcastSent, isNull, reason: '没选受众时活动只发布不通知');
    expect(find.text('活动已发布'), findsOneWidget);
  });

  testWidgets('★★ 内容安全不过时,后端原因原文透传', (WidgetTester t) async {
    await _pump(t, _FakeApi(publishError: Exception('标题包含违规词:XXX')));
    await t.enterText(find.byKey(const Key('official-title')), 'x');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('official-publish')));
    await t.pumpAndSettle();
    expect(
      find.text('标题包含违规词:XXX'),
      findsOneWidget,
      reason: '那句话告诉他改哪儿 —— 改写成「发布失败」他就不知道了',
    );
  });

  testWidgets('★ 活动发布后可把 eventId 绑到通知', (WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, api);
    await t.enterText(find.byKey(const Key('official-title')), '成都点亮日');
    await t.tap(find.byKey(const Key('official-audience-player')));
    await t.pump();
    await t.tap(find.byKey(const Key('official-publish')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    expect(api.broadcastSent?['eventId'], 77);
    expect(api.broadcastSent?['audience'], 'player');
    expect(find.text('已发布并通知'), findsOneWidget);
  });

  testWidgets('★ 只发通知不创建活动，受众选定后上送', (WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, api);
    final CupertinoSlidingSegmentedControl<String> mode = t.widget(
      find.byKey(const Key('official-mode')),
    );
    mode.onValueChanged('notice');
    await t.pump();
    await t.tap(find.byKey(const Key('official-audience-club')));
    await t.enterText(find.byKey(const Key('official-unifiedTitle')), '俱乐部通知');
    await t.pump();
    await t.tap(find.byKey(const Key('official-publish')));
    await t.pumpAndSettle();

    expect(api.sent, isNull);
    expect(api.broadcastSent?['eventId'], isNull);
    expect(api.broadcastSent?['audience'], 'club');
    expect(api.broadcastSent?['title'], '俱乐部通知');
    expect(find.text('通知已发送'), findsOneWidget);
  });
}
