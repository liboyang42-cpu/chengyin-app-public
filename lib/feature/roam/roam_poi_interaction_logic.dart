import '../../data/models/city_node_detail.dart';

/// 据点详情页「到店互动」的纯逻辑。对齐小程序
/// `components/cy/scene-roam-poi-detail` 的验证方式分派与失败恢复。

/// 验证方式 → 互动类型。5/GPS 到达/空/其它都归 gps(与后端分支一致,
/// 客户端不能再造第六档)。
enum RoamInteractionKind { text, choice, photo, scan, gps }

RoamInteractionKind interactionKindFor(int? validationMethod) {
  switch (validationMethod) {
    case 1:
      return RoamInteractionKind.text;
    case 2:
      return RoamInteractionKind.photo;
    case 3:
      return RoamInteractionKind.choice;
    case 4:
      return RoamInteractionKind.scan;
    default:
      return RoamInteractionKind.gps;
  }
}

/// 互动失败后的恢复态:取消即清除;权限被拒给「去设置」;
/// 其余给「重试」。
enum RoamInteractionRecovery { none, retry, cameraPermission, locationPermission }

/// 互动按钮文案(对齐 wxml:completed → 已完成 / completing → 处理中…)。
String interactButtonLabel({required bool completed, required bool completing}) {
  if (completed) return '已完成';
  if (completing) return '处理中…';
  return '开始互动';
}

/// 互动行 meta 文案:验证方式 + 领券提示。
String nodeMetaText(CityNodeDetail node) {
  final String base = node.methodLabel;
  return node.hasCoupon ? '$base · 完成领券' : base;
}

/// 定位异常是否是「权限被拒/服务没开」—— 这要引导去设置,不是重试。
/// 判据走文案关键词(geolocator 不同平台抛的异常类型不同,
/// 文案里都会带 permission/denied/service 之一)。
bool isLocationPermissionFailure(String message) {
  final String m = message.toLowerCase();
  return m.contains('permission') ||
      m.contains('denied') ||
      m.contains('service');
}

/// 定位异常是否是「用户取消」—— 取消不是失败,静默收场。
bool isLocationCancel(String message) {
  return RegExp(r'\bcancel(?:led)?\b', caseSensitive: false).hasMatch(message);
}
