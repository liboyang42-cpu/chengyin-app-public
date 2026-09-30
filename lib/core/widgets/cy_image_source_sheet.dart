import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

enum CyImagePickSource { camera, gallery }

/// 触发元素在**屏幕坐标**里的矩形 —— action sheet 的 `sourceView` 锚点(S4)。
///
/// 传**触发元素**(那个「+」、那个头像)的 context 才拿得到它的矩形;
/// 传页面 context 拿到的就是整页矩形,iPad 上仍然近似从中间弹 ⸺ 那不是
/// 「锚上了」,只是没锚错方向。取不到 RenderBox(没布局 / 已卸载)返回 null,
/// 调用方按「不锚定」处理。
Rect? cySourceRectOf(BuildContext context) {
  final RenderObject? object = context.findRenderObject();
  if (object is! RenderBox || !object.attached || !object.hasSize) return null;
  return object.localToGlobal(Offset.zero) & object.size;
}

class CyNativeImageSourceAction {
  const CyNativeImageSourceAction({
    required this.id,
    required this.title,
    this.isCancel = false,
  });

  final String id;
  final String title;
  final bool isCancel;
}

abstract interface class CyNativeImageSourceDriver {
  bool get supportsLiquidGlass;

  Future<String?> showActionSheet({
    required BuildContext context,
    required List<CyNativeImageSourceAction> actions,
    Rect? sourceRect,
  });
}

class _LiquidGlassImageSourceDriver implements CyNativeImageSourceDriver {
  const _LiquidGlassImageSourceDriver();

  @override
  bool get supportsLiquidGlass => NativeLiquidGlassUtils.supportsLiquidGlass;

  @override
  Future<String?> showActionSheet({
    required BuildContext context,
    required List<CyNativeImageSourceAction> actions,
    Rect? sourceRect,
  }) {
    return LiquidGlassAlert.show(
      context: context,
      style: LiquidGlassAlertStyle.actionSheet,
      sourceRect: sourceRect,
      actions: actions
          .map(
            (CyNativeImageSourceAction action) => LiquidGlassAlertAction(
              id: action.id,
              title: action.title,
              isCancel: action.isCancel,
            ),
          )
          .toList(growable: false),
    );
  }
}

/// 对齐小程序 `chooseImage` 的来源选择：拍照 / 从相册选择 / 取消。
///
/// iOS 26 使用系统 `UIAlertController.actionSheet`；旧 iOS 或原生通道
/// 暂不可用时降级为 Cupertino action sheet，且用户取消不会再弹第二层。
///
/// [sourceRect] 是 S4 的锚点:action sheet 从触发元素弹出,而不是屏幕中央。
/// 不传就按 [context] 自己的矩形(见 [cySourceRectOf])——
/// **想要真锚点,就把触发元素的 context 或它的矩形传进来。**
///
/// ⚠️ 降级路径(< 26 / 原生通道不可用)用的是 `showCupertinoModalPopup`,
///   它只有底部对齐、没有 `sourceView` 这个概念 —— **不锚定**。这是明说的
///   降级,不是「已经锚上了」。
Future<CyImagePickSource?> cyChooseImageSource(
  BuildContext context, {
  Rect? sourceRect,
  CyNativeImageSourceDriver? nativeDriver,
}) async {
  final Rect? anchorRect = sourceRect ?? cySourceRectOf(context);
  final CyNativeImageSourceDriver driver =
      nativeDriver ?? const _LiquidGlassImageSourceDriver();
  const List<CyNativeImageSourceAction> actions = <CyNativeImageSourceAction>[
    CyNativeImageSourceAction(id: 'camera', title: '拍照'),
    CyNativeImageSourceAction(id: 'gallery', title: '从相册选择'),
    CyNativeImageSourceAction(id: 'cancel', title: '取消', isCancel: true),
  ];

  if (driver.supportsLiquidGlass) {
    try {
      final String? actionId = await driver.showActionSheet(
        context: context,
        actions: actions,
        sourceRect: anchorRect,
      );
      return switch (actionId) {
        'camera' => CyImagePickSource.camera,
        'gallery' => CyImagePickSource.gallery,
        _ => null,
      };
    } on MissingPluginException {
      // 原生插件未注册时使用下方系统风格降级。
    } on PlatformException {
      // 原生 presentation 暂不可用时使用下方系统风格降级。
    }
  }

  if (!context.mounted) return null;
  return showCupertinoModalPopup<CyImagePickSource>(
    context: context,
    builder: (BuildContext sheetContext) => CupertinoActionSheet(
      actions: <Widget>[
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(sheetContext).pop(CyImagePickSource.camera),
          child: const Text('拍照'),
        ),
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(sheetContext).pop(CyImagePickSource.gallery),
          child: const Text('从相册选择'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: const Text('取消'),
      ),
    ),
  );
}
