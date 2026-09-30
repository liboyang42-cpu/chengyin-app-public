// 勋章墙整页视觉快照 + 徽章详情页。假 Api 注入,不打网络。
// 状态:完整(墙网格)/ sheet 详情 / wall-v2 挂 / medal 挂 / 空墙。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/badge_wall_api.dart';
import 'package:chengyin_app/data/models/badge_wall.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_logic.dart';
import 'package:chengyin_app/feature/p3/badges/badge_detail_page.dart';
import 'package:chengyin_app/feature/p3/badges/badge_wall_page.dart';

import 'golden_theme.dart';

class FakeBadgeWallApi implements BadgeWallApi {
  FakeBadgeWallApi({
    this.v2Error,
    this.medalError,
    this.v2Data,
    this.medalData,
  });

  final Object? v2Error;
  final Object? medalError;
  final Map<String, dynamic>? v2Data;
  final Map<String, dynamic>? medalData;

  @override
  Future<BadgeWallV2> wallV2() async {
    if (v2Error != null) throw v2Error!;
    return BadgeWallV2.fromJson(
      v2Data ??
          <String, dynamic>{
            'identity': <dynamic>[
              <String, dynamic>{
                'badgeCode': 'FIRST_STEP',
                'badgeName': '开始在场',
                'nameEn': 'First Step',
                'statement': '你第一次走进这座城市',
                'iconUrl': '',
                'assetType': 'IDENTITY',
                'category': 'EXPLORE',
                'unlockHint': '完成第一次城市打卡',
                'unlocked': true,
                'unlockTime': '2026-07-12 10:30:00',
              },
              <String, dynamic>{
                'badgeCode': 'ID_CITY_LIT',
                'badgeName': '点亮全城',
                'nameEn': 'City Lit',
                'statement': '',
                'iconUrl': '',
                'assetType': 'IDENTITY',
                'category': 'CO_CREATE',
                'unlockHint': '点亮 10 个城市节点',
                'unlocked': false,
              },
            ],
            'growth': <dynamic>[],
            'collection': <dynamic>[],
            'honor': <dynamic>[],
          },
    );
  }

  @override
  Future<MedalWall> medalWall() async {
    if (medalError != null) throw medalError!;
    return MedalWall.fromJson(
      medalData ??
          <String, dynamic>{
            'count': 2,
            'medals': <dynamic>[
              <String, dynamic>{
                'templateId': 3,
                'medalImg': '',
                'medalName': '城墙勋章',
                'style': 'enamel',
                'topicId': 5,
                'getTime': '2026-07-13 09:00:00',
                'condition': '完成绑定此勋章模板的城市节点',
                'kind': '',
              },
              <String, dynamic>{
                'badgeCode': 'STREAK_7',
                'medalName': '七日连击',
                'medalImg': '',
                'style': 'glow',
                'getTime': '2026-07-10 08:00:00',
                'kind': 'achievement',
              },
            ],
          },
    );
  }
}

/// 勋章墙对游客是登录门(B1 报告 P1 修复),快照拍的是登录后的三态。
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
  Future<void> pumpWall(WidgetTester tester, List<dynamic> overrides) async {
    setGoldenViewport(tester, const Size(390, 800));
    await tester.pumpWidget(_app(overrides, const BadgeWallPage()));
    await tester.pumpAndSettle();
  }

  List<dynamic> overrides(FakeBadgeWallApi api) => <dynamic>[
    badgeWallApiProvider.overrideWithValue(api),
  ];

  testWidgets('勋章墙:完整数据(身份卡×2 + 纪念章 + 成就)', (WidgetTester tester) async {
    await pumpWall(tester, overrides(FakeBadgeWallApi()));
    expect(find.text('已点亮 3 / 4 · 还有 1 枚等待探索'), findsOneWidget);
    expect(find.text('开始在场'), findsOneWidget);
    expect(find.text('城墙勋章'), findsOneWidget);
    expect(find.text('探索×1'), findsOneWidget);
    expect(find.text('创造×2'), findsOneWidget);
    expect(find.text('共创×1'), findsOneWidget);
    await expectLater(
      find.byType(BadgeWallPage),
      matchesGoldenFile('goldens/p3_badge_wall_full.png'),
    );
  });

  testWidgets('勋章墙:点开珐琅纪念章 → sheet 带查看3D入口', (WidgetTester tester) async {
    await pumpWall(tester, overrides(FakeBadgeWallApi()));
    await tester.tap(find.text('城墙勋章'));
    await tester.pumpAndSettle();
    expect(find.text('城市纪念章 · 节点通关'), findsOneWidget);
    expect(find.text('2026-07-13'), findsWidgets, reason: '卡片与 sheet 各一处');
    expect(find.text('查看 3D 徽章 →'), findsOneWidget);
    expect(find.text('获得条件'), findsOneWidget);
    await expectLater(
      find.byType(CupertinoPageScaffold).last,
      matchesGoldenFile('goldens/p3_badge_wall_sheet.png'),
    );
  });

  testWidgets('勋章墙:wall-v2 挂 → 整页错误(不显示空墙)', (WidgetTester tester) async {
    await pumpWall(
      tester,
      overrides(FakeBadgeWallApi(v2Error: BadgeWallException('500'))),
    );
    expect(find.text('勋章数据没有到达'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('还没有点亮勋章'), findsNothing);
  });

  testWidgets('勋章墙:medal 挂 → 部分失败,不静默当完整', (WidgetTester tester) async {
    await pumpWall(
      tester,
      overrides(FakeBadgeWallApi(medalError: BadgeWallException('500'))),
    );
    expect(find.text('部分勋章数据未到达，当前结果不完整'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('勋章墙:空墙 → 去探索 CTA', (WidgetTester tester) async {
    await pumpWall(
      tester,
      overrides(
        FakeBadgeWallApi(
          v2Data: <String, dynamic>{
            'identity': <dynamic>[],
            'growth': <dynamic>[],
            'collection': <dynamic>[],
            'honor': <dynamic>[],
          },
          medalData: <String, dynamic>{'count': 0, 'medals': <dynamic>[]},
        ),
      ),
    );
    expect(find.text('还没有点亮勋章'), findsOneWidget);
    expect(find.text('去探索'), findsOneWidget);
    await expectLater(
      find.byType(BadgeWallPage),
      matchesGoldenFile('goldens/p3_badge_wall_empty.png'),
    );
  });

  testWidgets('徽章详情:珐琅 + 神话色 + 真图参数', (WidgetTester tester) async {
    setGoldenViewport(tester, const Size(390, 800));
    await tester.pumpWidget(
      _app(
        <dynamic>[],
        const BadgeDetailPage(
          params: BadgeDetailParams(
            name: '城墙勋章',
            sub: '城墙线 · 完成一程',
            img: 'https://cdn/x.png',
            style: 'enamel',
            rarity: 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('城墙勋章'), findsOneWidget);
    expect(find.text('神话'), findsOneWidget);
    expect(find.text('珐琅样式'), findsOneWidget);
  });
}
