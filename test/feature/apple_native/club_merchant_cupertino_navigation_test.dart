import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:chengyin_app/data/models/club.dart';
import 'package:chengyin_app/data/models/club_manage.dart';
import 'package:chengyin_app/data/models/club_post.dart';
import 'package:chengyin_app/feature/club/club_controller.dart';
import 'package:chengyin_app/feature/club/club_enroll_page.dart';
import 'package:chengyin_app/feature/club/club_feed_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_apply_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {List<dynamic> overrides = const <dynamic>[]}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('俱乐部动态使用 Cupertino 根导航', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const ClubFeedPage(),
        overrides: <dynamic>[
          clubFeedProvider.overrideWith(
            (ref) async => ClubFeed.fromJson(<String, dynamic>{
              'clubCount': 1,
              'rows': <dynamic>[],
            }),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('俱乐部动态'), findsOneWidget);
  });

  testWidgets('报名名册使用 Cupertino 根导航且保留内容标题', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const ClubEnrollPage(clubId: 1, clubName: '城西探店社'),
        overrides: <dynamic>[
          clubDetailProvider(
            1,
          ).overrideWith((ref) async => Club(id: 1, name: '城西探店社')),
          clubTopicsProvider(1).overrideWith((ref) async => <ClubTopic>[]),
          clubMembersProvider(1).overrideWith((ref) async => <ClubMember>[]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('报名名册'), findsOneWidget);
  });

  testWidgets('商户申请使用 Cupertino 导航且 VoiceOver 可返回上一步', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        const MerchantApplyPage(),
        // 入驻页进页先查「名下有没有已提交的申请」(真源 checkExisting)。
        // 这条要的是向导本体 → 当后端回了 NONE。不桩就会吊着一个真请求,
        // pumpAndSettle 直接超时。
        overrides: <dynamic>[
          merchantApplicationProvider.overrideWith((ref) async => null),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('入驻申请 · 基础信息'), findsOneWidget);
    expect(find.bySemanticsLabel('返回'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('merchant-apply-name')),
      '城市咖啡',
    );
    await tester.enterText(
      find.byKey(const Key('merchant-apply-phone')),
      '13800138000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('merchant-apply-next')));
    await tester.pump();

    expect(find.text('入驻申请 · 经营信息'), findsOneWidget);
    final Finder back = find.bySemanticsLabel('返回上一步');
    expect(back, findsOneWidget);
    expect(tester.getSize(back).height, greaterThanOrEqualTo(44));
    final node = tester.getSemantics(back);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        nodeId: node.id,
        viewId: tester.view.viewId,
      ),
    );
    await tester.pump();

    expect(find.text('入驻申请 · 基础信息'), findsOneWidget);
    expect(find.byKey(const Key('merchant-apply-name')), findsOneWidget);
    semantics.dispose();
  });
}
