import 'dart:async';

import 'package:flutter/material.dart';

import 'shares/liquid_glass_icon.dart';
import 'utils/liquid_glass_presenter_channel.dart';
import 'utils/native_liquid_glass_utils.dart';

/// An action button for [LiquidGlassAlert].
class LiquidGlassAlertAction {
  /// Unique identifier.
  final String id;

  /// Display title.
  final String title;

  /// Optional icon. On iOS, only [NativeLiquidGlassIcon.sfSymbol] icons are
  /// rendered natively. Other icon types are shown in the Flutter fallback only.
  final NativeLiquidGlassIcon? icon;

  /// Whether this is a destructive action (shown in red).
  final bool isDestructive;

  /// Whether this is the cancel action.
  final bool isCancel;

  const LiquidGlassAlertAction({
    required this.id,
    required this.title,
    this.icon,
    this.isDestructive = false,
    this.isCancel = false,
  });

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'sfSymbolName': icon?.sfSymbolName,
      'isDestructive': isDestructive,
      'isCancel': isCancel,
    };
  }
}

/// Alert style.
enum LiquidGlassAlertStyle {
  /// Centered alert dialog.
  alert,

  /// Action sheet from bottom.
  actionSheet,
}

/// Shows a native iOS alert using UIAlertController with Liquid Glass effects
/// on iOS 26+.
///
/// Uses the shared LiquidGlassPresenter channel for modal presentation.
/// On non-iOS platforms, falls back to [showDialog] + [AlertDialog].
class LiquidGlassAlert {
  static const _presenterChannel = LiquidGlassPresenterChannel.channel;
  static int _nextId = 0;

  /// Pending alert requests keyed by request id. The shared presenter channel
  /// is used by alert/sheet/popover at once, so a single persistent handler
  /// dispatches results by id instead of clobbering the handler per-show.
  static final Map<int, Completer<String?>> _pending =
      <int, Completer<String?>>{};
  static bool _handlerInstalled = false;

  LiquidGlassAlert._();

  /// Install the shared method-call handler exactly once. Subsequent shows
  /// reuse it and route results to the right completer by id.
  static void _ensureHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    LiquidGlassPresenterChannel.register('alertActionSelected', (call) {
      final args = call.arguments as Map?;
      if (args == null) return;
      final id = args['id'] as int?;
      if (id == null) return;
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(args['actionId'] as String?);
      }
    });
    LiquidGlassPresenterChannel.register('alertDismissed', (call) {
      final args = call.arguments as Map?;
      final id = args?['id'] as int?;
      if (id == null) return;
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(null);
      }
    });
  }

  /// Show an alert and return the selected action ID.
  ///
  /// [sourceRect] 只对 [LiquidGlassAlertStyle.actionSheet] 有意义:
  /// 它对应 `UIAlertController` 的 `popoverPresentationController.sourceView`
  /// (S4 —— action sheet 从触发元素弹出)。不传时原生端退回宿主视图中心。
  static Future<String?> show({
    required BuildContext context,
    String? title,
    String? message,
    List<LiquidGlassAlertAction> actions = const [],
    LiquidGlassAlertStyle style = LiquidGlassAlertStyle.alert,
    Rect? sourceRect,
  }) async {
    if (NativeLiquidGlassUtils.supportsLiquidGlass) {
      _ensureHandlerInstalled();

      final id = _nextId++;
      final completer = Completer<String?>();
      _pending[id] = completer;

      try {
        await _presenterChannel.invokeMethod<void>('showAlert', {
          'id': id,
          'title': title,
          'message': message,
          'style': style.index,
          'actions': actions.map((a) => a.toMap()).toList(),
          if (sourceRect != null) ...<String, double>{
            'anchorX': sourceRect.left,
            'anchorY': sourceRect.top,
            'anchorWidth': sourceRect.width,
            'anchorHeight': sourceRect.height,
          },
        });
      } catch (_) {
        // The native side failed to present (e.g. plugin torn down).
        // Complete and clean up so the future never hangs.
        _pending.remove(id);
        if (!completer.isCompleted) completer.complete(null);
        rethrow;
      }

      return completer.future;
    }

    return null;
  }

  /// Convenience: show a confirmation dialog with OK & Cancel.
  static Future<bool> confirm({
    required BuildContext context,
    String? title,
    String? message,
    String confirmTitle = 'OK',
    String cancelTitle = 'Cancel',
  }) async {
    final result = await show(
      context: context,
      title: title,
      message: message,
      actions: [
        LiquidGlassAlertAction(
          id: 'cancel',
          title: cancelTitle,
          isCancel: true,
        ),
        LiquidGlassAlertAction(id: 'confirm', title: confirmTitle),
      ],
    );
    return result == 'confirm';
  }

  /// Convenience: show a destructive confirmation dialog.
  static Future<bool> destructive({
    required BuildContext context,
    String? title,
    String? message,
    String destructiveTitle = 'Delete',
    String cancelTitle = 'Cancel',
  }) async {
    final result = await show(
      context: context,
      title: title,
      message: message,
      actions: [
        LiquidGlassAlertAction(
          id: 'cancel',
          title: cancelTitle,
          isCancel: true,
        ),
        LiquidGlassAlertAction(
          id: 'destructive',
          title: destructiveTitle,
          isDestructive: true,
        ),
      ],
    );
    return result == 'destructive';
  }
}
