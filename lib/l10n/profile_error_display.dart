import '../feature/profile/profile_controller.dart';
import 'app_localizations.dart';
import 'error_presentation.dart';

/// Only explicit local reasons select translated copy. Server text stays original.
String? profileFailureSummary(Object error, AppLocalizations strings) =>
    error is ProfileLoadFailure ? switch (error.reason) {
      ProfileLoadReason.userInfoRejected => strings.profileFailureUserInfo,
      ProfileLoadReason.missingUser => strings.profileFailureMissingUser,
      ProfileLoadReason.postsFailed => strings.profileFailurePosts,
    } : null;

String? profileOriginalMessage(Object error) => error is ProfileLoadFailure
    ? error.backendMessage : legacyApiMessage(error);
