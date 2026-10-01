import '../data/api/im_api.dart';
import 'app_localizations.dart';
import 'error_presentation.dart';

String imErrorText(Object error, AppLocalizations strings) {
  if (error is ImApiException) {
    return switch (error.localReason) {
      null => error.message,
      ImLocalFailure.request => strings.imApiRequest,
      ImLocalFailure.operation => strings.imApiOperation,
      ImLocalFailure.report => strings.imApiReport,
      ImLocalFailure.delete => strings.imApiDelete,
      ImLocalFailure.start => strings.imApiStart,
      ImLocalFailure.missingConversation => strings.imApiMissingConversation,
      ImLocalFailure.uploadMissingUrl => strings.imApiUploadMissingUrl,
    };
  }
  final legacy = legacyApiMessage(error);
  if (legacy != null) return legacy;
  return presentError(error, strings).noticeText;
}

String imReceiptText(ImReceipt receipt, AppLocalizations strings) =>
  receipt.serverMessage ?? switch (receipt.kind) {
    ImReceiptKind.blocked => strings.imApiBlocked,
    ImReceiptKind.unblocked => strings.imApiUnblocked,
    ImReceiptKind.reported => strings.imApiReported,
    ImReceiptKind.muted => strings.imApiMuted,
    ImReceiptKind.unmuted => strings.imApiUnmuted,
    ImReceiptKind.deleted => strings.imApiDeleted,
  };
