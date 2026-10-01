import 'package:chengyin_app/data/api/club_api.dart';
import 'package:dio/dio.dart';
import 'package:chengyin_app/data/models/registration_cancellation_outcome.dart';
import 'package:chengyin_app/feature/club/registration_cancellation_display.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cash = <String, (String, String)>{
    'NOT_NEEDED': ('无需现金退款', 'No cash refund is needed'),
    'DISPATCH_PENDING': ('现金退款已受理，尚未派发', 'Cash refund accepted; awaiting dispatch'),
    'DISPATCHING': ('现金退款正在派发，尚未确认到账', 'Cash refund is being dispatched; receipt is unconfirmed'),
    'PROCESSING': ('现金退款渠道处理中，尚未确认到账', 'Cash refund is processing with the payment provider; receipt is unconfirmed'),
    'SUCCESS': ('现金退款已确认到账', 'Cash refund receipt is confirmed'),
    'PENDING_MANUAL': ('现金退款失败，待人工处理', 'Cash refund failed; awaiting manual handling'),
    'MANUAL_HANDLED': ('现金退款已人工处理，待复核', 'Cash refund handled manually; awaiting verification'),
    'MANUAL_VERIFIED': ('现金退款已完成人工复核', 'Manual cash refund verification is complete'),
    'MANUAL_REVIEW': ('本单未自动退款，已转人工处理', 'No automatic cash refund was made; referred for manual handling'),
    'UNCONFIRMED': ('现金退款结果尚未确认', 'Cash refund outcome is unconfirmed'),
  };
  const cancellation = <String, (String, String)>{
    'CANCELLED': ('报名已取消', 'Registration cancelled'),
    'MANUAL_REVIEW': ('报名取消已转人工处理', 'Registration cancellation is under manual review'),
    'UNCONFIRMED': ('报名取消结果尚未确认', 'Registration cancellation is unconfirmed'),
  };
  const points = <String, (String, String)>{
    'NOT_NEEDED': ('本单未使用积分，无需返还', 'No points were used; no points return is needed'),
    'RETURNED': ('本单已用积分已返还', 'Points used on this order have been returned'),
    'PARTIAL': ('本单积分已部分返还，其余尚未确认', 'Some points have been returned; the remainder is unconfirmed'),
    'UNCONFIRMED': ('积分返还结果尚未确认', 'Points return outcome is unconfirmed'),
  };
  for (final language in ['zh', 'en']) {
    testWidgets('$language cancellation statuses remain independent and preserve the original receipt', (tester) async {
      String expected((String, String) pair) => language == 'zh' ? pair.$1 : pair.$2;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          for (final entry in cancellation.entries) {
            expect(registrationCancellationStatusLabel(context, entry.key), expected(entry.value));
          }
          for (final entry in cash.entries) {
            expect(registrationCashRefundLabel(context, entry.key), expected(entry.value));
          }
          for (final entry in points.entries) {
            expect(registrationPointsRefundLabel(context, entry.key), expected(entry.value));
          }
          final local = registrationCancellationError(context, ClubApiException('local fallback sentinel', isLocal: true));
          expect(local, isNot(contains('local fallback sentinel')));
          final business = registrationCancellationError(context, ClubApiException('  Refund review required\nOriginal detail  '));
          expect(business, endsWith('  Refund review required\nOriginal detail  '));
          expect(registrationCancellationError(context, const FormatException('private parser detail')), isNot(contains('private parser detail')));
          final transport = DioException(requestOptions: RequestOptions(path: '/private-path'), error: 'private network detail');
          expect(registrationCancellationError(context, transport), isNot(contains('private network detail')));
          expect(registrationCancellationError(context, transport), isNot(contains('/private-path')));
          const original = '  后端原始回执\n保留空白  ';
          final notice = registrationCancellationNotice(context, const RegistrationCancellationOutcome(
            message: original, cancellationStatus: 'CANCELLED',
            cashRefundStatus: 'PROCESSING', pointsRefundStatus: 'PARTIAL',
          ));
          expect(notice, startsWith(expected(cancellation['CANCELLED']!)));
          expect(notice, contains(expected(cash['PROCESSING']!)));
          expect(notice, contains(expected(points['PARTIAL']!)));
          expect(notice, isNot(contains(expected(cash['SUCCESS']!))));
          expect(notice, endsWith(original));
          for (final status in ['', 'FUTURE_STATUS', 'success']) {
            expect(registrationCashRefundLabel(context, status), expected(cash['UNCONFIRMED']!));
            expect(registrationPointsRefundLabel(context, status), expected(points['UNCONFIRMED']!));
            expect(registrationCancellationStatusLabel(context, status), expected(cancellation['UNCONFIRMED']!));
          }
          final missing = RegistrationCancellationOutcome.fromResponse({'code': 200, 'msg': '已退款'});
          expect(registrationCancellationNotice(context, missing), startsWith(expected(cancellation['UNCONFIRMED']!)));
          expect(registrationCancellationNotice(context, missing), contains(expected(cash['UNCONFIRMED']!)));
          return const SizedBox();
        }),
      ));
      expect(tester.takeException(), isNull);
    });
  }
}
