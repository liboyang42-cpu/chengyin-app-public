import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/address_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/deregistration.dart';
import 'package:chengyin_app/data/models/profile_detail.dart';
import 'package:chengyin_app/feature/account/address_edit_page.dart';
import 'package:chengyin_app/feature/account/address_list_page.dart';
import 'package:chengyin_app/feature/account/deregister_page.dart';
import 'package:chengyin_app/feature/account/inviter_sheet.dart';
import 'package:chengyin_app/feature/profile/profile_edit_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixed_auth.dart';

class _AddressApi extends Fake implements AddressApi {
  Map<String, Object?>? saved;

  @override
  Future<MemberAddress> info(int id) async => const MemberAddress(
    id: 7, fullName: '小李', mobilePhone: '13800001111',
    province: '上海市', detailAddress: '南京西路', isDefault: true,
  );

  @override
  Future<void> save({
    int? id,
    required String fullName,
    required String mobilePhone,
    String? province,
    String? detailAddress,
    bool isDefault = false,
  }) async {
    saved = {
      'id': id, 'fullName': fullName, 'mobilePhone': mobilePhone,
      'province': province, 'detailAddress': detailAddress,
      'isDefault': isDefault,
    };
    throw Exception('服务端原文');
  }
}

class _AccountApi extends Fake implements AccountApi {
  @override
  Future<DeregistrationStatus> deregisterStatus() async =>
      const DeregistrationStatus(
        status: 'PENDING', blockers: [], executeAfter: '2026-10-07 12:00:00',
      );
}

class _EligibleAccountApi extends Fake implements AccountApi {
  @override
  Future<DeregistrationStatus> deregisterStatus() async =>
      const DeregistrationStatus(status: 'NORMAL', blockers: []);

  @override
  Future<DeregistrationStatus> deregisterPrecheck() async =>
      const DeregistrationStatus(status: 'ELIGIBLE', blockers: []);

  @override
  Future<void> agreeCancellationNotice(String requestId) async {}
}

class _RegistrationApi extends Fake implements RegistrationApi {
  final List<String> submitted = [];

  @override
  Future<void> setInviter(String inviterId) async {
    submitted.add(inviterId);
    throw Exception('服务端原文');
  }
}

Widget _host(Widget page, List<dynamic> overrides) => ProviderScope(
  overrides: [signedInAuthOverride(), ...overrides].cast(),
  child: MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: page,
  ),
);

void main() {
  testWidgets('English deletion notice and confirmation preserve the cooling-off terms', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(const DeregisterPage(), [
      accountApiProvider.overrideWithValue(_EligibleAccountApi()),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('seven-day cooling-off period'), findsOneWidget);
    expect(find.textContaining('pending withdrawal'), findsOneWidget);
    expect(find.textContaining('merchant or club roles'), findsOneWidget);
    await tester.tap(find.byType(CupertinoCheckbox));
    await tester.pump();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('deregister-code-field')), '123456');
    await tester.ensureVisible(find.text('Submit deletion request'));
    await tester.tap(find.text('Submit deletion request'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm account deletion?'), findsOneWidget);
    expect(find.textContaining('your personal information will be anonymized'), findsOneWidget);
    expect(find.textContaining('withdraw your request.'), findsOneWidget);
    await tester.tap(find.text('Keep my account'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('English participant editing preserves hidden fields and server text', (
    tester,
  ) async {
    final api = _AddressApi();
    await tester.pumpWidget(_host(const AddressEditPage(addressId: 7), [
      addressApiProvider.overrideWithValue(api),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Participant details'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNothing);
    await tester.enterText(find.byType(CupertinoTextField).first, 'Alex');
    await tester.tap(find.text('Save participant details'));
    await tester.pumpAndSettle();
    expect(api.saved, {
      'id': 7, 'fullName': 'Alex', 'mobilePhone': '13800001111',
      'province': '上海市', 'detailAddress': '南京西路', 'isDefault': true,
    });
    expect(find.text('Participant details were not saved'), findsOneWidget);
    expect(find.text('服务端原文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English deletion pending state preserves the server timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const DeregisterPage(), [
      accountApiProvider.overrideWithValue(_AccountApi()),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Account deletion request pending'), findsOneWidget);
    expect(
      find.text('Account deletion is scheduled for 2026-10-07 12:00:00'),
      findsOneWidget,
    );
    expect(find.text('Cancel deletion request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English inviter validation preserves raw submitted identity', (
    tester,
  ) async {
    final api = _RegistrationApi();
    await tester.pumpWidget(_host(
      Builder(builder: (context) => CupertinoPageScaffold(
        child: Center(child: CupertinoButton(
          onPressed: () => showInviterSheet(context),
          child: const Text('Open'),
        )),
      )),
      [
        registrationApiProvider.overrideWithValue(api),
        myProfileProvider.overrideWith((ref) async => ProfileDetail.fromJson({
          'id': 42, 'nickname': 'Account owner',
        })),
      ],
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inviter-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an invitation code'), findsWidgets);
    expect(api.submitted, isEmpty);
    await tester.enterText(find.byKey(const Key('inviter-code')), '42');
    await tester.tap(find.byKey(const Key('inviter-submit')));
    await tester.pumpAndSettle();
    expect(find.text('You cannot use your own invitation code'), findsOneWidget);
    expect(api.submitted, isEmpty);
    await tester.enterText(find.byKey(const Key('inviter-code')), '007');
    await tester.tap(find.byKey(const Key('inviter-submit')));
    await tester.pumpAndSettle();
    expect(api.submitted, ['007']);
    expect(find.text('服务端原文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
