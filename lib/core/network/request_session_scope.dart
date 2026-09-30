import 'dart:async';

import 'package:dio/dio.dart';

/// Captured session identity for account-owned mutations. The callback contains
/// no credentials and becomes false as soon as authentication transitions.
class RequestSessionScope {
  const RequestSessionScope(this.isCurrent, {this.requireAuthentication = true});
  final bool requireAuthentication;
  final bool Function() isCurrent;
  static const extraKey = 'chengyin.requestSessionScope';
  static final Object _zoneKey = Object();

  /// A request scope follows one asynchronous action, never a shared Dio client.
  static Future<T> run<T>(RequestSessionScope scope, Future<T> Function() action) =>
      runZoned(action, zoneValues: <Object, Object>{_zoneKey: scope});

  static RequestSessionScope? get current =>
      Zone.current[_zoneKey] as RequestSessionScope?;

  /// Merge the guard into existing options without changing response/content types.
  static Options? options([Options? base]) {
    final scope = current;
    if (scope == null) return base;
    return (base ?? Options()).copyWith(extra: <String, dynamic>{
      ...?base?.extra,
      extraKey: scope,
    });
  }
}
