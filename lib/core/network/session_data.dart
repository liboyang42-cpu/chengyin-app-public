import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feature/auth/auth_controller.dart';
import 'request_session_scope.dart';

/// Data-cache identity only. Never make Dio, token storage, or AuthApi watch this.
/// Public APIs can still be constructed while signed out; protected leaf reads
/// use [readSessionData] to reject missing or transitioning owners.
typedef SessionDataKey = ({int? userId, bool loading, bool initialized, String? role});

final sessionDataKeyProvider = Provider<SessionDataKey>((ref) => ref.watch(
  authControllerProvider.select((state) => (
    userId: state.user?.id,
    loading: state.loading,
    initialized: state.initialized,
    role: state.user?.effectiveRole,
  )),
));

class SessionDataUnavailable implements Exception {
  const SessionDataUnavailable();
}

/// Establish both a reactive cache dependency and a dispatch/completion guard.
/// API methods must forward RequestSessionScope.options() to Dio themselves.
RequestSessionScope watchSessionDataScope(Ref ref) {
  final key = ref.watch(sessionDataKeyProvider);
  final owner = key.userId;
  if (owner == null || key.loading || !key.initialized) {
    throw const SessionDataUnavailable();
  }
  final authScope = ref.read(authControllerProvider.notifier).requestScope(owner);
  final scope = RequestSessionScope(() => ref.mounted &&
      ref.read(sessionDataKeyProvider) == key && authScope.isCurrent());
  if (!scope.isCurrent()) throw const SessionDataUnavailable();
  return scope;
}

Future<T> readSessionData<T>(Ref ref, Future<T> Function() read) async {
  final scope = watchSessionDataScope(ref);
  final result = await RequestSessionScope.run(scope, read);
  if (!scope.isCurrent()) throw const SessionDataUnavailable();
  return result;
}
