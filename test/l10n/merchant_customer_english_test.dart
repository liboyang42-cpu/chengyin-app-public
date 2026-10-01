import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/merchant_crm_console.dart';
import 'package:chengyin_app/data/models/merchant_crm_export.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_crm_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import '../support/fake_crm_console_api.dart';

Widget _host(Widget child) => MaterialApp(locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: child);
void main() {
  testWidgets('English customer permission state does not load private rows', (tester) async {
    final api = FakeCrmConsoleApi();
    await tester.pumpWidget(ProviderScope(overrides: [
      merchantCrmAccessProvider.overrideWith((ref) async => const MerchantCrmAccess(active: true)),
      merchantCrmConsoleApiProvider.overrideWithValue(api),
    ], child: _host(const MerchantCustomerPage())));
    await tester.pumpAndSettle();
    expect(find.text('Your role cannot view customers'), findsOneWidget);
    expect(api.queries, isEmpty);
  });
  testWidgets('English customer list preserves names phone hints and notes', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeCrmConsoleApi(page: FakeCrmConsoleApi.pageOf([
      FakeCrmConsoleApi.rowJson(name: '原始客户', phone: null, contactHint: '原始号码权限原因', latestNote: '原始客户备注'),
    ]));
    await tester.pumpWidget(ProviderScope(overrides: [
      merchantCrmAccessProvider.overrideWith((ref) async => const MerchantCrmAccess(active: true, canReadCrm: true)),
      merchantCrmConsoleApiProvider.overrideWithValue(api),
    ], child: _host(const MerchantCustomerPage())));
    await tester.pumpAndSettle();
    expect(find.text('原始客户'), findsOneWidget);
    expect(find.text('原始号码权限原因'), findsOneWidget);
    expect(find.text('原始客户备注'), findsOneWidget);
    expect(find.text('Awaiting redemption'), findsOneWidget);
  });
  testWidgets('CRM fallbacks preserve same-text server names and missing count semantics', (tester) async {
    final segments = CrmSavedSegment.parseList([{'id': 1}, {'id': 2, 'name': '已保存分群'}]);
    final coupons = CrmCoupon.parseList([{'id': 1}, {'id': 2, 'name': '优惠券'}]);
    await tester.pumpWidget(_host(Builder(builder: (context) => Scaffold(body: Column(children: [
      for (final row in segments) Text(merchantCrmSegmentName(context, row)),
      for (final row in coupons) Text(merchantCrmCouponName(context, row)),
      Text(merchantCrmSummary(context, const CrmCustomerPageData(rows: [], total: 0, segmentCounts: {}, availableTags: []))),
      Text(merchantCrmExportStatus(context, const MerchantCrmExportTask(id: 1, status: 'SUCCESS', rowCount: 12))),
      Text(merchantCrmAction(context, const CrmCustomerRow(memberId: 1, name: '原名', lastAction: '原始动作', lastTime: '2026-09-28 12:00:00'), DateTime(2026, 9, 30, 12))),
    ])))));
    expect(find.text('Saved segment'), findsOneWidget);
    expect(find.text('已保存分群'), findsOneWidget);
    expect(find.text('Coupon'), findsOneWidget);
    expect(find.text('优惠券'), findsOneWidget);
    expect(find.text('Loading customer count'), findsOneWidget);
    expect(find.text('Export ready (12 rows)'), findsOneWidget);
    expect(find.text('原始动作 · 2 days ago'), findsOneWidget);
  });
}
