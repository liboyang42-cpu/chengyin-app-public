import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter/semantics.dart';

typedef CyRangeSemanticFormatter = String Function(double value);

/// Cupertino 未提供双端滑块，此组件使用 Apple 滑块几何与
/// 两个独立 VoiceOver adjustable 节点，保留单轨双端值。
///
/// 它没有隐式动画，Reduce Motion 下也会即时跳到新值。
class CyCupertinoRangeSlider extends StatefulWidget {
  CyCupertinoRangeSlider({
    super.key,
    required this.values,
    required this.min,
    required this.max,
    required this.startSemanticLabel,
    required this.endSemanticLabel,
    this.onChanged,
    this.divisions,
    this.semanticFormatter,
    this.activeColor,
    this.trackColor,
    this.thumbColor,
  }) : assert(min < max),
       assert(values.start >= min && values.end <= max),
       assert(values.start <= values.end),
       assert(divisions == null || divisions > 0);

  final RangeValues values;
  final double min;
  final double max;
  final ValueChanged<RangeValues>? onChanged;
  final int? divisions;
  final String startSemanticLabel;
  final String endSemanticLabel;
  final CyRangeSemanticFormatter? semanticFormatter;
  final Color? activeColor;
  final Color? trackColor;
  final Color? thumbColor;

  @override
  State<CyCupertinoRangeSlider> createState() => _CyCupertinoRangeSliderState();
}

enum _RangeThumb { start, end }

class _CyCupertinoRangeSliderState extends State<CyCupertinoRangeSlider> {
  static const double _height = 44;
  static const double _hitRadius = 22;
  static const double _thumbRadius = 14;
  _RangeThumb? _activeThumb;

  double get _step => (widget.max - widget.min) / (widget.divisions ?? 20);

  double _position(double value, double width) {
    final double usable = math.max(1, width - _hitRadius * 2);
    return _hitRadius +
        (value - widget.min) / (widget.max - widget.min) * usable;
  }

  double _value(double x, double width) {
    final double usable = math.max(1, width - _hitRadius * 2);
    final double raw =
        widget.min +
        ((x - _hitRadius) / usable).clamp(0.0, 1.0) * (widget.max - widget.min);
    if (widget.divisions == null) return raw;
    return widget.min + ((raw - widget.min) / _step).round() * _step;
  }

  void _selectThumb(double x, double width) {
    final double startX = _position(widget.values.start, width);
    final double endX = _position(widget.values.end, width);
    if ((x - startX).abs() == (x - endX).abs()) {
      _activeThumb = x <= startX ? _RangeThumb.start : _RangeThumb.end;
      return;
    }
    _activeThumb = (x - startX).abs() < (x - endX).abs()
        ? _RangeThumb.start
        : _RangeThumb.end;
  }

  void _updateFromPosition(double x, double width) {
    if (widget.onChanged == null || _activeThumb == null) return;
    final double next = _value(x, width);
    final RangeValues values = switch (_activeThumb!) {
      _RangeThumb.start => RangeValues(
        math.min(next, widget.values.end),
        widget.values.end,
      ),
      _RangeThumb.end => RangeValues(
        widget.values.start,
        math.max(next, widget.values.start),
      ),
    };
    widget.onChanged!(values);
  }

  void _adjust(_RangeThumb thumb, double delta) {
    if (widget.onChanged == null) return;
    final double next = switch (thumb) {
      _RangeThumb.start => (widget.values.start + delta).clamp(
        widget.min,
        widget.values.end,
      ),
      _RangeThumb.end => (widget.values.end + delta).clamp(
        widget.values.start,
        widget.max,
      ),
    };
    widget.onChanged!(
      thumb == _RangeThumb.start
          ? RangeValues(next, widget.values.end)
          : RangeValues(widget.values.start, next),
    );
  }

  String _semanticValue(double value) =>
      widget.semanticFormatter?.call(value) ?? value.toStringAsFixed(0);

