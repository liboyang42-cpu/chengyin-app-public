import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/account/my_likes_page.dart';
import 'package:chengyin_app/feature/account/participants_page.dart';
import 'package:chengyin_app/feature/account/play_guide_page.dart';
import 'package:chengyin_app/feature/activity/participant_picker.dart';

void main() {
  testWidgets('账户高频页使用 iOS 原生导航壳且 200% 字号不溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));

    final List<
      ({Widget page, List<dynamic> overrides, String bodyAnchor, String title})
    >
    cases =
        <
          ({
            Widget page,
            List<dynamic> overrides,
            String bodyAnchor,
            String title,
          })
        >[
          (
            page: const MyLikesPage(),
            overrides: <dynamic>[
              myLikesProvider.overrideWith((_) async => const []),
            ],
            bodyAnchor: '我的收藏',
            title: '我的收藏',
          ),
          (
            page: const PlayGuidePage(),
            overrides: <dynamic>[
              infomationsProvider.overrideWith((_) async => const []),
            ],
            bodyAnchor: '三种玩法,即开即玩',
            title: '城瘾玩法',
          ),
          (
            page: const ParticipantsPage(liquidGlassSupported: false),
            overrides: <dynamic>[
              participantsProvider.overrideWith((_) async => const []),
            ],
            bodyAnchor: '参与人信息',
            title: '参与人信息',
          ),
        ];

    for (final testCase in cases) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: testCase.overrides.cast(),
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(390, 844),
                textScaler: TextScaler.linear(2),
              ),
              child: testCase.page,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoPageScaffold), findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      expect(find.text(testCase.title), findsOneWidget);
      expect(find.text(testCase.bodyAnchor), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(testCase.bodyAnchor)).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(CupertinoNavigationBar)).dy,
        ),
        reason: '${testCase.title} 的正文不能被透明导航栏遮住',
      );
      expect(tester.takeException(), isNull, reason: testCase.title);
    }
  });

  testWidgets('iOS 路由自动给原生导航栏返回键并支持左缘滑返', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          myLikesProvider.overrideWith((_) async => const []),
        ].cast(),
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (BuildContext context) => CupertinoButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const MyLikesPage()),
              ),
              child: const Text('打开收藏'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget);

    await tester.dragFrom(const Offset(1, 420), const Offset(360, 0));
    await tester.pumpAndSettle();
    expect(find.text('打开收藏'), findsOneWidget);
  });
}
