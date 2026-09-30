// 积分 hero:拿不到的值不许兜 0。
//
// ★ 「这周没赚到」和「统计没算出来」是两回事。兜 0 会把后者说成前者 ——
//   用户看到 +0 会以为自己这周白干了,而其实是接口没返。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/points_statistics.dart';
import 'package:chengyin_app/feature/points/points_hero.dart';

Future<void> _pump(WidgetTester t, PointsStatistics? stat, {int? balance}) async {
  await t.pumpWidget(ProviderScope(
    overrides: <dynamic>[
      pointsStatProvider.overrideWith((Ref ref) async => stat),
    ].cast(),
    child: MaterialApp(home: Scaffold(body: PointsHero(balance: balance))),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★ 统计没返 ⇒ 说「暂无」,绝不写 +0', (WidgetTester t) async {
    await _pump(t, null, balance: 120);
    expect(find.text('暂无'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('★ 余额没拿到 ⇒ 「—」,不是 0', (WidgetTester t) async {
    await _pump(t, null);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('两个口径分别标注,不许合并成一个「本周」', (WidgetTester t) async {
    await _pump(
      t,
      PointsStatistics.fromJson(<String, dynamic>{
        'weekPoints': '30',
        'rankPercentage': '82%',
      }),
      balance: 120,
    );
    expect(find.text('我的积分'), findsOneWidget);
    expect(find.text('本周获得'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('+30'), findsOneWidget);
  });

  testWidgets('★ 排名百分比原样透出 —— 后端自带 % 号,别自己再拼一个',
      (WidgetTester t) async {
    await _pump(
      t,
      PointsStatistics.fromJson(<String, dynamic>{
        'weekPoints': '30',
        'rankPercentage': '82%',
      }),
      balance: 1,
    );
    expect(find.text('超过 82% 的探索者'), findsOneWidget);
    expect(find.textContaining('%%'), findsNothing);
  });

  testWidgets('没有排名就整行不出现,不渲染「超过  的探索者」',
      (WidgetTester t) async {
    await _pump(
      t,
      PointsStatistics.fromJson(<String, dynamic>{'weekPoints': '30'}),
      balance: 1,
    );
    expect(find.byKey(const Key('points-hero-rank')), findsNothing);
  });
}
