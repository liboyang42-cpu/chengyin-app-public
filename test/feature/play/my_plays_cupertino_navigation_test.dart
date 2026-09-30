import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/completed_play.dart';
import 'package:chengyin_app/feature/play/my_plays_page.dart';

void main() {
  testWidgets('我走过的使用 iOS 原生导航壳且 200% 字号不溢出', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          myCompletedPlaysProvider.overrideWith(
            (_) async => <CompletedPlay>[
              CompletedPlay.fromJson(<String, dynamic>{
                'name': '静安夜跑',
                'activityId': 1,
                'total': 6,
                'doneCount': 2,
              }),
            ],
          ),
        ].cast(),
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(2),
            ),
            child: MyPlaysPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.text('我走过的'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('静安夜跑')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(CupertinoNavigationBar)).dy,
      ),
      reason: '首条路线不能被透明导航栏遮住',
    );
    expect(tester.takeException(), isNull);
  });
}
