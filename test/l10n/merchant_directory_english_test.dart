import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant.dart';
import 'package:chengyin_app/data/models/merchant_coop.dart';
import 'package:chengyin_app/data/models/merchant_relation.dart';
import 'package:chengyin_app/data/models/chapter_application.dart';
import 'package:chengyin_app/feature/merchant/merchant_discover_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_relation_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_profile_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_chapters_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_clubs_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
class _Api implements MerchantApi {
  Map<String, dynamic>? saved;
  @override
  Future<String> saveCoopProfile({int? capacity, String? availableTime,
    String? suitActivityTypes, int? chargeType, String? demand, int? coopOpen}) async {
    saved = {'capacity': capacity, 'availableTime': availableTime,
      'suitActivityTypes': suitActivityTypes, 'chargeType': chargeType,
      'demand': demand, 'coopOpen': coopOpen};
    return '服务器保存回执';
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('discovery translates filter labels without changing backend tag matching', (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [discoverMerchantsProvider.overrideWith((ref, tag) async {
        requested.add(tag);
        return [Merchant(id: 1, memberId: 2, name: '夜间友好', description: '后端介绍', tags: '自定义标签')];
      })],
      child: _host(const MerchantDiscoverPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night friendly'));
    await tester.pumpAndSettle();
    expect(requested, contains('夜间友好'));
    expect(requested, isNot(contains('Night friendly')));
    expect(find.text('夜间友好'), findsOneWidget);
    expect(find.text('后端介绍'), findsOneWidget);
  });

  testWidgets('invitation labels localize while financial terms and backend title stay verbatim', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _host(const Scaffold(body: MerchantInviteTile(
      invite: MerchantInvite(id: 7, title: '官方活动', status: 2, shareMode: 2,
        fixedFee: 12.5, expireTime: '2026-10-02'),
    )))));
    await tester.pumpAndSettle();
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('官方活动'), findsOneWidget);
    expect(find.text('固定 ¥12.5/人'), findsOneWidget);
    expect(find.text('Deadline 10/2'), findsOneWidget);
    expect(find.text('Accept partnership'), findsNothing);
  });

  testWidgets('chapter application preserves rejection reason and withdraw rules', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [myChapterApplicationsProvider.overrideWith((ref) async => const [
        ChapterApplication(id: 1, topicName: '原始主题', chapterName: '原始章节',
          status: 2, auditRemark: '原始拒绝理由'),
      ])],
      child: _host(const MerchantChaptersPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('原始主题 · 原始章节'), findsOneWidget);
    expect(find.text('Declined: 原始拒绝理由'), findsOneWidget);
    expect(find.text('Withdraw application'), findsNothing);
  });

  testWidgets('relation missing description fallback differs from same-text server description', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantRelationProvider.overrideWith((ref) async => const MerchantRelationHome(
        relations: [
          MerchantRelation(id: 1, memberId: 1, name: '商家甲'),
          MerchantRelation(id: 2, memberId: 2, name: '商家乙', address: '查看商家资料'),
        ], stats: MerchantRelationStats(merchantCount: 2),
      ))],
      child: _host(const MerchantRelationPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Merchants 2'), findsOneWidget);
    expect(find.text('View merchant profile'), findsOneWidget);
    expect(find.text('查看商家资料'), findsOneWidget);
    expect(find.text('Pending 0'), findsNothing);
  });

  testWidgets('hosting settings retain hidden fields, time text and numeric charge mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantApiProvider.overrideWithValue(api),
        coopProfileProvider.overrideWith((ref) async => {
          'capacity': 30, 'availableTime': '周末 10:00-22:00',
          'suitActivityTypes': 'UNCHANGED_TYPES', 'chargeType': 1,
          'demand': '原始合作诉求', 'coopOpen': 1,
        }),
      ],
      child: _host(const MerchantCoopProfilePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Paid hosting'), findsOneWidget);
    expect(tester.widget<CupertinoSlidingSegmentedControl<int>>(find.byType(CupertinoSlidingSegmentedControl<int>)).groupValue, 1);
    await tester.tap(find.byKey(const Key('merchant-coop-save')));
    await tester.pumpAndSettle();
    expect(api.saved, {'capacity': 30, 'availableTime': '周末 10:00-22:00',
      'suitActivityTypes': 'UNCHANGED_TYPES', 'chargeType': 1,
      'demand': '原始合作诉求', 'coopOpen': 1});
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('club directory keeps city and name while localizing member count', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantClubsProvider.overrideWith((ref, keyword) async => [
        {'name': '俱乐部', 'city': '上海', 'memberCount': 12},
      ])], child: _host(const MerchantClubsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Clubs available to invite'), findsOneWidget);
    expect(find.text('俱乐部'), findsOneWidget);
    expect(find.text('上海 · 12 members'), findsOneWidget);
  });
}