  Widget _semanticThumb({
    required _RangeThumb thumb,
    required double value,
    required String label,
  }) {
    final bool enabled = widget.onChanged != null;
    final bool canDecrease =
        enabled &&
        (thumb == _RangeThumb.start
            ? value > widget.min
            : value > widget.values.start);
    final bool canIncrease =
        enabled &&
        (thumb == _RangeThumb.start
            ? value < widget.values.end
            : value < widget.max);
    return Semantics(
      container: true,
      slider: true,
      enabled: enabled,
      label: label,
      value: _semanticValue(value),
      decreasedValue: canDecrease
          ? _semanticValue(math.max(widget.min, value - _step))
          : null,
      increasedValue: canIncrease
          ? _semanticValue(math.min(widget.max, value + _step))
          : null,
      onDecrease: canDecrease ? () => _adjust(thumb, -_step) : null,
      onIncrease: canIncrease ? () => _adjust(thumb, _step) : null,
      sortKey: OrdinalSortKey(thumb == _RangeThumb.start ? 0 : 1),
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final Color active = enabled
        ? (widget.activeColor ??
              CupertinoColors.activeBlue.resolveFrom(context))
        : CupertinoColors.inactiveGray.resolveFrom(context);
    final Color track =
        widget.trackColor ?? CupertinoColors.systemGrey4.resolveFrom(context);
    final Color thumb =
        widget.thumbColor ??
        // ★ 不是 `systemBackground` —— 它在暗色主题解析成**纯黑**,黑页上
        //   画黑拇指(阴影也是黑的)整个隐形(a5-ios27-search-2 critic 点名)。
        //   原生 `CupertinoSlider` 的拇指恒白(slider.dart `thumbColor =
        //   CupertinoColors.white`),靠阴影起层,浅/深底都读得出来 —— 同规格。
        CupertinoColors.white;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double startX = _position(widget.values.start, width);
          final double endX = _position(widget.values.end, width);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: enabled
                ? (TapDownDetails details) {
                    _selectThumb(details.localPosition.dx, width);
                    _updateFromPosition(details.localPosition.dx, width);
                  }
                : null,
            onHorizontalDragStart: enabled
                ? (DragStartDetails details) {
                    _selectThumb(details.localPosition.dx, width);
                  }
                : null,
            onHorizontalDragUpdate: enabled
                ? (DragUpdateDetails details) =>
                      _updateFromPosition(details.localPosition.dx, width)
                : null,
            onHorizontalDragEnd: enabled ? (_) => _activeThumb = null : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: _CyRangePainter(
                        startX: startX,
                        endX: endX,
                        activeColor: active,
                        trackColor: track,
                        thumbColor: thumb,
                        thumbRadius: _thumbRadius,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: startX - _hitRadius,
                  width: _hitRadius * 2,
                  top: 0,
                  bottom: 0,
                  child: _semanticThumb(
                    thumb: _RangeThumb.start,
                    value: widget.values.start,
                    label: widget.startSemanticLabel,
                  ),
                ),
                Positioned(
                  left: endX - _hitRadius,
                  width: _hitRadius * 2,
                  top: 0,
                  bottom: 0,
                  child: _semanticThumb(
                    thumb: _RangeThumb.end,
                    value: widget.values.end,
                    label: widget.endSemanticLabel,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CyRangePainter extends CustomPainter {
  const _CyRangePainter({
    required this.startX,
    required this.endX,
    required this.activeColor,
    required this.trackColor,
    required this.thumbColor,
    required this.thumbRadius,
  });

  final double startX;
  final double endX;
  final Color activeColor;
  final Color trackColor;
  final Color thumbColor;
  final double thumbRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    final RRect track = RRect.fromRectAndRadius(
      Rect.fromLTRB(22, centerY - 2, size.width - 22, centerY + 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(startX, centerY - 2, endX, centerY + 2),
        const Radius.circular(2),
      ),
      Paint()..color = activeColor,
    );
    for (final double x in <double>[startX, endX]) {
      final Path shadow = Path()
        ..addOval(
          Rect.fromCircle(center: Offset(x, centerY), radius: thumbRadius),
        );
      canvas.drawShadow(shadow, CupertinoColors.black, 2, true);
      canvas.drawCircle(
        Offset(x, centerY),
        thumbRadius,
        Paint()..color = thumbColor,
      );
    }
  }

  @override
  bool shouldRepaint(_CyRangePainter oldDelegate) =>
      startX != oldDelegate.startX ||
      endX != oldDelegate.endX ||
      activeColor != oldDelegate.activeColor ||
      trackColor != oldDelegate.trackColor ||
      thumbColor != oldDelegate.thumbColor;
}
