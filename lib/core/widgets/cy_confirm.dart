import '../../l10n/strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

enum CyNativeConfirmResult { confirmed, cancelled, unavailable }

class CyNativeConfirmRequest {
  const CyNativeConfirmRequest({
    required this.title,
    required this.content,
    required this.confirmText,
    required this.cancelText,
    required this.danger,
    required this.showCancel,
  });

  final String title;
  final String? content;
  final String confirmText;
  final String cancelText;
  final bool danger;
  final bool showCancel;
}

abstract interface class CyNativeConfirmPresenter {
  Future<CyNativeConfirmResult> show(
    BuildContext context,
    CyNativeConfirmRequest request,
  );
}

class CyNativeAlertAction {
  const CyNativeAlertAction({
    required this.id,
    required this.title,
    this.isDestructive = false,
    this.isCancel = false,
  });

  final String id;
  final String title;
  final bool isDestructive;
  final bool isCancel;
}

abstract interface class CyNativeAlertDriver {
  bool get supportsLiquidGlass;

  Future<String?> show({
    required BuildContext context,
    required String title,
    required String? message,
    required List<CyNativeAlertAction> actions,
  });
}

class _LiquidGlassNativeAlertDriver implements CyNativeAlertDriver {
  const _LiquidGlassNativeAlertDriver();

  @override
  bool get supportsLiquidGlass => NativeLiquidGlassUtils.supportsLiquidGlass;

  @override
  Future<String?> show({
    required BuildContext context,
    required String title,
    required String? message,
    required List<CyNativeAlertAction> actions,
  }) {
    return LiquidGlassAlert.show(
      context: context,
      title: title,
      message: message,
      actions: actions
          .map(
            (CyNativeAlertAction action) => LiquidGlassAlertAction(
              id: action.id,
              title: action.title,
              isDestructive: action.isDestructive,
              isCancel: action.isCancel,
            ),
          )
          .toList(growable: false),
    );
  }
}

class CyLiquidGlassConfirmPresenter implements CyNativeConfirmPresenter {
  const CyLiquidGlassConfirmPresenter({CyNativeAlertDriver? driver})
    : _driver = driver ?? const _LiquidGlassNativeAlertDriver();

  final CyNativeAlertDriver _driver;

  @override
  Future<CyNativeConfirmResult> show(
    BuildContext context,
    CyNativeConfirmRequest request,
  ) async {
    if (!_driver.supportsLiquidGlass) {
      return CyNativeConfirmResult.unavailable;
    }

    try {
      final String? actionId = await _driver.show(
        context: context,
        title: request.title,
        message: request.content,
        actions: <CyNativeAlertAction>[
          if (request.showCancel)
            CyNativeAlertAction(
              id: 'cancel',
              title: request.cancelText,
              isCancel: true,
            ),
          CyNativeAlertAction(
            id: 'confirm',
            title: request.confirmText,
            isDestructive: request.danger,
          ),
        ],
      );
      return actionId == 'confirm'
          ? CyNativeConfirmResult.confirmed
          : CyNativeConfirmResult.cancelled;
    } on MissingPluginException {
      return CyNativeConfirmResult.unavailable;
    } on PlatformException {
      return CyNativeConfirmResult.unavailable;
    }
  }
}

/// 确认弹窗。移植小程序 `components/cy/modal`。
///
/// **为什么值得一个组件**:App 里 27 处各写一套 `AlertDialog`,按钮 24 处用
/// `TextButton`、7 处用 `FilledButton`。更要命的是**危险动作没有区分**——
/// 「确定要退出账号吗?」的「取消」和「退出」是两颗一模一样的文字按钮,
/// 主次不分,误点概率明显偏高。小程序那边一直有 secondary / primary / danger 三档。
///
/// iOS 26+ 优先由系统 Liquid Glass alert 呈现；旧系统和插件
/// 不可用时回退 [CupertinoAlertDialog]，危险动作保留 destructive 语义。
///
/// 返回 `true` = 用户确认;`false` 或 `null` = 取消/点遮罩关掉。
/// ★ **调用方必须把 null 和 false 一样对待** —— 点遮罩返回的是 null,
///   用 `== false` 判会把「关掉弹窗」误判成「确认」。所以这里统一收敛成 bool。
Future<bool> cyConfirm(
  BuildContext context, {
  required String title,
  String? content,
  String? confirmText,
  String? cancelText,
  bool danger = false,
  bool showCancel = true,
  CyNativeConfirmPresenter? nativePresenter,
}) async {
  final resolvedConfirmText = confirmText ?? stringsOf(context).ok;
  final resolvedCancelText = cancelText ?? stringsOf(context).cancel;
  final CyNativeConfirmResult nativeResult =
      await (nativePresenter ?? const CyLiquidGlassConfirmPresenter()).show(
        context,
        CyNativeConfirmRequest(
          title: title,
          content: content,
          confirmText: resolvedConfirmText,
          cancelText: resolvedCancelText,
          danger: danger,
          showCancel: showCancel,
        ),
      );
  switch (nativeResult) {
    case CyNativeConfirmResult.confirmed:
      return true;
    case CyNativeConfirmResult.cancelled:
      return false;
    case CyNativeConfirmResult.unavailable:
      break;
  }
  if (!context.mounted) return false;

  final bool? r = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: content == null || content.isEmpty ? null : Text(content),
      actions: <Widget>[
        if (showCancel)
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(resolvedCancelText),
          ),
        CupertinoDialogAction(
          isDefaultAction: !danger,
          isDestructiveAction: danger,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(resolvedConfirmText),
        ),
      ],
    ),
  );
  return r ?? false;
}
