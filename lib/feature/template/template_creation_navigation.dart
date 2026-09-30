import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 以小程序 `redirectTo` 的栈语义替换模板创建步骤。
///
/// go_router 的 `replace` 会给新步骤创建新 Completer；如果不中继，
/// 最早 `push<bool>` 的调用方会在 intro → name → edit 后永远等不到
/// 编辑器的返回值。这里只中继结果，页面栈仍是真正的 replace。
void replaceTemplateCreationStep(BuildContext context, String location) {
  final GoRouter router = GoRouter.of(context);
  final ImperativeRouteMatch? previous = _lastImperativeMatch(
    router.routerDelegate.currentConfiguration.matches,
  );
  final Future<Object?> next = router.replace<Object?>(location);
  if (previous == null) return;

  unawaited(
    next.then<void>(
      (Object? value) {
        if (!previous.completer.isCompleted) previous.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!previous.completer.isCompleted) {
          previous.completer.completeError(error, stackTrace);
        }
      },
    ),
  );
}

ImperativeRouteMatch? _lastImperativeMatch(List<RouteMatchBase> matches) {
  for (final RouteMatchBase match in matches.reversed) {
    if (match is ImperativeRouteMatch) return match;
    if (match is ShellRouteMatch) {
      final ImperativeRouteMatch? nested = _lastImperativeMatch(match.matches);
      if (nested != null) return nested;
    }
  }
  return null;
}
