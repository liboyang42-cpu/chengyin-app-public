import 'package:dio/dio.dart';

import 'app_localizations.dart';

/// App-owned summary and original external detail have separate provenance.
/// Never infer authentication/business meaning from message text or business codes.
class ErrorPresentation {
  const ErrorPresentation({required this.summary, this.detail, this.detailLabel});
  final String summary;
  final String? detail;
  final String? detailLabel;

  String get noticeText => detail == null
      ? summary
      : '$summary\n$detailLabel\n$detail';
}

ErrorPresentation presentError(
  Object error,
  AppLocalizations strings, {
  String? fallback,
  // Only pass a known API-layer message, never an arbitrary exception stack.
  // Legacy wrappers may contain app fallbacks, so do not claim server origin.
  String? originalApiMessage,
}) {
  var summary = fallback ?? strings.operationFailed;
  String? detail = originalApiMessage;
  var label = strings.errorOriginalMessage;
  if (error is DioException) {
    if (error.response?.statusCode == 401) {
      summary = strings.loginExpired;
    } else if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      summary = strings.networkError;
    }
    final data = error.response?.data;
    final message = data is Map ? data['msg'] : null;
    if (message is String && message.trim().isNotEmpty) {
      detail = message; // Preserve original whitespace and language verbatim.
      label = strings.originalServerMessage;
    }
  }
  if (detail == null || detail.trim().isEmpty) {
    return ErrorPresentation(summary: summary);
  }
  return ErrorPresentation(summary: summary, detail: detail, detailLabel: label);
}

/// Migration bridge only for API methods that throw Exception(message).
/// Known structured/transport errors must use their own message field instead.
String? legacyApiMessage(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : null;
}
