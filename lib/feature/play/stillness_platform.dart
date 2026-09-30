import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'stillness_challenge_controller.dart';

class SensorsPlusStillnessSampleSource implements StillnessSampleSource {
  @override
  Stream<StillnessSample> watch() {
    return accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).map(
      (AccelerometerEvent event) => StillnessSample(
        x: event.x,
        y: event.y,
        z: event.z,
        timestamp: Duration(
          microseconds: event.timestamp.microsecondsSinceEpoch,
        ),
      ),
    );
  }
}

abstract interface class ScreenWakeLock {
  Future<void> enable();
  Future<void> disable();
}

class WakelockPlusScreenWakeLock implements ScreenWakeLock {
  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

final stillnessSampleSourceProvider = Provider<StillnessSampleSource>(
  (_) => SensorsPlusStillnessSampleSource(),
);

final screenWakeLockProvider = Provider<ScreenWakeLock>(
  (_) => WakelockPlusScreenWakeLock(),
);
