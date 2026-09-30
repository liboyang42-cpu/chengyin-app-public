import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/batch_detail_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_ai_insight_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_chapters_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_clubs_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_decor_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_discover_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_edit_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_ledger_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_registration_edit_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <({Widget page, String title})>[
    (page: const BatchDetailPage(batchId: 1), title: '对公结算'),
    (page: const MerchantAiInsightPage(), title: '店铺参谋'),
    (page: const MerchantChaptersPage(), title: '我的承接'),
    (page: const MerchantClubsPage(), title: '可邀请的俱乐部'),
    (page: const MerchantDecorPage(), title: '店铺装修'),
    (page: const MerchantDiscoverPage(), title: '发现商家'),
    (page: const MerchantEditPage(), title: '店铺资料'),
    (page: const MerchantLedgerPage(), title: '台账'),
    (page: const MerchantPublicHomePage(memberId: 1), title: '商家主页'),
    (
      page: const MerchantRegistrationEditPage(registrationId: 1),
      title: '修改报名',
    ),
  ];

  for (final testCase in cases) {
    testWidgets('${testCase.title}使用 iOS 原生根导航且保留标题', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: <dynamic>[
            merchantApiProvider.overrideWithValue(_LoadingMerchantApi()),
          ].cast(),
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: testCase.page,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byType(CupertinoPageScaffold),
        findsOneWidget,
        reason: testCase.title,
      );
      expect(
        find.byType(CupertinoNavigationBar),
        findsOneWidget,
        reason: testCase.title,
      );
      expect(find.byType(Scaffold), findsNothing, reason: testCase.title);
      expect(find.byType(AppBar), findsNothing, reason: testCase.title);
      expect(find.text(testCase.title), findsOneWidget, reason: testCase.title);
      expect(tester.takeException(), isNull, reason: testCase.title);
    });
  }
}

class _LoadingMerchantApi implements MerchantApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<dynamic>().future;
}
