import 'dart:async';
import 'package:flutter/cupertino.dart';
import '../../../core/theme/cy_palette.dart';
import '../../../core/theme/cy_tokens.dart';

/// 可复用倒计时文本:每秒刷新,显示距 [target] 还剩 天/时/分/秒。
/// 已过期显示「已开始」。target 为 null 时显示「待定」。
class CountdownText extends StatefulWidget {
  const CountdownText({super.key, required this.target, this.style});

  final DateTime? target;
  final TextStyle? style;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(CountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) _tick();
  }

  void _tick() {
    final target = widget.target;
    if (target == null) {
      if (mounted) setState(() => _remaining = Duration.zero);
      return;
    }
    final diff = target.difference(DateTime.now());
    if (mounted) {
      setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format() {
    if (widget.target == null) return '待定';
    if (_remaining == Duration.zero) return '已开始';
    final d = _remaining.inDays;
    final h = _remaining.inHours % 24;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;
    if (d > 0) return '$d天 $h时 $m分';
    if (h > 0) return '$h时 $m分 $s秒';
    return '$m分 $s秒';
  }

  @override
  Widget build(BuildContext context) {
    // 默认档:字号落到 iOS 梯级 Caption2(11,满足 T1 最小 11pt),
    // 颜色走调色板(C4 双值),等宽数字避免逐秒跳宽。
    // 倒计时是内容层的信息,不占强调色(§3.6 强调色只做小点缀)。
    final base =
        widget.style ??
        CyType.caption2.copyWith(
          color: CyPalette.of(context).textPrimary,
          fontWeight: FontWeight.w700,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );
    return Text(_format(), style: base);
  }
}
