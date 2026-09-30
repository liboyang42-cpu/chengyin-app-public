// 成长中心:空态那句话与两个 aria 标签跟小程序逐字对齐。
//
// ★ 真源 `subpackageP3/pages/growthcenter/index/index.wxml`:
//   cy-empty sub「继续探索城市，第一枚徽章会在这里出现」(全角逗号)、
//   徽章区重试钮 aria-label「重试徽章数据」、
//   名次行 aria-label「查看完整排行榜」(可见文字只是「查看榜单」)。
//   ⚠️ 一屏上两处「重试」(排名 / 徽章),屏幕阅读器要能分清点的是哪一个 ——
//   这两个 aria 不是装饰,是**可区分性**。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/growth_api.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/growth/growth_center_page.dart';

class _FakeGrowthApi implements GrowthApi {
  _FakeGrowthApi({required this.badges, this.centerFails = false});

  final List<MedalBadge> badges;

  /// 成长中心接口没接通 → 徽章区走「暂不可用 + 重试」那一支。
  final bool centerFails;

  @override
  Future<GrowthCenter> center() async {
    if (centerFails) throw Exception('500');
    return GrowthCenter(
      levelNo: 1,
      expValue: 0,
      points: 0,
      badges: badges,
      missions: const <GrowthMission>[],
    );
  }

  @override
  Future<PlayGrowth> playGrowth() async => throw Exception('500');

  @override
  Future<List<CompletedActivity>> myCompleted() async => throw Exception('500');

  @override
  Future<GrowthLeaderboard> leaderboard({
    String metric = 'point',
    String period = 'total',
    int limit = 20,
  }) async => throw Exception('500');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 成长中心对游客是登录门(B1 报告 P1 修复),这两条拍的是登录后的文案。
class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
  );
}

Future<void> _pump(
  WidgetTester t,
  List<MedalBadge> badges, {
  bool centerFails = false,
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(() => _FixedAuth()),
        growthApiProvider.overrideWithValue(
          _FakeGrowthApi(badges: badges, centerFails: centerFails),
        ),
      ].cast(),
      child: const MaterialApp(home: GrowthCenterPage()),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('★ 徽章空态:全角逗号那句,逐字和小程序一样', (WidgetTester t) async {
    await _pump(t, const <MedalBadge>[]);
    expect(find.text('还没有点亮任何徽章'), findsOneWidget);
    expect(find.text('继续探索城市，第一枚徽章会在这里出现'), findsOneWidget);
    expect(
      find.text('继续探索城市,第一枚徽章会在这里出现'),
      findsNothing,
      reason: '半角逗号和小程序对不上(这一句被逐字比过)',
    );
  });

  testWidgets('★ 徽章区重试钮带着自己的 aria:一屏两处「重试」要分得清', (WidgetTester t) async {
    // 徽章源没接通(center 抛错)→ 徽章区出现「重试」。
    final SemanticsHandle handle = t.ensureSemantics();
    await _pump(t, const <MedalBadge>[], centerFails: true);
    expect(find.text('徽章数据暂时不可用'), findsOneWidget);
    // 徽章区那一行里的「重试」——一屏两处「重试」,屏幕阅读器靠这个 label 分。
    final Finder badgeRetry = find.descendant(
      of: find
          .ancestor(of: find.text('徽章数据暂时不可用'), matching: find.byType(Row))
          .first,
      matching: find.text('重试'),
    );
    expect(badgeRetry, findsOneWidget);
    expect(t.getSemantics(badgeRetry).label, '重试徽章数据');
    expect(find.text('重试'), findsWidgets, reason: '可见文字还是「重试」,aria 只是补上区分');
    handle.dispose();
  });
}
