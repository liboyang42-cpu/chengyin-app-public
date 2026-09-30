import 'dart:async';

import 'package:flutter/services.dart';

typedef LiquidGlassPresenterCallback = FutureOr<void> Function(MethodCall call);

/// Owns the one Dart handler allowed for the shared native presenter channel.
///
/// Alert, sheet and popover register their event names here so enabling one
/// presenter cannot silently disconnect callbacks for another presenter.
final class LiquidGlassPresenterChannel {
  LiquidGlassPresenterChannel._();

  static const MethodChannel channel = MethodChannel('liquid-glass-presenter');
  static final Map<String, LiquidGlassPresenterCallback> _callbacks =
      <String, LiquidGlassPresenterCallback>{};
  static bool _installed = false;

  static void register(String method, LiquidGlassPresenterCallback callback) {
    _callbacks[method] = callback;
    if (_installed) return;
    _installed = true;
    channel.setMethodCallHandler((MethodCall call) async {
      final LiquidGlassPresenterCallback? handler = _callbacks[call.method];
      if (handler != null) await handler(call);
    });
  }
}
