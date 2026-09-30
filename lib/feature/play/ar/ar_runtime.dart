import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// P4 图像追踪 Spike 的运行时边界。
///
/// 原生层只上报业务无关事件（识别/稳定/丢失/相机不可用/设备不支持），
/// **不上报「完成/通过/发奖」结论**——那属于后端 P5 口径。
enum ArEventKind {
  imageDetected,
  trackingStable,
  trackingLost,
  cameraUnavailable,
  unsupportedDevice,
}

final class ArTrackingEvent {
  const ArTrackingEvent(this.kind, {required this.at});

  final ArEventKind kind;
  final DateTime at;
}

/// 可注入的 AR 运行时 seam（照 `stillness_platform.dart` 的姿势）：
/// 单测用假实现，不依赖真机/模拟器。
abstract interface class ArRuntime {
  /// 设备/平台是否可用 ARKit 图像追踪。
  /// Android、Web、模拟器、A9 及更早芯片一律 false（契约 §7.3：Android 先不做）。
  Future<bool> isSupported();

  /// 开始识别锚图。[physicalWidthCm] 是锚图打印后的实际物理宽度，
  /// 传给 `ARReferenceImage.physicalSize`，填错会直接影响测距。
  Stream<ArTrackingEvent> startTracking({required double physicalWidthCm});

  Future<void> stopTracking();
}

class ChannelArRuntime implements ArRuntime {
  ChannelArRuntime({
    @visibleForTesting MethodChannel? methodChannel,
    @visibleForTesting EventChannel? eventChannel,
  }) : _method = methodChannel ?? const MethodChannel(_kMethodChannel),
       _events = eventChannel ?? const EventChannel(_kEventChannel);

  static const String _kMethodChannel = 'com.chengyin.app/ar_image';
  static const String _kEventChannel = 'com.chengyin.app/ar_image_events';

  final MethodChannel _method;
  final EventChannel _events;

  @override
  Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _method.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Stream<ArTrackingEvent> startTracking({
    required double physicalWidthCm,
  }) async* {
    await _method.invokeMethod<void>('start', <String, Object?>{
      'physicalWidthCm': physicalWidthCm,
    });
    yield* _events
        .receiveBroadcastStream()
        .map(_decodeEvent)
        .where((event) => event != null)
        .cast<ArTrackingEvent>();
  }

  @override
  Future<void> stopTracking() => _method.invokeMethod<void>('stop');

  static ArTrackingEvent? _decodeEvent(Object? raw) {
    if (raw is! Map) return null;
    final String? name = raw['event'] as String?;
    final ArEventKind? kind = switch (name) {
      'image_detected' => ArEventKind.imageDetected,
      'tracking_stable' => ArEventKind.trackingStable,
      'tracking_lost' => ArEventKind.trackingLost,
      'camera_unavailable' => ArEventKind.cameraUnavailable,
      'unsupported_device' => ArEventKind.unsupportedDevice,
      _ => null,
    };
    if (kind == null) return null;
    final int? ms = raw['timestampMs'] as int?;
    return ArTrackingEvent(
      kind,
      at: ms == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}

/// 一个节点的进入结果：AR 事件流，或已走拍照回落并拿到回落产物。
final class ArNodeOutcome<R> {
  const ArNodeOutcome.ar(this.events) : photoResult = null;

  const ArNodeOutcome.photoFallback(this.photoResult) : events = null;

  final Stream<ArTrackingEvent>? events;
  final R? photoResult;

  bool get usedPhotoFallback => events == null;
}

/// 节点进入编排：AR 可用 ⇒ 返回事件流（是否「完成」由上层/后端判定）；
/// 不可用（A9 及更早 / 模拟器 / Android / 通道异常）⇒ 走 [photoFallback]，
/// 即现有 `PlaySessionController.photo` / `filterPhoto`（submitPhoto → /api/play/photo）
/// 那条链路，节点仍可完成。不新发明第二套提交通道。
Future<ArNodeOutcome<R>> runArNode<R>({
  required ArRuntime runtime,
  required double physicalWidthCm,
  required Future<R> Function() photoFallback,
}) async {
  bool supported;
  try {
    supported = await runtime.isSupported();
  } catch (_) {
    // 桥本身异常也不许卡在 AR 路径，一律回落。
    supported = false;
  }
  if (supported) {
    return ArNodeOutcome<R>.ar(
      runtime.startTracking(physicalWidthCm: physicalWidthCm),
    );
  }
  return ArNodeOutcome<R>.photoFallback(await photoFallback());
}
