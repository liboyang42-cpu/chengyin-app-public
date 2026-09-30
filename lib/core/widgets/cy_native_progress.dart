import 'package:flutter/cupertino.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

/// Apple 进度条。iOS 使用插件提供的原生 `UIProgressView`，
/// 其他环境使用插件自带的 Flutter 回退。
///
/// 组件不做补间动画，因此 Reduce Motion 下不会强制播放进度过渡。
class CyNativeProgress extends StatelessWidget {
  const CyNativeProgress({
    super.key,
    required this.progress,
    required this.semanticLabel,
    this.height = 8,
    this.progressColor,
    this.trackColor,
    this.semanticValue,
  }) : assert(progress >= 0 && progress <= 1),
       assert(height > 0);

  final double progress;
  final String semanticLabel;
  final double height;
  final Color? progressColor;
  final Color? trackColor;
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      readOnly: true,
      label: semanticLabel,
      value: semanticValue ?? '${(progress * 100).round()}%',
      child: ExcludeSemantics(
        child: LiquidGlassProgressView(
          progress: progress,
          height: height,
          progressTintColor: progressColor,
          trackTintColor: trackColor,
        ),
      ),
    );
  }
}
