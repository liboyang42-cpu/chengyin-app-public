import 'package:flutter/cupertino.dart';

import '../../core/widgets/cy_swipe_actions.dart';

/// 会话行左右滑动露出的一个操作 —— 对 `CyContextualAction` 的一层薄包装,
/// 保留 im_list_page 现有调用的字段名。
class CySwipeAction {
  const CySwipeAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// 破坏性动作(删除)。走系统语义红 (destructive)。
  final bool destructive;

  CyContextualAction toContextualAction() => CyContextualAction(
    id: id,
    label: label,
    icon: icon,
    onPressed: onPressed,
    destructive: destructive,
  );
}

/// 「信息」式左右滑动操作(§3.9 IM2),内部走 [CySwipeActionsRow]
/// (iOS 27 原生观感的 `UISwipeActionsConfiguration` 对应物,#393 落地)。
///
/// 语义与自绘版逐条一致:滑动只**露出**不执行(划到底不触发,删除还要过
/// cyConfirm)、同一时刻只开一行(由父级持有 openKey)、展开期间点行先收起。
///
/// ★ 手势是 Flutter 自绘的,**行内不挂平台视图** ——
///   会话行是列表里重复 N 份的东西,每行挂一个 UIKit 视图会把滚动拖垮。
class CySwipeRow extends StatelessWidget {
  const CySwipeRow({
    super.key,
    required this.child,
    required this.selfKey,
    required this.openKey,
    required this.onOpen,
    this.leading = const <CySwipeAction>[],
    this.trailing = const <CySwipeAction>[],
    this.enabled = true,
  });

  final Widget child;

  /// 本行的身份(会话 id)。
  final Object selfKey;

  /// 当前展开的是哪一行 —— 同一时刻只允许开一行(iOS 行为)。
  final Object? openKey;

  /// 展开/收起时上报:`true` 打开本行,`false` 收起。
  final ValueChanged<bool> onOpen;

  /// 从左向右滑露出的操作。
  final List<CySwipeAction> leading;

  /// 从右向左滑露出的操作。
  final List<CySwipeAction> trailing;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return CySwipeActionsRow(
      rowKey: selfKey,
      openKey: openKey,
      onOpenChanged: (Object? opened) => onOpen(opened != null),
      leading: leading
          .map((CySwipeAction a) => a.toContextualAction())
          .toList(),
      trailing: trailing
          .map((CySwipeAction a) => a.toContextualAction())
          .toList(),
      enabled: enabled,
      child: child,
    );
  }
}
