import '../../l10n/strings.dart';
// 「放弃未保存修改?」—— 脏表单返回时的守卫。
//
// ★★ App 此前**一处都没有**。小程序在 6 个编辑面上都挂了
//   (俱乐部编辑、个人资料、设置、商家工作台、漫游、游玩)。
//
//   代价不对称:少这道闸,用户填了十分钟的表单、误触一下返回就全没了,
//   而且**没有任何提示说他刚丢了什么**。多这道闸最坏只是多点一次。
//
// ⚠️ 只在**真的脏**的时候拦。没改过还弹一下确认框,
//   会让「返回」这个最高频的动作变得很重,用户很快就会开始盲点确认 ——
//   那时这道闸对真正该拦的那次也失效了。

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import 'cy_confirm.dart';

/// 与小程序逐字一致(pages/club/edit/index.wxml:12 同句的 title 另在 shezhi/
/// roam/play/index/merchant/index 四处逐字同;问号与「返回后，」的逗号都是全角)。
const String kUnsavedTitle = '放弃未保存修改？';
const String kUnsavedContent = '返回后，本次修改不会保留。';
const String kUnsavedConfirm = '放弃修改';
const String kUnsavedCancel = '继续编辑';

/// 包在编辑页外面:[isDirty] 为真时,返回会先问一句。
///
/// 用法:
/// ```dart
/// UnsavedGuard(
///   isDirty: () => _name.text != _original,
///   child: Scaffold(...),
/// )
/// ```
class UnsavedGuard extends StatefulWidget {
  const UnsavedGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.title,
    this.content,
    this.confirmText,
    this.cancelText,
  });

  /// 各编辑面在小程序里各有各的原话(如门店相册「还没有保存 / 离开后,本次相册修改不会保留。」),
  /// 缺省才是俱乐部编辑那套。
  final String? title;
  final String? content;
  final String? confirmText;
  final String? cancelText;

  /// ★ 传**函数**而不是 bool —— 表单每敲一个字都会变脏,
  ///   传值的话要求调用方每次 setState,漏一次这道闸就悄悄失效了。
  final bool Function() isDirty;
  final Widget child;

  @override
  State<UnsavedGuard> createState() => _UnsavedGuardState();
}

class _UnsavedGuardState extends State<UnsavedGuard> {
  /// 「返回」与「sheet 下滑」共用同一个确认 —— 两处文案、两个分支都只能是这一份,
  /// 否则两条路径会各自漂移(小程序 6 个编辑面用的是同一句)。
  Future<void> _confirmThenPop() async {
    if (!widget.isDirty()) {
      // canPop 是构建时的快照。表单在不重建守卫的情况下恢复了原值,
      // 这次仍然会以「要拦」进来;必须补做退出,否则已干净的页面会被
      // 永久留在栈上。
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final bool discard = await cyConfirm(
      context,
      title: widget.title ?? stringsOf(context).discardChangesTitle,
      content: widget.content ?? stringsOf(context).discardChangesMessage,
      confirmText: widget.confirmText ?? stringsOf(context).discardChanges,
      cancelText: widget.cancelText ?? stringsOf(context).keepEditing,
      danger: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop=false 会阻止退出;Android 返回与程序化 pop 仍会回调。
      // Flutter 的 iOS Cupertino 边缘手势在此状态下不会启动,所以脏表单
      // 必须从导航返回键进入确认;干净时 canPop=true,保留交互式侧滑。
      canPop: !widget.isDirty(),
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        await _confirmThenPop();
      },
      child: _SheetSwipeGuard(
        isDirty: widget.isDirty,
        onDismissAttempt: _confirmThenPop,
        child: widget.child,
      ),
    );
  }
}

