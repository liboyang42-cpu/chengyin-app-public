import 'dart:async';

import 'package:chengyin_app/feature/play/ar/ar_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假实现：单测不依赖真机/模拟器（seam 姿势同 stillness_platform）。
class FakeArRuntime implements ArRuntime {
  FakeArRuntime({required this.supported, this.throwsOnIsSupported = false});

  final bool supported;
  final bool throwsOnIsSupported;
  final StreamController<ArTrackingEvent> events =
      StreamController<ArTrackingEvent>.broadcast();
  double? lastPhysicalWidthCm;
  bool stopped = false;

  @override
  Future<bool> isSupported() async {
    if (throwsOnIsSupported) throw Exception('channel unavailable');
    return supported;
  }

  @override
  Stream<ArTrackingEvent> startTracking({required double physicalWidthCm}) {
    lastPhysicalWidthCm = physicalWidthCm;
    return events.stream;
  }

  @override
  Future<void> stopTracking() async => stopped = true;
}

class _ThrowingMethodChannel extends MethodChannel {
  _ThrowingMethodChannel() : super('com.chengyin.app/ar_image');

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) =>
      throw MissingPluginException('native side absent');
}

class _ThrowingEventChannel extends EventChannel {
  _ThrowingEventChannel() : super('com.chengyin.app/ar_image_events');

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) =>
      Stream<dynamic>.error(MissingPluginException());
}

class _StubMethodChannel extends MethodChannel {
  _StubMethodChannel() : super('com.chengyin.app/ar_image');

  final List<MethodCall> calls = <MethodCall>[];

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) {
    calls.add(MethodCall(method, arguments));
    return Future<T?>.value();
  }
}

class _StubEventChannel extends EventChannel {
  _StubEventChannel(this.source) : super('com.chengyin.app/ar_image_events');

  final StreamController<dynamic> source;

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) => source.stream;
}

void main() {
  test('设备支持 ⇒ 走 AR 事件流，不调拍照回落', () async {
    final runtime = FakeArRuntime(supported: true);
    var photoFallbackCalled = false;

    final outcome = await runArNode<int>(
      runtime: runtime,
      physicalWidthCm: 15,
      photoFallback: () async {
        photoFallbackCalled = true;
        return 0;
      },
    );

    expect(outcome.usedPhotoFallback, isFalse);
    expect(photoFallbackCalled, isFalse);
    expect(outcome.events, isNotNull);
    expect(runtime.lastPhysicalWidthCm, 15);

    // 广播流：必须先订阅再投递事件。
    final firstEvent = outcome.events!.first;
    runtime.events.add(
      ArTrackingEvent(ArEventKind.trackingStable, at: DateTime(2026, 9, 22)),
    );
    expect(
      await firstEvent,
      isA<ArTrackingEvent>().having(
        (e) => e.kind,
        'kind',
        ArEventKind.trackingStable,
      ),
    );
    await runtime.stopTracking();
    expect(runtime.stopped, isTrue);
    await runtime.events.close();
  });

  test('不支持设备（A9/模拟器/Android）⇒ 拍照回落 ⇒ 节点仍可完成', () async {
    final runtime = FakeArRuntime(supported: false);
    // photoFallback 即现有 PlaySessionController.photo（submitPhoto →
    // /api/play/photo）链路的位置；返回发奖结果代表节点可完成。
    final outcome = await runArNode<String>(
      runtime: runtime,
      physicalWidthCm: 15,
      photoFallback: () async => 'reward-42',
    );

    expect(outcome.usedPhotoFallback, isTrue);
    expect(outcome.photoResult, 'reward-42');
    expect(outcome.events, isNull);
  });

  test('通道异常 ⇒ 同样拍照回落，不卡在 AR 路径', () async {
    final runtime = FakeArRuntime(supported: true, throwsOnIsSupported: true);
    final outcome = await runArNode<int>(
      runtime: runtime,
      physicalWidthCm: 15,
      photoFallback: () async => 1,
    );
    expect(outcome.usedPhotoFallback, isTrue);
    expect(outcome.photoResult, 1);
  });

  test('Android/macOS 上不发起 channel 调用，isSupported 直接 false（契约 §7.3）', () async {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final runtime = ChannelArRuntime(
        methodChannel: _ThrowingMethodChannel(),
        eventChannel: _ThrowingEventChannel(),
      );
      expect(await runtime.isSupported(), isFalse, reason: '$platform');
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('iOS 上通道缺失（MissingPluginException）⇒ isSupported=false 走回落', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final runtime = ChannelArRuntime(
      methodChannel: _ThrowingMethodChannel(),
      eventChannel: _ThrowingEventChannel(),
    );
    expect(await runtime.isSupported(), isFalse);

    final outcome = await runArNode<String>(
      runtime: runtime,
      physicalWidthCm: 15,
      photoFallback: () async => 'photo-ok',
    );
    expect(outcome.usedPhotoFallback, isTrue);
    expect(outcome.photoResult, 'photo-ok');
  });

  test('start 调用把 physicalWidthCm 传给原生；事件名解码、未知事件丢弃', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final method = _StubMethodChannel();
    final source = StreamController<dynamic>.broadcast();
    final runtime = ChannelArRuntime(
      methodChannel: method,
      eventChannel: _StubEventChannel(source),
    );

    final stream = runtime.startTracking(physicalWidthCm: 29.5);
    final collected = <ArTrackingEvent>[];
    final sub = stream.listen(collected.add);
    await pumpEventQueue();

    expect(method.calls.first.method, 'start');
    expect(
      (method.calls.first.arguments as Map<String, Object?>)['physicalWidthCm'],
      29.5,
    );

    source.add(<String, Object?>{
      'event': 'image_detected',
      'timestampMs': 1758528000000,
    });
    source.add(<String, Object?>{'event': 'node_completed'}); // 业务结论一律不接
    source.add(<String, Object?>{'event': 'tracking_lost'});
    await pumpEventQueue();

    expect(collected.map((e) => e.kind), <ArEventKind>[
      ArEventKind.imageDetected,
      ArEventKind.trackingLost,
    ]);
    expect(
      collected.first.at,
      DateTime.fromMillisecondsSinceEpoch(1758528000000),
    );

    await sub.cancel();
    await source.close();
  });
}
