import 'package:dio/dio.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/api/club_api.dart';
import 'package:chengyin_app/data/api/registration_api.dart';
import 'package:chengyin_app/data/models/registration_read_failure.dart';
import 'package:chengyin_app/feature/orders/registration_order_strings.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English ticket fallback does not translate identical server text', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        expect(localizedOrderError(context, ClubApiException('local-only-sentinel', isLocal: true)), isNot(contains('local-only-sentinel')));
        final local = RegistrationReadFailure.fromResponse(RegistrationReadKind.detail, {'code': 500}, '票券详情加载失败');
        final remote = RegistrationReadFailure.fromResponse(RegistrationReadKind.detail,
          {'code': 500, 'msg': '票券详情加载失败'}, '票券详情加载失败');
        expect(localizedOrderError(context, local), 'Could not load ticket details');
        expect(localizedOrderError(context, remote), endsWith('票券详情加载失败'));
        final englishRemote = RegistrationReadFailure.fromResponse(RegistrationReadKind.routeTickets,
          {'msg': 'Token permission requires manual review'}, '路线票加载失败');
        final wallet = describeWalletFailure(englishRemote, WalletFailureKind.route);
        expect(wallet.kind, isNull, reason: 'Message text is not an authentication code');
        expect(wallet.message, 'Token permission requires manual review');
        final legacy = describeWalletFailure(Exception('token failure requires review'), WalletFailureKind.route);
        expect(legacy.kind, isNull);
        expect(legacy.message, 'token failure requires review');
        final network = describeWalletFailure(DioException.connectionError(requestOptions: RequestOptions(path: '/test'), reason: 'private internal detail'), WalletFailureKind.route);
        expect(network.kind, WalletFailureKind.network);
        expect(network.message, isNot(contains('private internal detail')));
        final sameAsDefault = describeWalletFailure(RegistrationReadFailure.fromResponse(
          RegistrationReadKind.activityTickets, {'msg': '活动票加载失败'}, '活动票加载失败'), WalletFailureKind.activity);
        expect(sameAsDefault.kind, isNull);
        expect(sameAsDefault.message, '活动票加载失败');
        expect(localizedOrderError(context, const RegistrationCheckoutException(409, '报名失败', hasServerMessage: false)), 'The registration or payment request did not complete');
        expect(localizedOrderError(context, const RegistrationCheckoutException(409, '报名失败')), endsWith('报名失败'));
        expect(localizedOrderError(context, const RegistrationFollowFailure('关注状态没确认下来:Original', originalMessage: '  Original  ')), endsWith('  Original  '));
        expect(localizedOrderError(context, const RegistrationReadFailure(RegistrationReadKind.quote, '没能取得报价', hasServerMessage: false)), 'Could not retrieve the quote');
        expect(localizedOrderError(context, const FormatException('private field detail')), isNot(contains('private field detail')));
        return const SizedBox();
      }),
    ));
    expect(tester.takeException(), isNull);
  });
}