/// 接住 sheet 的**下滑关闭**(S2)。
///
/// ★★ 为什么 PopScope 不够:sheet 的下滑关闭不走「返回」那条路 ——
///   Flutter `cupertino/sheet.dart` 的 `_handleDragEnd` 直接调
///   `navigator.pop()`(**强制 pop**,绕过 `PopScope` 与 `popDisposition`)。
///   于是页面以 sheet 呈现时,下滑 = 静默丢弃未保存的修改:用户以为
///   滑掉就存了。实测(`maybePop` 会被拦,拖动不会)确认了这一点。
///
/// 做法:脏的时候由我们**自己接住这次竖直拖动**(不进 sheet 的滚动链),
/// 拖动越过阈值 = 一次关闭意图,走与「返回」同一个确认。
/// 干净的时侯识别器**不进竞技场**,下滑关闭与原生完全一致 ——
/// 「没改过还拦一下」会让关闭这个高频动作变重,用户很快开始盲点确认。
///
/// ⚠️ 已知边界(Flutter SDK 约束,实测过,不是漏做)——
///   下面两条路径**拦不到**,只能由打开方 `enableDrag: false` 堵死:
///   · sheet 顶部的**抓手条**是 SDK 的兄弟节点,不在本 widget 子树里;
///   · 内容**自带滚动条**时(仓里 79/86 处 sheet 用的 scrollableBuilder),
///     拖动先被内层 `Scrollable` 吃掉,本识别器根本进不了竞技场。
///   这两条路径上,单纯把 PopScope 换成「接住下滑」是做不到的:
///   `cupertino/sheet.dart` 的 `_handleDragEnd` 直接 `navigator.pop()`
///   (强制 pop,不看 `popDisposition`)。所以口径是
///   **「守卫在场 ⇒ 这个 sheet 不许能拖」**,门禁
///   `test/widgets/unsaved_guard_sheet_contract_test.dart` 挡住
///   「UnsavedGuard + 可拖动」的组合;仓内持状态的 sheet
///   (`club_post_mutation_sheets` / `club_comments_sheet` 等)本来就是
///   `enableDrag: false`。
///
/// ⚠️ 只在 `CupertinoSheetRoute` 里装识别器:普通页面里向下拖不是「关闭」
///   手势,在那种地方弹确认框是纯噪音。
class _SheetSwipeGuard extends StatefulWidget {
  const _SheetSwipeGuard({
    required this.isDirty,
    required this.onDismissAttempt,
    required this.child,
  });

  final bool Function() isDirty;
  final VoidCallback onDismissAttempt;
  final Widget child;

  @override
  State<_SheetSwipeGuard> createState() => _SheetSwipeGuardState();
}

/// 一次关闭意图的量:拖动距离或甩动速度任一越线。
/// 口径对齐系统 sheet 的甩动阈值(>= 1 屏/秒的一半就够果断)。
const double _kDismissSwipeDistance = 96;
const double _kDismissSwipeVelocity = 700;

class _SheetSwipeGuardState extends State<_SheetSwipeGuard> {
  double _draggedDown = 0;

  void _onDragEnd(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    final double dragged = _draggedDown;
    _draggedDown = 0;
    if (velocity < _kDismissSwipeVelocity && dragged < _kDismissSwipeDistance) {
      return;
    }
    widget.onDismissAttempt();
  }

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context) is! CupertinoSheetRoute) return widget.child;
    return RawGestureDetector(
      // translucent:sheet 里的空白处(内容没铺满)也要能接住拖动。
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _DismissSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<_DismissSwipeRecognizer>(
              () => _DismissSwipeRecognizer(isDirty: widget.isDirty),
              (_DismissSwipeRecognizer instance) {
                instance.onStart = (DragStartDetails _) {
                  _draggedDown = 0;
                };
                instance.onUpdate = (DragUpdateDetails details) {
                  _draggedDown += details.primaryDelta ?? 0;
                };
                instance.onEnd = _onDragEnd;
                instance.onCancel = () {
                  _draggedDown = 0;
                };
              },
            ),
      },
      child: widget.child,
    );
  }
}

/// 干净时不进竞技场:`addAllowedPointer` 直接不接管这个指针,
/// 于是「下滑关闭」「内容滚动」都按系统原样走,守卫零成本。
class _DismissSwipeRecognizer extends VerticalDragGestureRecognizer {
  _DismissSwipeRecognizer({required this.isDirty});

  final bool Function() isDirty;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!isDirty()) return;
    super.addAllowedPointer(event);
  }
}
