// 成长中心整页视觉快照:完整数据态 / 排名 notice 态 / 徽章加载失败态 /
// 徽章空态。与 pages_account 同套路:Riverpod override 注入假 Api,不打网络。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/growth.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/growth/growth_center_page.dart';

import 'fake_growth_api.dart';

import 'golden_theme.dart';

/// 成长中心对游客是登录门(B1 报告 P1 修复),快照拍的是登录后的三态。
class _FixedAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 1, nickname: '阿兰', avatar: '', role: 'player'),
  );
}

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: <dynamic>[
      ...overrides,
      authControllerProvider.overrideWith(() => _FixedAuth()),
    ].cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

void main() {
  Future<void> pumpGrowth(WidgetTester tester, List<dynamic> overrides) async {
    setGoldenViewport(tester, const Size(390, 800));
    await tester.pumpWidget(_app(overrides, const GrowthCenterPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('成长中心:完整数据态(积分/名次/足迹/徽章)', (WidgetTester tester) async {
    await pumpGrowth(tester, <dynamic>[
      growthApiProvider.overrideWithValue(FakeGrowthApi()),
    ]);
    expect(find.text('Lv.7'), findsOneWidget);
    expect(find.text('1,234,567'), findsOneWidget);
    expect(find.text('12,345'), findsOneWidget);
    expect(find.text('123.4'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: '两个活动同一 topic,去重后 1 个主题');
    // 真源 .gc-score-rank-copy 只有昵称 + 总榜名次两行;TOP 百分位是 profile
    // 组件字段,成长中心不上屏(a5-ios27-p3-2 复核删掉自造尾巴)。
    expect(find.text('总榜第 42 名'), findsOneWidget);
    expect(find.text('开始在场'), findsOneWidget);
    await expectLater(
      find.byType(GrowthCenterPage),
      matchesGoldenFile('goldens/p3_growth_center_full.png'),
    );
  });

  testWidgets('成长中心:排名 HTTP 异常 → notice 文案不标红重试', (WidgetTester tester) async {
    await pumpGrowth(tester, <dynamic>[
      growthApiProvider.overrideWithValue(
        FakeGrowthApi(
          boardError: DioException(
            requestOptions: RequestOptions(path: '/api/growth/leaderboard'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/growth/leaderboard'),
              statusCode: 502,
            ),
          ),
        ),
      ),
    ]);
    expect(find.text('排行榜暂未开放，请稍后查看'), findsOneWidget);
    expect(find.text('重试'), findsNothing, reason: 'notice 态不该放重试按钮');
  });

  testWidgets('成长中心:徽章数据加载失败 → 显示不可用,不显示 0 枚', (WidgetTester tester) async {
    await pumpGrowth(tester, <dynamic>[
      growthApiProvider.overrideWithValue(
        FakeGrowthApi(centerError: Exception('500')),
      ),
    ]);
    expect(find.text('徽章数据暂时不可用'), findsOneWidget);
    expect(find.text('0'), findsNothing, reason: '没拿到不能伪装成 0 枚');
  });

  testWidgets('成长中心:徽章空态', (WidgetTester tester) async {
    await pumpGrowth(tester, <dynamic>[
      growthApiProvider.overrideWithValue(
        FakeGrowthApi(
          centerData: GrowthCenter(
            levelNo: 1,
            expValue: 0,
            points: 0,
            badges: <MedalBadge>[],
            missions: <GrowthMission>[],
          ),
          playError: Exception('500'),
          completedError: Exception('500'),
        ),
      ),
    ]);
    expect(find.text('还没有点亮任何徽章'), findsOneWidget);
    expect(
      find.text('—'),
      findsNWidgets(2),
      reason: 'play/completed 没拿到 → 两项 —',
    );
  });
}
