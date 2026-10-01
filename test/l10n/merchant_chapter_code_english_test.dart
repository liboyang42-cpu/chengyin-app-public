import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/chapter_node_code_sheet.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements MerchantApi {
  _Api({this.message, this.data = const {}});
  final String? message;
  final Map<String, dynamic> data;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> chapterNodeLiveCheckinCode(int nodeId) async {
    calls++;
    if (message != null) throw MerchantApiException(message!);
    return data;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Future<void> _open(WidgetTester tester, _Api api) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [merchantApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Scaffold(body: CupertinoButton(
        child: const Text('open'),
        onPressed: () => showChapterNodeCodeSheet(context, nodeId: 5, kind: ChapterNodeCodeKind.liveCheckin),
      ))),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
void main() {
  testWidgets('missing QR result uses English local fallback and offers retry', (tester) async {
    await _open(tester, _Api());
    expect(find.text('Could not generate a check-in code yet'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-save')), findsNothing);
  });
  for (final message in ['打卡码暂时没能生成', 'Server refused this code']) {
    testWidgets('server QR message remains verbatim: $message', (tester) async {
      await _open(tester, _Api(message: message));
      expect(find.text(message), findsOneWidget);
      expect(find.text('Could not generate a check-in code yet'), findsNothing);
    });
  }
  testWidgets('live code keeps exact content and server expiry countdown in English', (tester) async {
    final api = _Api(data: {'code': '原始-CODE-0123', 'ttlMs': 10000});
    await _open(tester, api);
    expect(find.text('原始-CODE-0123'), findsOneWidget);
    expect(find.text('Refreshes automatically in 10 seconds'), findsOneWidget);
    expect(find.byKey(const Key('chapter-node-code-save')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Refreshes automatically in 9 seconds'), findsOneWidget);
    expect(api.calls, 1);
    await tester.tap(find.byKey(const Key('chapter-node-code-close')));
    await tester.pumpAndSettle();
  });
}
