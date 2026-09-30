import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// 原生 sheet 的停靠档位(S2):medium / large / 两档可拖。
enum CyNativeSheetDetents { medium, large, both }

/// B1 `native_flutter_sheet`:原生 `UISheetPresentationController` 承载 Flutter 内容。
///
/// - iOS 15+:原生 sheet(26+ 真 Liquid Glass,15–25 系统旧样式),grabber /
///   detent / 下滑关闭 / 键盘避让都由 UIKit 负责。内容仍由**主引擎**渲染
///   (同一个 isolate),Riverpod 等状态天然共享;内容里
///   `Navigator.of(context).pop(value)` 即关闭并回传 value。
/// - iOS 13–14(原生回 `unsupported`)、Android、测试环境(无插件):
///   回退 `showCupertinoSheet`。
///
/// 原生承载时内容背景要透明才能透出玻璃(S3 不给 sheet 加自定义背景),
/// 用 [isCyNativeSheet] 判断。
Future<T?> showCyNativeSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  CyNativeSheetDetents detents = CyNativeSheetDetents.both,
  bool grabber = true,
  bool dismissible = true,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    );
    try {
      _channel.setMethodCallHandler(_onNativeCall);
      await _channel.invokeMethod<void>('present', <String, Object>{
        'detents': detents.name,
        'grabber': grabber,
        'dismissible': dismissible,
      });
      return _hostNatively<T>(overlay, themes, builder);
    } on MissingPluginException {
      // 测试环境 / 未注册插件的嵌入。
    } on PlatformException {
      // 一次只一个原生 sheet(S1)。嵌套请求(如登录 sheet 里的「手机号登录」)
      // 不能静默吞掉:already_presented / unsupported(iOS 13–14)/ 原生呈现
      // 失败都回退 Flutter 承载,叠在当前 sheet 的内容里;表单不能因此不可用。
    }
  }

  if (!context.mounted) return null;
  // 嵌套请求(调用方本身就在原生 sheet 内容里):必须叠进承载内容的
  // 最近 Navigator。showCupertinoSheet 恒推**根** Navigator,而原生承载
  // 的入口是一个盖住根 overlay 的 opaque OverlayEntry,推到根上会被
  // 压在登录 sheet 内容之下 —— 完全不可见(手机号登录表单打不开即此)。
  if (_insideNativeSheet(context)) {
    return Navigator.of(context).push<T>(
      CupertinoSheetRoute<T>(
        scrollableBuilder:
            (BuildContext context, ScrollController controller) =>
                PrimaryScrollController(
                  controller: controller,
                  child: builder(context),
                ),
        enableDrag: dismissible,
        showDragHandle: grabber,
        topGap: detents == CyNativeSheetDetents.medium ? 0.5 : null,
      ),
    );
  }
  return showCupertinoSheet<T>(
    context: context,
    enableDrag: dismissible,
    showDragHandle: grabber,
    topGap: detents == CyNativeSheetDetents.medium ? 0.5 : null,
    scrollableBuilder: (BuildContext context, ScrollController controller) =>
        PrimaryScrollController(
          controller: controller,
          child: builder(context),
        ),
  );
}

bool _insideNativeSheet(BuildContext context) =>
    context.getElementForInheritedWidgetOfExactType<_NativeSheetScope>() !=
    null;

/// 当前内容是否由原生 sheet 承载(背景应透明,透出系统玻璃)。
///
/// 原生 sheet 里再叠的 Flutter 回退 sheet(`CupertinoSheetRoute`)虽在原生
/// 承载入口之下,但要自己的不透明背景(叠在当前内容之上,透明会透出
/// 下层表单),所以带 parent sheet 的一律算「回退承载」。
bool isCyNativeSheet(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_NativeSheetScope>() != null &&
    !CupertinoSheetRoute.hasParentSheet(context);

const MethodChannel _channel = MethodChannel(
  'native_liquid_glass/native_flutter_sheet',
);

/// 原生报「sheet 已消失、主控制器已接回」时要做的收尾。一次只一个。
VoidCallback? _onDismissed;

Future<Object?> _onNativeCall(MethodCall call) async {
  if (call.method == 'dismissed') {
    final VoidCallback? onDismissed = _onDismissed;
    _onDismissed = null;
    if (onDismissed != null) {
      onDismissed();
    } else {
      unawaited(_restoreAfterFrame());
    }
  }
  return null;
}

Future<void> _restoreAfterFrame() async {
  await SchedulerBinding.instance.endOfFrame;
  await _channel.invokeMethod<void>('restored');
}

Future<T?> _hostNatively<T>(
  OverlayState overlay,
  CapturedThemes themes,
  WidgetBuilder builder,
) async {
  final Completer<T?> completer = Completer<T?>();
  T? result;
  bool closing = false;

  final _SheetContentRoute<T> route = _SheetContentRoute<T>(
    builder: (BuildContext context) =>
        _NativeSheetScope(child: builder(context)),
    onPop: (T? value) {
      if (closing) return;
      closing = true;
      result = value;
      unawaited(_channel.invokeMethod<void>('dismiss'));
    },
  );
  // opaque:下层页面不绘制(原生 sheet 的 Flutter 视图里只剩内容)但保活。
  final OverlayEntry entry = OverlayEntry(
    opaque: true,
    maintainState: true,
    builder: (BuildContext context) => themes.wrap(
      Navigator(
        onGenerateInitialRoutes: (NavigatorState _, String _) => <Route<void>>[
          route,
        ],
      ),
    ),
  );

  _onDismissed = () {
    entry.remove();
    entry.dispose();
    completer.complete(result);
    unawaited(_restoreAfterFrame());
  };
  overlay.insert(entry);
  await SchedulerBinding.instance.endOfFrame;
  await _channel.invokeMethod<void>('reveal');
  return completer.future;
}

/// 内容里 `Navigator.pop` 不真的出栈:先让原生做关闭动画，
/// 等原生回 `dismissed` 再拆 overlay,避免动画中途内容消失。
class _SheetContentRoute<T> extends PageRouteBuilder<T> {
  _SheetContentRoute({required WidgetBuilder builder, required this.onPop})
    : super(
        pageBuilder: (BuildContext context, _, _) => builder(context),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  final ValueChanged<T?> onPop;

  // 刻意不调 super:super 会 complete 路由并出栈，关闭动画期间内容就没了。
  @override
  // ignore: must_call_super
  bool didPop(T? result) {
    onPop(result);
    return false;
  }
}

class _NativeSheetScope extends InheritedWidget {
  const _NativeSheetScope({required super.child});

  @override
  bool updateShouldNotify(_NativeSheetScope oldWidget) => false;
}
