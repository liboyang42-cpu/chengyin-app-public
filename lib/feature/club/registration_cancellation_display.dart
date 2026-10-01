import 'package:flutter/widgets.dart';

import '../../data/models/registration_cancellation_outcome.dart';
import '../../data/api/club_api.dart';
import '../../l10n/error_presentation.dart';
import '../../l10n/strings.dart';

/// Independent facts from the published cancellation feedback. No cross-field
/// inference: CANCELLED never proves cash arrival or points return.
String registrationCancellationStatusLabel(BuildContext context, String status) => switch (status) {
  'CANCELLED' => stringsOf(context).clubCancellationRegistrationCancelled,
  'MANUAL_REVIEW' => stringsOf(context).clubCancellationRegistrationManualReview,
  _ => stringsOf(context).clubCancellationRegistrationUnconfirmed,
};

String registrationCashRefundLabel(BuildContext context, String status) => switch (status) {
  'NOT_NEEDED' => stringsOf(context).clubCancellationCashNotNeeded,
  'DISPATCH_PENDING' => stringsOf(context).clubCancellationCashDispatchPending,
  'DISPATCHING' => stringsOf(context).clubCancellationCashDispatching,
  'PROCESSING' => stringsOf(context).clubCancellationCashProcessing,
  'SUCCESS' => stringsOf(context).clubCancellationCashSuccess,
  'PENDING_MANUAL' => stringsOf(context).clubCancellationCashPendingManual,
  'MANUAL_HANDLED' => stringsOf(context).clubCancellationCashManualHandled,
  'MANUAL_VERIFIED' => stringsOf(context).clubCancellationCashManualVerified,
  'MANUAL_REVIEW' => stringsOf(context).clubCancellationCashManualReview,
  _ => stringsOf(context).clubCancellationCashUnconfirmed,
};

String registrationPointsRefundLabel(BuildContext context, String status) => switch (status) {
  'NOT_NEEDED' => stringsOf(context).clubCancellationPointsNotNeeded,
  'RETURNED' => stringsOf(context).clubCancellationPointsReturned,
  'PARTIAL' => stringsOf(context).clubCancellationPointsPartial,
  _ => stringsOf(context).clubCancellationPointsUnconfirmed,
};

/// Preserve original feedback independently of the translated structured facts.
/// Missing/forward-compatible statuses stay unconfirmed, including code 200
/// responses with absent data. No amount, currency or timing promises are added.
String registrationCancellationNotice(BuildContext context, RegistrationCancellationOutcome outcome) {
  final lines = <String>[
    registrationCancellationStatusLabel(context, outcome.cancellationStatus),
    registrationCashRefundLabel(context, outcome.cashRefundStatus),
    registrationPointsRefundLabel(context, outcome.pointsRefundStatus),
  ];
  if (outcome.message.trim().isNotEmpty) {
    lines.add(stringsOf(context).originalServerMessage);
    lines.add(outcome.message);
  }
  return lines.join('\n');
}

/// ClubApiException owns an API message; arbitrary exceptions do not. Preserve
/// that message exactly, including English and whitespace, without exposing
/// parser/transport implementation details or guessing a refund result.
String registrationCancellationError(BuildContext context, Object error) =>
    presentError(
      error,
      stringsOf(context),
      fallback: stringsOf(context).clubCheckinRefundUnknown,
      originalApiMessage: error is ClubApiException && !error.isLocal ? error.message : null,
    ).noticeText;
