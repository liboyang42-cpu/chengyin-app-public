import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_crm_console_api.dart';

/// F15:列表里的号码是服务端脱敏号,拨/复制前必须经服务端换明文
/// (快照 pages/merchant/customer/index.js:734)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('点号码拨号:先调 contact(purpose=call),拿到明文再拨', (WidgetTester tester) async {
    final FakeCrmConsoleApi api = _api();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('138****1234'));
    await tester.pumpAndSettle();

    expect(api.contacts.single.memberId, 42);
    expect(api.contacts.single.purpose, 'call');
    expect(api.contactPhone, '13812341234');
  });

  testWidgets('点复制:换明文走 purpose=copy,复制的是明文号', (WidgetTester tester) async {
    final FakeCrmConsoleApi api = _api();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.doc_on_doc));
    await tester.pumpAndSettle();

    expect(api.contacts.single.purpose, 'copy');
    expect(find.text('已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('号码取不到:说清是「号码没能取到」并把后端原因带上', (WidgetTester tester) async {
    final FakeCrmConsoleApi api = _api(
      failures: <String, String>{'revealContact': '今日取号次数已达上限'},
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('138****1234'));
    await tester.pumpAndSettle();

    expect(find.textContaining('号码没能取到'), findsOneWidget);
    expect(find.textContaining('今日取号次数已达上限'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}

FakeCrmConsoleApi _api({Map<String, String>? failures}) => FakeCrmConsoleApi(
  failures: failures,
  page: FakeCrmConsoleApi.pageOf(<Map<String, dynamic>>[
    FakeCrmConsoleApi.rowJson(memberId: 42, phone: '138****1234'),
  ]),
);

Widget _app(FakeCrmConsoleApi api) {
  return ProviderScope(
    overrides: <dynamic>[
      merchantCrmAccessProvider.overrideWith(
        (ref) async => const MerchantCrmAccess(
          active: true,
          canReadCrm: true,
          canSegmentCrm: true,
          canExportCrm: true,
          canWriteMarketing: true,
          canManageCoupons: true,
        ),
      ),
      merchantCrmConsoleApiProvider.overrideWithValue(api),
    ].cast(),
    child: const MaterialApp(home: MerchantCustomerPage()),
  );
}
