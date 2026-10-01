import 'package:flutter/widgets.dart';

import '../../l10n/strings.dart';
import 'club_director_controller.dart';

String clubDirectorWriteMessage(BuildContext context, ClubDirectorState state) =>
    state.localWriteMessage == null ? state.writeMessage
        : _localMessage(context, state.localWriteMessage!);

String clubDirectorErrorMessage(BuildContext context, ClubDirectorState state) =>
    state.localErrorMessage == null ? state.errorText
        : _localMessage(context, state.localErrorMessage!);

String _localMessage(BuildContext context, ClubDirectorLocalMessage kind) => switch (kind) {
  ClubDirectorLocalMessage.legacyOwnerUnknown => stringsOf(context).clubDirectorLegacyOwnerUnknown,
  ClubDirectorLocalMessage.ownerRequired => stringsOf(context).clubDirectorMessageOwnerRequired,
  ClubDirectorLocalMessage.projectionMismatch => stringsOf(context).clubDirectorMessageProjectionMismatch,
  ClubDirectorLocalMessage.recoveredPending => stringsOf(context).clubDirectorMessageRecoveredPending,
  ClubDirectorLocalMessage.versionPending => stringsOf(context).clubDirectorMessageVersionPending,
  ClubDirectorLocalMessage.submitting => stringsOf(context).clubDirectorMessageSubmitting,
  ClubDirectorLocalMessage.storageFailed => stringsOf(context).clubDirectorMessageStorageFailed,
  ClubDirectorLocalMessage.resultPending => stringsOf(context).clubDirectorMessageResultPending,
  ClubDirectorLocalMessage.requestPending => stringsOf(context).clubDirectorMessageRequestPending,
  ClubDirectorLocalMessage.rejected => stringsOf(context).clubDirectorMessageRejected,
  ClubDirectorLocalMessage.readingReceipt => stringsOf(context).clubDirectorMessageReadingReceipt,
  ClubDirectorLocalMessage.stillPending => stringsOf(context).clubDirectorMessageStillPending,
  ClubDirectorLocalMessage.verificationUnavailable => stringsOf(context).clubDirectorMessageVerificationUnavailable,
  ClubDirectorLocalMessage.retryStorageFailed => stringsOf(context).clubDirectorMessageRetryStorageFailed,
  ClubDirectorLocalMessage.retrying => stringsOf(context).clubDirectorMessageRetrying,
  ClubDirectorLocalMessage.retryPending => stringsOf(context).clubDirectorMessageRetryPending,
  ClubDirectorLocalMessage.loadUnavailable => stringsOf(context).clubDirectorMessageLoadUnavailable,
  ClubDirectorLocalMessage.needsSession => stringsOf(context).clubDirectorMessageNeedsSession,
  ClubDirectorLocalMessage.networkUnavailable => stringsOf(context).clubDirectorMessageNetworkUnavailable,
};
