import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/data/api/merchant_customer_detail_api.dart';
import 'package:chengyin_app/data/models/merchant_customer_detail.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_detail_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements MerchantCustomerDetailGateway {
  _Api({this.allowed = true, this.name = '未留姓名', this.amount = 12.5});
  final bool allowed;
  final String? name;
  final double? amount;
  int detailCalls = 0;
  @override
  Future<MerchantCustomerAccess> access() async => MerchantCustomerAccess(active: true, merchantId: 7,
    roleCode: 'STAFF', permissions: allowed ? {MerchantCustomerAccess.crmRead} : {});
  @override
  Future<MerchantCustomerDetail> detail(int customerMemberId) async {
    detailCalls++;
    return MerchantCustomerDetail(summary: MerchantCustomerSummary.fromJson({
      'customerMemberId': customerMemberId, 'displayName': name, 'arrivedCount': 2, 'pendingCount': 1,
      'refundedCount': 0, 'paidAmount': amount, 'lastInteractionTime': '2026-09-30 12:34:00',
    }), systemTags: const [MerchantCustomerSystemTag(code: 'REPEAT_CUSTOMER', label: '原始系统标签')], merchantTags: const [],
      timeline: const [MerchantCustomerTimelineItem(key: 'NOTE-8', type: 'NOTE', title: '原始时间线标题', description: '原始客户备注', occurredAt: null, noteId: 8, noteVersion: 3, correctsNoteId: null)]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _page(_Api api) => MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales, home: MerchantCustomerDetailPage(api: api, customerMemberId: 41));
void main() {
  testWidgets('English customer detail gate prevents private detail request', (tester) async {
    final api = _Api(allowed: false);
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    expect(find.text('Your role cannot view customers'), findsOneWidget);
    expect(api.detailCalls, 0);
  });
  testWidgets('English detail preserves exact money name labels and read-only timeline', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_page(_Api()));
    await tester.pumpAndSettle();
    expect(find.text('未留姓名'), findsOneWidget);
    expect(find.text('¥12.50'), findsOneWidget);
    expect(find.text('原始系统标签'), findsOneWidget);
    expect(find.text('原始客户备注'), findsOneWidget);
    expect(find.text('Follow-up'), findsOneWidget);
    expect(find.byKey(const Key('merchant-customer-correct-note-8')), findsNothing);
  });
  testWidgets('missing customer name and restricted amount use independent English fallbacks', (tester) async {
    await tester.pumpWidget(_page(_Api(name: null, amount: null)));
    await tester.pumpAndSettle();
    expect(find.text('Name not provided'), findsOneWidget);
    expect(find.text('No permission to view'), findsOneWidget);
    expect(find.text('¥0.00'), findsNothing);
  });
}
