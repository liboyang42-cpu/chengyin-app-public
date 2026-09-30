// 俱乐部贡献榜整页快照。
//
// fixture 刻意造**语义边界**而不是漂亮数据:
//   · 第一名有完整数据;
//   · 第二名 pace / completionDuration 都是 **null**(零里程或零用时)——
//     这一行必须显示「—」。若显示成 0,他就是"0.0 min/km 的最快的人",
//     而他恰恰是没有任何有效计时的那个;
//   · 第三名没有 nickname —— 要回落成「成员 <id>」,不能是空白行。
//
// 更新基准图:flutter test --update-goldens test/golden/page_club_leaderboard_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_leaderboard_page.dart';
import 'golden_theme.dart';

const List<ClubRankRow> _rows = <ClubRankRow>[
  ClubRankRow(
    memberId: 1,
    nickname: '夜骑的老王',
    score: 42.5,
    clearCount: 8,
    mileage: 96.4,
    durationMin: 512.0,
    hostedCount: 3,
    pace: 5.3,
    completionDuration: 512.0,
  ),
  ClubRankRow(
    memberId: 2,
    nickname: '只打过一次卡',
    score: 2.0,
    clearCount: 1,
    mileage: 0,
    durationMin: 0,
    hostedCount: 0,
    // ★ 两个 null:零里程 / 零用时。后端用 nullsLast 把他沉底,
    //   前端也必须显示「—」——写 0 会让他变成"最快的人"。
    pace: null,
    completionDuration: null,
  ),
  ClubRankRow(
    memberId: 3,
    nickname: null, // 没设昵称 → 回落「成员 3」
    score: 1.0,
    clearCount: 1,
    mileage: 3.2,
    durationMin: 30,
    hostedCount: 0,
    pace: 9.4,
    completionDuration: 30,
  ),
];

/// ★ 四个排序维度**全部**覆盖。
///   只覆盖要拍的那一个是不够的:页面初始停在「综合」,
///   要拍配速榜得先点 tab,而点之前页面已经在读综合那一档 ——
///   没覆盖就落进真网络,骨架屏无限转,pumpAndSettle 直接超时。
List<dynamic> _overrides() => ClubRankSort.values
    .map((ClubRankSort s) =>
        clubLeaderboardProvider((clubId: 1, sort: s))
            .overrideWith((ref) async => _rows))
    .toList();

Future<void> _pump(WidgetTester tester) async {
  setGoldenViewport(tester, const Size(390, 900));
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides().cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: const ClubLeaderboardPage(clubId: 1),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('贡献榜:综合分', (WidgetTester tester) async {
    await _pump(tester);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_club_leaderboard_composite.png'));
  });

  testWidgets('★ 贡献榜:配速榜 —— 无配速那行必须是「—」不是 0',
      (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.text('配速'));
    await tester.pumpAndSettle();

    // golden 只证明"长这样";这两条证明"那个字符确实是 —,不是 0.0"。
    expect(find.text('—'), findsOneWidget, reason: '零里程那行应显示「—」');
    expect(find.textContaining('0.0 min/km'), findsNothing,
        reason: '写成 0.0 min/km 的话,没有有效计时的人会排在最快');
    // 没设昵称的那位要回落成「成员 3」,不能是空白行。
    expect(find.text('成员 3'), findsOneWidget);

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_club_leaderboard_pace.png'));
  });
}
