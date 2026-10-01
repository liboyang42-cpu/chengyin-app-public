// 邀请记录页:两种"没奖励"必须说不同的话。
//
// ★ 这条测的是**页面真渲出来的字**,不是逻辑函数 —— 逻辑对但页面
//   把 rewardReady 接反了,用户看到的还是假话。

import 'package:flutter/material.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/account/invite_history_logic.dart';
import 'package:chengyin_app/feature/account/invite_history_page.dart';

import '../../support/fixed_auth.dart';

InviteHistoryState _state({required bool ready}) => InviteHistoryState(
  groups: buildInviteGroups(
    members:
        const <({int id, String name, String? avatar, String? createTime})>[
          (id: 7, name: '小李', avatar: null, createTime: '2026-08-03 09:05:00'),
        ],
    rewards: const <String, InviteReward>{},
    rewardReady: ready,
  ),
  total: 1,
  rewardReady: ready,
  earnedTotal: 0,
);

Future<void> _pump(WidgetTester t, {required bool ready, bool english = false}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        signedInAuthOverride(),
        inviteHistoryProvider.overrideWith(
          (Ref ref) async => _state(ready: ready),
        ),
      ].cast(),
      child: MaterialApp(
        locale: english ? const Locale('en') : const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(english ? 2 : 1)),
          child: child!,
        ),
        home: const InviteHistoryPage(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  // NOT_RUN locally: Flutter SDK unavailable.
  testWidgets('English large text preserves incomplete-reward uncertainty and names', (t) async {
    await _pump(t, ready: false, english: true);
    expect(find.text('Invitation history'), findsOneWidget);
    expect(find.text('Joined · Reward sync pending'), findsOneWidget);
    expect(find.text('小李'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('★★ 流水没拉全:说「待同步」,且必须横那条说明', (WidgetTester t) async {
    await _pump(t, ready: false);
    expect(find.text('已加入 · 奖励待同步'), findsOneWidget);
    expect(find.byKey(const Key('invite-sync-note')), findsOneWidget);
    // 顶部汇总也不许显示 +0 —— 那是个数字,会被当成已结算的事实。
    expect(find.text('+0'), findsNothing);
    expect(find.text('待同步'), findsWidgets);
  });

  testWidgets('★ 流水拉全了没奖励:说「首购待完成」,不横说明', (WidgetTester t) async {
    await _pump(t, ready: true);
    expect(find.text('已加入 · 首购待完成'), findsOneWidget);
    expect(find.byKey(const Key('invite-sync-note')), findsNothing);
    expect(find.text('待解锁'), findsOneWidget);
    // 拉全了才允许把 0 当成事实说出来。
    expect(find.byKey(const Key('invite-earned-total')), findsOneWidget);
  });

  testWidgets('空态说清「怎么才会有」', (WidgetTester t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          signedInAuthOverride(),
          inviteHistoryProvider.overrideWith(
            (Ref ref) async => const InviteHistoryState(
              groups: <InviteGroup>[],
              total: 0,
              rewardReady: true,
              earnedTotal: 0,
            ),
          ),
        ].cast(),
        child: const MaterialApp(home: InviteHistoryPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('还没有邀请记录'), findsOneWidget);
    expect(find.textContaining('好友通过你的邀请加入后'), findsOneWidget);
  });
}
