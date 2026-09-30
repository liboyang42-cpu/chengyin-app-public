import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'playkit_fullscreen_logic.dart';

/// 整屏族的传感器来源。
///
/// 与 `stillness_platform.dart` 同一套路:接口在这里,真实现注入,组件
/// 构造时可以换一份假流 —— widget 测试不碰 MethodChannel,行为照样可测。
/// **组件只从这里取传感器数据,自己不 new 平台对象**(否则测试里必炸
/// MissingPluginException,而那块逻辑就永远测不到)。

@immutable
class PlayKitAcceleration {
  const PlayKitAcceleration({
    required this.x,
    required this.y,
    required this.z,
    required this.at,
  });

  /// sensors_plus 原生口径:m/s²(含重力)。
  final double x;
  final double y;
  final double z;
  final Duration at;
}

/// 加速度来源。摇一摇(coinflip / diceroll)与倾斜(ballshake)共用。
abstract interface class PlayKitAccelerationSource {
  Stream<PlayKitAcceleration> watch();
}

class PlayKitDeviceAccelerationSource implements PlayKitAccelerationSource {
  const PlayKitDeviceAccelerationSource();

  @override
  Stream<PlayKitAcceleration> watch() {
    return accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).map(
      (AccelerometerEvent event) => PlayKitAcceleration(
        x: event.x,
        y: event.y,
        z: event.z,
        at: Duration(microseconds: event.timestamp.microsecondsSinceEpoch),
      ),
    );
  }
}

/// 麦克风响度来源(0–1 线性峰值)。quietHold 用。
abstract interface class PlayKitSoundLevelSource {
  Stream<double> watch();
  Future<void> start();
  Future<void> stop();
}

/// 拿不到麦克风(没授权 / 设备拒绝)时抛这个,由组件翻成「不假装在听」的失败态。
class PlayKitMicUnavailable implements Exception {
  const PlayKitMicUnavailable(this.message);

  final String message;

  @override
  String toString() => 'PlayKitMicUnavailable: $message';
}

/// 每帧响度的采样间隔。照抄小程序 TICK_MS / FRAME_MS(采样节拍,不是过渡)。
const Duration kQuietPoll = Duration(milliseconds: 100);

/// `record` 插件实现:录到一个临时文件(内容**不上传、不落盘持久、用完即删**),
/// 期间只消费振幅流。小程序那边同理:这一屏只需要每帧振幅,不需要内容。
class PlayKitRecorderSoundLevelSource implements PlayKitSoundLevelSource {
  PlayKitRecorderSoundLevelSource({
    AudioRecorder? recorder,
    this.poll = kQuietPoll,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final Duration poll;
  final StreamController<double> _levels =
      StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  String? _path;

  @override
  Stream<double> watch() => _levels.stream;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw const PlayKitMicUnavailable('麦克风权限未开启');
    }
    final Directory dir = await Directory.systemTemp.createTemp('cy-quiet');
    _path = '${dir.path}/quiet.pcm';
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(poll)
        .listen(
          (Amplitude amplitude) =>
              _levels.add(decibelsToLinear(amplitude.current)),
        );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  @override
  Future<void> stop() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } on Object {
      // 已经停了 —— 停不下来不该盖过「这一局的结果」。
    }
    final String? path = _path;
    _path = null;
    if (path != null) {
      try {
        File(path).parent.delete(recursive: true);
      } on Object {
        // 临时目录清不掉不影响玩法;系统会回收。
      }
    }
  }
}
