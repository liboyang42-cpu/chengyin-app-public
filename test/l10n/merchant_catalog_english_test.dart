import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/data/models/merchant_apply.dart';
import 'package:chengyin_app/data/models/merchant_recruit.dart';
import 'package:chengyin_app/feature/merchant/merchant_registrations_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_registration_edit_page.dart';
import 'package:chengyin_app/feature/merchant/project_home_page.dart';
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
  Future<String> updateTopicRegistration(Map<String, dynamic> body) async {
    saved = body;
    return '服务器保存回执';
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('English applications preserve rejection content and filter wire values', (tester) async {
    final requested = <RegistrationListFilter>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantRegistrationsProvider.overrideWith((ref, filter) async {
        requested.add(filter);
        return const [TopicRegistration(id: 7, topicId: 3, status: 2,
          topicName: '原始主题', reason: '原始驳回理由')];
      })],
      child: _host(const MerchantRegistrationsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('原始主题'), findsOneWidget);
    expect(find.text('Rejection reason: 原始驳回理由'), findsOneWidget);
    expect(find.text('Cancel application'), findsOneWidget);
    await tester.tap(find.text('Ended'));
    await tester.pumpAndSettle();
    expect(requested.last, RegistrationListFilter.finished);
    expect(requested.last.wire, '4');
  });

  testWidgets('unknown application status does not gain actions after localization', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [merchantRegistrationsProvider.overrideWith((ref, filter) async => const [
        TopicRegistration(id: 7, topicId: 3),
      ])],
      child: _host(const MerchantRegistrationsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Status unknown'), findsOneWidget);
    expect(find.text('Cancel application'), findsNothing);
    expect(find.byKey(const Key('registration-edit-7')), findsNothing);
  });

  testWidgets('English edit form saves original content and preserves the field whitelist', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        merchantApiProvider.overrideWithValue(api),
        merchantRegistrationDetailProvider.overrideWith((ref, id) async => const MerchantRegistrationDetail(
          id: 7, topicId: 3, status: 2, topicName: '原始主题', reason: '原始驳回理由',
          addressName: '原始场地', address: '门牌12号', activityDesc: '原始接待内容',
          longitude: '121.1234', latitude: '31.5678', limitNum: 12,
          startDate: '2026-10-01', endDate: '2026-10-02',
        )),
      ],
      child: _host(const MerchantRegistrationEditPage(registrationId: 7)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Venue name (required)'), findsOneWidget);
    expect(find.text('Rejection reason: 原始驳回理由'), findsOneWidget);
    expect(find.text('承接的路线、站点和玩法模板不能在这里改;分成与结算也不由报名内容决定。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-edit-save')));
    await tester.pumpAndSettle();
    expect(api.saved, {
      'id': 7, 'topicId': 3, 'addressName': '原始场地', 'address': '门牌12号',
      'activityDesc': '原始接待内容', 'longitude': '121.1234', 'latitude': '31.5678',
      'limitNum': 12, 'picUrl': '',
    });
    expect(find.text('服务器保存回执'), findsOneWidget);
  });

  testWidgets('project keeps both roles and backend counts and dates in English', (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [projectHomeProvider.overrideWith((ref, id) async => {
        'topic': {'name': '未命名主题', 'city': '上海', 'circleThemeCode': 'A', 'circleReviewedAt': '2026-09-29T12:30:00'},
        'host': {'recruit': {'nodeFilled': 2, 'nodeTotal': 4, 'pendingCount': 3}, 'players': {'paidCount': 6}},
        'join': {'registration': {'addressName': '我的门店'}},
      })],
      child: _host(const ProjectHomePage(topicId: 3, scope: 'MERCHANT')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Organized by me'), findsOneWidget);
    expect(find.text('Hosted by me'), findsOneWidget);
    expect(find.text('2 / 4 stops assigned, 3 merchants awaiting confirmation'), findsOneWidget);
    expect(find.text('View player list (6 people)'), findsOneWidget);
    expect(find.text('Reviewed 2026-09-29'), findsOneWidget);
    expect(find.text('未命名主题'), findsOneWidget);
    expect(find.text('我的门店'), findsOneWidget);
  });
}
