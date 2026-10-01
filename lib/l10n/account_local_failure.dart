import 'package:flutter/widgets.dart';

import '../data/models/account_local_failure.dart';
import 'strings.dart';

/// Translate only typed local validation failures. Keep supplied server copy,
/// including strings identical to the original Chinese fallback, untouched.
String accountFailureMessage(BuildContext context, Object error, {
  required String fallback,
}) {
  if (error is AccountLocalFailure) {
    final strings = stringsOf(context);
    return switch (error.kind) {
      AccountLocalFailureKind.playerCode => strings.settingsResidualCodeUnavailable,
      AccountLocalFailureKind.roamRevocation => strings.accountRoamRevocationUnconfirmed,
      AccountLocalFailureKind.merchantConsent => strings.playSessionConsentUnknown,
    };
  }
  final text = error.toString();
  if (text.startsWith('Exception: ')) {
    final message = text.substring('Exception: '.length);
    if (message.trim().isNotEmpty) return message;
  }
  return fallback;
}
