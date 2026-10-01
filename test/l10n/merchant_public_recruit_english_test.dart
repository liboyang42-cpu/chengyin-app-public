import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/api/template_api.dart';
import 'package:chengyin_app/data/models/template.dart';
import 'package:chengyin_app/feature/merchant/merchant_public_home_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_recruit_sheets.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
class _MerchantApi implements MerchantApi {
  @override
  Future<Map<String, dynamic>> merchantInfo() async => {'address': '原始店址'};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _TemplateApi implements TemplateApi {
  @override
  Future<List<PlayTemplate>> myList() async => const [PlayTemplate(id: 11, title: '原始玩法')];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main() {
  testWidgets('invalid public link stays local and explains missing parameters in English', (tester) async {
    var reads = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantPublicHomeProvider.overrideWith((ref, id) async { reads++; return {}; })],
      child: _host(const MerchantPublicHomePage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Invalid link'), findsOneWidget);
    expect(reads, 0);
  });
  testWidgets('public profile keeps server text and absent business status', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantPublicHomeProvider.overrideWith((ref, id) async => {
        'id': 7, 'memberId': 91, 'name': '商家', 'storyTitle': '介绍',
        'description': '原始介绍', 'capacity': 12, 'availableTime': '周末 09:00-18:00',
        'demand': '原始合作需求', 'npc': {'name': '原始角色', 'greeting': '原始问候'},
      })],
      child: _host(const MerchantPublicHomePage(memberId: 91)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('商家'), findsOneWidget);
    expect(find.text('介绍'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    expect(find.text('Closed'), findsNothing);
    expect(find.text('Capacity: 12'), findsOneWidget);
    expect(find.text('Available times: 周末 09:00-18:00'), findsOneWidget);
    expect(find.text('Partnership needs: 原始合作需求'), findsOneWidget);
    expect(find.text('原始问候'), findsOneWidget);
    expect(find.byKey(const Key('merchant-npc-chat-entry')), findsNothing);
  });
  testWidgets('English supply form retains financial disclosure and exact per-visit amount', (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(ProviderScope(child: _host(Consumer(builder: (context, ref, _) => Scaffold(
      body: CupertinoButton(child: const Text('open'), onPressed: () async {
        result = await showChapterOfferForm(context, ref, chapterId: 7,
          chapterName: '原始章节', termsMode: 'REVSHARE');
      }),
    )))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Payment per visit (required)'), findsOneWidget);
    expect(find.text('Amount the platform pays per redeemed visit'), findsOneWidget);
    expect(tester.widget<CupertinoButton>(find.byKey(const Key('offer-submit'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('offer-fee')), '12.50');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-submit')));
    await tester.pumpAndSettle();
    expect(result, {'chapterId': 7, 'termsMode': 'REVSHARE', 'perHeadFee': 12.5});
  });
  testWidgets('English chapter form submits original node and template without invented XP input', (tester) async {
    ChapterNodeDraft? result;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      merchantApiProvider.overrideWithValue(_MerchantApi()),
      templateApiProvider.overrideWithValue(_TemplateApi()),
    ], child: _host(Consumer(builder: (context, ref, _) => Scaffold(
      body: CupertinoButton(child: const Text('open'), onPressed: () async {
        result = await showChapterApplyForm(context, ref, chapterName: '原始章节');
      }),
    )))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Stop name (required)'), findsOneWidget);
    expect(tester.widget<CupertinoButton>(find.byKey(const Key('apply-submit'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('apply-node-name')), '原始点位');
    await tester.tap(find.byKey(const Key('apply-template-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('原始玩法').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-submit')));
    await tester.pumpAndSettle();
    expect(result?.name, '原始点位');
    expect(result?.templateId, 11);
    expect(result?.address, '原始店址');
  });
}
