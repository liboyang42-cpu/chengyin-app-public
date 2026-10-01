import '../../data/api/group_code_api.dart';
import 'package:flutter/widgets.dart';

import '../../core/network/dio_client.dart';
import '../../data/api/club_api.dart';
import '../../l10n/strings.dart';

String clubApiErrorMessage(BuildContext context, Object error, {String? fallback}) {
  final strings = stringsOf(context);
  final String? groupLocalMessage = error is GroupCodePermissionException && error.isLocalFallback ? error.message
      : error is GroupCodeApiException && error.isLocalFallback ? error.message : null;
  if (groupLocalMessage != null) {
    return switch (groupLocalMessage) {
      '当前账号没有出码权限' => strings.boundedApiGroupPermission,
      '出码失败' => strings.boundedApiGroupIssue,
      '场次加载失败' => strings.boundedApiGroupActivities,
      '核销失败' => strings.boundedApiGroupRedeem,
      _ => groupLocalMessage,
    };
  }
  if (error is GroupCodeEmptyDownloadException) return strings.boundedApiCodeDownload;
  if (error is ClubLocalApiFailure) {
    return switch (error.code) {
      'request' => strings.clubApiFailureRequest,
      'remove' => strings.clubApiFailureRemove,
      'role' => strings.clubApiFailureRole,
      'load' => strings.clubApiFailureLoad,
      'send' => strings.clubApiFailureSend,
      'delete' => strings.clubApiFailureDelete,
      'report' => strings.clubApiFailureReport,
      'action' => strings.clubApiFailureAction,
      'publish' => strings.clubApiFailurePublish,
      'chat' => strings.clubApiFailureChat,
      _ => fallback ?? strings.clubApiFailureRequest,
    };
  }
  if (error is ClubApiException) {
    return error.isLocal ? (fallback ?? strings.clubApiFailureRequest) : error.message;
  }
  return fallback == null
      ? error.toString().replaceFirst('Exception: ', '')
      : friendlyOrBackendMessage(error, fallback: fallback);
}

Future<T> clubApiAction<T>(BuildContext context, Future<T> Function() action) {
  final strings = stringsOf(context);
  return ClubApiLocalCopy.run({
    'removed': strings.clubApiSuccessRemoved,
    'adminSet': strings.clubApiSuccessAdminSet,
    'adminRemoved': strings.clubApiSuccessAdminRemoved,
    'deleted': strings.clubApiSuccessDeleted,
    'reported': strings.clubApiSuccessReported,
    'updated': strings.clubApiSuccessUpdated,
    'pinned': strings.clubApiSuccessPinned,
    'unpinned': strings.clubApiSuccessUnpinned,
  }, action);
}
