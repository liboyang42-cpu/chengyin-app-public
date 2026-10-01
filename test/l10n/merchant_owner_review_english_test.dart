import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/topic_chapter_applications_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

class _Api implements MerchantApi {
  Map<String, dynamic>? audit;
  @override
  Future<Map<String, dynamic>> auditChapterNode({required int nodeId, required bool approve, String? reason}) async {
    audit = {'nodeId': nodeId, 'approve': approve, 'reason': reason};
    return {};
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
Widget _page({List<Map<String, dynamic>> applications = const [], List<Map<String, dynamic>> nodes = const [], List<Map<String, dynamic>> invitable = const [], MerchantApi? api}) => ProviderScope(
  overrides: [
    topicChapterApplicationsProvider.overrideWith((ref, id) async => applications),
    pendingChapterNodesProvider.overrideWith((ref, id) async => nodes),
    invitableMerchantsProvider.overrideWith((ref, id) async => invitable),
    if (api != null) merchantApiProvider.overrideWithValue(api),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const TopicChapterApplicationsPage(topicId: 42),
  ),
);
void main() {
  testWidgets('English owner review keeps unknown status unactionable and raw submitted notes', (tester) async {
    await tester.pumpWidget(_page(applications: [
      {'id': 1, 'merchantName': '未命名商家', 'chapterName': '未命名章节', 'message': '原始说明', 'auditRemark': '原始备注'},
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Status unknown'), findsOneWidget);
    expect(find.text('未命名商家'), findsOneWidget);
    expect(find.text('Application note: 原始说明'), findsOneWidget);
    expect(find.text('Review note: 原始备注'), findsOneWidget);
    expect(find.byKey(const Key('owner-approve-1')), findsNothing);
    expect(find.byKey(const Key('owner-reject-1')), findsNothing);
  });
  testWidgets('English stop rejection requires a reason and submits it verbatim', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api();
    await tester.pumpWidget(_page(api: api, nodes: [{'id': 7, 'name': '原始点位'}]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stops to review'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('owner-node-reject-7')));
    await tester.pumpAndSettle();
    expect(find.text('Reason (sent to the merchant verbatim)'), findsOneWidget);
    expect(tester.widget<CupertinoButton>(find.byKey(const Key('owner-reject-confirm'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('owner-reject-reason')), '原始拒绝原因');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('owner-reject-confirm')));
    await tester.pumpAndSettle();
    expect(api.audit, {'nodeId': 7, 'approve': false, 'reason': '原始拒绝原因'});
    expect(find.text('Stop rejected'), findsOneWidget);
  });
  testWidgets('English invitations distinguish missing distance from rounded server distance', (tester) async {
    await tester.pumpWidget(_page(invitable: [
      {'memberId': 1, 'chapterId': 3, 'name': '原始商家甲', 'chapterName': '原始章节'},
      {'memberId': 2, 'chapterId': 3, 'name': '原始商家乙', 'chapterName': '原始章节', 'distance': 12.5},
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite merchants'));
    await tester.pumpAndSettle();
    expect(find.text('About 13 m'), findsOneWidget);
    expect(find.text('About 0 m'), findsNothing);
    expect(find.text('原始商家甲'), findsOneWidget);
    expect(find.text('原始商家乙'), findsOneWidget);
  });
}
