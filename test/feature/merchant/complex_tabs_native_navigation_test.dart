import 'dart:io';

import 'package:chengyin_app/core/widgets/cy_tabs.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/data/models/merchant_relation.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_relation_page.dart';
import 'package:chengyin_app/feature/merchant/topic_chapter_applications_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('三个复杂 Tab 根页移除 Material TabController 实现', () {
    for (final String path in <String>[
      'lib/feature/merchant/merchant_coop_page.dart',
      'lib/feature/merchant/merchant_relation_page.dart',
      'lib/feature/merchant/topic_chapter_applications_page.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, contains('CupertinoPageScaffold('), reason: path);
      expect(source, contains('CupertinoNavigationBar('), reason: path);
      expect(source, contains('CyTabs('), reason: path);
      expect(source, contains('CyTabsVariant.segmented'), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('TabBar(')), reason: path);
      expect(source, isNot(contains('TabBarView(')), reason: path);
      expect(source, isNot(contains('TabController')), reason: path);
    }
  });

  testWidgets('合作中心保留两档顺序、默认项与切换内容', (WidgetTester tester) async {
    await _pump(
      tester,
      const MerchantCoopPage(),
      overrides: <dynamic>[
        recruitingRoutesProvider.overrideWith(
          (_) async => const <RecruitingRoute>[],
        ),
        merchantInvitesProvider.overrideWith(
          (_) async => const <MerchantInvite>[],
        ),
      ],
    );

    expect(_tabLabels(tester), <String>['可承接', '邀约我的']);
    expect(find.text('暂无开放路线'), findsOneWidget);
    await tester.tap(find.text('邀约我的'));
    await tester.pumpAndSettle();
    expect(find.text('还没有邀约'), findsOneWidget);
  });

  testWidgets('伙伴页保留两档顺序、默认项与切换内容', (WidgetTester tester) async {
    await _pump(
      tester,
      const MerchantRelationPage(),
      overrides: <dynamic>[
        merchantRelationProvider.overrideWith(
          (_) async => const MerchantRelationHome(),
        ),
      ],
    );

    expect(_tabLabels(tester), <String>['已建立', '发现']);
    expect(find.text('还没有合作伙伴'), findsOneWidget);
    await tester.tap(find.text('发现'));
    await tester.pump();
    expect(find.text('附近暂时没有可发现的伙伴'), findsOneWidget);
  });

  testWidgets('章节承接保留三档顺序、默认项与切换内容', (WidgetTester tester) async {
    const int topicId = 42;
    await _pump(
      tester,
      const TopicChapterApplicationsPage(topicId: topicId),
      overrides: <dynamic>[
        topicChapterApplicationsProvider(
          topicId,
        ).overrideWith((_) async => const <Map<String, dynamic>>[]),
        pendingChapterNodesProvider(
          topicId,
        ).overrideWith((_) async => const <Map<String, dynamic>>[]),
        invitableMerchantsProvider(
          topicId,
        ).overrideWith((_) async => const <Map<String, dynamic>>[]),
      ],
    );

    expect(_tabLabels(tester), <String>['待我审', '点位待审', '可邀请']);
    expect(find.text('还没有商家申请承接'), findsOneWidget);
    await tester.tap(find.text('点位待审'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-pending-nodes-empty')), findsOneWidget);
    await tester.tap(find.text('可邀请'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner-invitable-empty')), findsOneWidget);
  });

  testWidgets('200% Dynamic Type 下原生分段控件仍可读且热区不小于 44pt', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const MerchantCoopPage(),
      textScaler: const TextScaler.linear(2),
      overrides: <dynamic>[
        recruitingRoutesProvider.overrideWith(
          (_) async => const <RecruitingRoute>[],
        ),
        merchantInvitesProvider.overrideWith(
          (_) async => const <MerchantInvite>[],
        ),
      ],
    );

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(CyTabs), findsOneWidget);
    expect(
      tester.getSize(find.byType(CyTabs)).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });
}

List<String> _tabLabels(WidgetTester tester) {
  final CyTabs tabs = tester.widget<CyTabs>(find.byType(CyTabs));
  return tabs.tabs.map((CyTab tab) => tab.label).toList(growable: false);
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required List<dynamic> overrides,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: textScaler,
          ),
          child: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
