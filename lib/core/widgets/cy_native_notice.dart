import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import '../theme/cy_palette.dart';
import '../theme/cy_tokens.dart';

/// 页内轻量反馈的 Apple 风格通知。
///
/// iOS 26+ 使用真实 [UIGlassEffect] 容器；其他环境使用
/// [CupertinoPopupSurface]。它只替代 Material SnackBar，不改业务页的
/// 入口、文案或返回落点。
abstract final class CyNativeNotice {
  static const Duration _actionMinimumDuration = Duration(seconds: 6);
  static const Duration _accessibleMinimumDuration = Duration(
    milliseconds: 4800,
  );
  static const Duration _accessibleActionMinimumDuration = Duration(
    seconds: 30,
  );
  static OverlayEntry? _entry;

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
    OverlayState? overlayState,
    Duration duration = const Duration(milliseconds: 2400),
  }) {
    assert(
      (actionLabel == null) == (onAction == null),
      'actionLabel and onAction must be provided together.',
    );
    hide();

    final OverlayState overlay =
        overlayState ?? Overlay.of(context, rootOverlay: true);
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bool accessibleNavigation = MediaQuery.accessibleNavigationOf(
      context,
    );
    final bool useLiquidGlass = NativeLiquidGlassUtils.supportsLiquidGlass;
    final bool hasAction = actionLabel != null;
    final Duration effectiveDuration = _effectiveDuration(
      requested: duration,
      hasAction: hasAction,
      accessibleNavigation: accessibleNavigation,
    );

    if (isError) {
      unawaited(HapticFeedback.heavyImpact());
    } else {
      unawaited(HapticFeedback.selectionClick());
    }

    _entry = OverlayEntry(
      builder: (BuildContext overlayContext) => _NoticeLifetime(
        duration: effectiveDuration,
        onElapsed: hide,
        child: _CyNativeNoticeOverlay(
          message: message,
          isError: isError,
          reduceMotion: reduceMotion,
          useLiquidGlass: useLiquidGlass,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  static Duration _effectiveDuration({
    required Duration requested,
    required bool hasAction,
    required bool accessibleNavigation,
  }) {
    final Duration minimum = switch ((accessibleNavigation, hasAction)) {
      (true, true) => _accessibleActionMinimumDuration,
      (true, false) => _accessibleMinimumDuration,
      (false, true) => _actionMinimumDuration,
      (false, false) => Duration.zero,
    };
    return requested < minimum ? minimum : requested;
  }
}

class _NoticeLifetime extends StatefulWidget {
  const _NoticeLifetime({
    required this.duration,
    required this.onElapsed,
    required this.child,
  });

  final Duration duration;
  final VoidCallback onElapsed;
  final Widget child;

  @override
  State<_NoticeLifetime> createState() => _NoticeLifetimeState();
}

class _NoticeLifetimeState extends State<_NoticeLifetime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onElapsed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CyNativeNoticeOverlay extends StatelessWidget {
  const _CyNativeNoticeOverlay({
    required this.message,
    required this.isError,
    required this.reduceMotion,
    required this.useLiquidGlass,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isError;
  final bool reduceMotion;
  final bool useLiquidGlass;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final Widget content = Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isError
                  ? CupertinoIcons.exclamationmark_circle_fill
                  : CupertinoIcons.check_mark_circled_solid,
              size: 19,
              color: isError
                  ? CupertinoColors.systemRed.resolveFrom(context)
                  : palette.textPrimary,
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(width: 8),
              CupertinoButton(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                pressedOpacity: reduceMotion ? 1 : 0.4,
                onPressed: () {
                  final VoidCallback callback = onAction!;
                  CyNativeNotice.hide();
                  callback();
                },
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final Widget surface = useLiquidGlass
        ? LiquidGlassContainer(
            config: const LiquidGlassConfig(
              shape: LiquidGlassEffectShape.rect,
              cornerRadius: 18,
            ),
            child: content,
          )
        : CupertinoPopupSurface(
            isSurfacePainted: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.systemBackground
                    .resolveFrom(context)
                    .withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(18),
              ),
              child: content,
            ),
          );

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 10,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : CyMotion.standard,
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double value, Widget? child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, reduceMotion ? 0 : -10 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: surface,
            ),
          ),
        ),
      ),
    );
  }
}
