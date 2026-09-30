// 排行榜整页视觉快照:完整榜单态 / 空榜态 / notice 态。假 Api 注入,不打网络。

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/growth_api.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/growth/leaderboard_page.dart';

import 'golden_theme.dart';
import 'fake_growth_api.dart';

/// 排行榜对游客是登录门(B1 报告 P1 修复),快照拍的是登录后的三态。
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
  Future<void> pumpBoard(WidgetTester tester, List<dynamic> overrides) async {
    setGoldenViewport(tester, const Size(390, 800));
    await tester.pumpWidget(_app(overrides, const LeaderboardPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('排行榜:前三领奖台 + 其余 + 我的名次', (WidgetTester tester) async {
    await pumpBoard(tester, <dynamic>[
      growthApiProvider.overrideWithValue(
        FakeGrowthApi(
          boardOverride: <String, dynamic>{
            'metric': 'point',
            'period': 'total',
            'list': <dynamic>[
              for (var i = 1; i <= 6; i++)
                <String, dynamic>{
                  'rank': i,
                  'memberId': i,
                  'nickname': '玩家$i',
                  'avatar': '',
                  'score': (7 - i) * 1000,
                },
            ],
            'me': <String, dynamic>{
              'rank': 42,
              'memberId': 99,
              'nickname': '阿兰',
              'avatar': '',
              'score': 66,
              'rankPercentage': 'TOP20%',
            },
          },
        ),
      ),
    ]);
    expect(find.text('第1名'), findsOneWidget);
    expect(find.text('玩家6'), findsOneWidget);
    expect(find.text('第 42 名'), findsOneWidget);
    await expectLater(
      find.byType(LeaderboardPage),
      matchesGoldenFile('goldens/p3_leaderboard_full.png'),
    );
  });

  testWidgets('排行榜:空榜 → 去探索 CTA(不是重试)', (WidgetTester tester) async {
    await pumpBoard(tester, <dynamic>[
      growthApiProvider.overrideWithValue(
        FakeGrowthApi(
          boardOverride: <String, dynamic>{
            'metric': 'point',
            'period': 'total',
            'list': <dynamic>[],
            'me': <String, dynamic>{'score': 0},
          },
        ),
      ),
    ]);
    expect(find.text('这张榜还没有人上榜'), findsOneWidget);
    expect(find.text('完成一次城市探索就会累计积分，第一个上榜的可能就是你'), findsOneWidget);
    expect(find.text('去探索'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await expectLater(
      find.byType(LeaderboardPage),
      matchesGoldenFile('goldens/p3_leaderboard_empty.png'),
    );
  });

  testWidgets('排行榜:HTTP 异常 → notice,无重试按钮', (WidgetTester tester) async {
    await pumpBoard(tester, <dynamic>[
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
    expect(find.text('排行榜没能加载出来'), findsOneWidget);
    expect(find.text('排行榜暂未开放，请稍后查看'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('排行榜:业务错误 → 危险态,给重试', (WidgetTester tester) async {
    await pumpBoard(tester, <dynamic>[
      growthApiProvider.overrideWithValue(
        FakeGrowthApi(boardError: GrowthException('请先登录')),
      ),
    ]);
    expect(find.text('排行榜没能加载出来'), findsOneWidget);
    expect(find.text('请先登录'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    await expectLater(
      find.byType(LeaderboardPage),
      matchesGoldenFile('goldens/p3_leaderboard_error.png'),
    );
  });
}
