import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:mjn_liquid_ui/mjn_liquid_ui.dart';

import '../theme/cy_tokens.dart';

/// A value-bearing action rendered by the iOS 26 native Liquid Glass sheet.
class CyNativeAction<T> {
  const CyNativeAction({
    required this.value,
    required this.label,
    this.systemImage,
    this.destructive = false,
  });

  final T value;
  final String label;
  final String? systemImage;
  final bool destructive;
}

/// Shows the shared native Liquid Glass action sheet on iOS 26 and preserves a
/// Cupertino action-sheet fallback for tests, older iOS versions and Android.
Future<T?> showCyNativeActionSheet<T>({
  required BuildContext context,
  required String title,
  required List<CyNativeAction<T>> actions,
  String? message,
  String cancelLabel = '取消',
}) async {
  T? selection;
  try {
    final bool shown = await AppleLiquidSheet.showSheet(
      scrollContext: context,
      heightFraction: CyTokens.iosSheetHeightFraction,
      backgroundZoomScale: 1,
      content: AppleLiquidSheetContent(
        title: title,
        doneSemanticLabel: cancelLabel,
        sections: <AppleLiquidSheetSection>[
          AppleLiquidSheetSection(
            title: message,
            rows: actions
                .map(
                  (CyNativeAction<T> action) => AppleLiquidSheetRow.button(
                    title: action.label,
                    systemImage: action.systemImage,
                    semanticLabel: action.label,
                    dismissesSheet: true,
                    style: AppleLiquidSheetButtonStyle(
                      foregroundColor: action.destructive
                          ? CupertinoColors.systemRed.resolveFrom(context)
                          : null,
                      pressedScale: 1,
                      pressAnimationDuration: 0,
                    ),
                    onPressed: () => selection = action.value,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
    if (shown) return selection;
  } on MissingPluginException {
    // Native channel is unavailable in widget tests and older embeddings.
  } on PlatformException {
    // Keep the action reachable if native presentation fails temporarily.
  }

  if (!context.mounted) return null;
  return showCupertinoModalPopup<T>(
    context: context,
    semanticsDismissible: true,
    builder: (BuildContext popupContext) => CupertinoActionSheet(
      title: Text(title),
      message: message == null ? null : Text(message),
      actions: actions
          .map(
            (CyNativeAction<T> action) => CupertinoActionSheetAction(
              isDestructiveAction: action.destructive,
              onPressed: () => Navigator.of(popupContext).pop(action.value),
              child: Text(action.label),
            ),
          )
          .toList(growable: false),
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(popupContext).pop(),
        child: Text(cancelLabel),
      ),
    ),
  );
}
