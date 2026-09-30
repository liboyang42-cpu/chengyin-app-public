// 路线/导航用的前台定位:当前位置 + 持续位置流,出参一律 GCJ-02。
//
// 失败分三类,文案对齐小程序 utils/location/location-manager.js 的拒绝引导
// (「需要位置权限 / 请在…设置中开启位置权限，以便继续使用位置功能 / 去设置」)
// 与 App 地图页已有的「请开启系统定位后重试」。
// 定位仅前台按需采集(AGENTS.md 边界),流随订阅取消即停。

import 'package:geolocator/geolocator.dart';

import '../util/coord.dart';
import 'map_scene.dart';

enum LocationFailure { serviceDisabled, denied, deniedForever }

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.reason);

  final LocationFailure reason;

  String get title => switch (reason) {
    LocationFailure.serviceDisabled => '定位未开启',
    LocationFailure.denied || LocationFailure.deniedForever => '需要位置权限',
  };

  String get message => switch (reason) {
    LocationFailure.serviceDisabled => '请开启系统定位后重试',
    LocationFailure.denied => '开启位置权限后才能规划从你当前位置出发的路线',
    LocationFailure.deniedForever => '请在系统设置中开启位置权限，以便继续使用位置功能',
  };

  /// 首次拒绝还能再弹系统授权框,不必把人赶去设置。
  bool get canOpenSettings => reason != LocationFailure.denied;

  @override
  String toString() => message;
}

class DeviceLocation {
  DeviceLocation({
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<MapCoordinate> Function()? currentWgs84,
    Stream<MapCoordinate> Function()? watchWgs84,
  }) : _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _currentWgs84 = currentWgs84 ?? _geolocatorCurrent,
       _watchWgs84 = watchWgs84 ?? _geolocatorWatch;

  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<MapCoordinate> Function() _currentWgs84;
  final Stream<MapCoordinate> Function() _watchWgs84;

  /// 确保可用(必要时弹系统授权框),否则抛 [LocationUnavailable]。
  Future<void> ensureAvailable() async {
    if (!await _serviceEnabled()) {
      throw const LocationUnavailable(LocationFailure.serviceDisabled);
    }
    LocationPermission permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    // iOS 家长控制等「受限」在 geolocator 里也归为 deniedForever。
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(LocationFailure.deniedForever);
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationUnavailable(LocationFailure.denied);
    }
  }

  Future<MapCoordinate>? _inFlight;

  /// 并发调用共用同一次请求:geolocator iOS 在上一次 getCurrentPosition 未返回时
  /// 再发一次,只回调最后一个,先发的 Future 永远不完成(模拟器实测卡住路线预览)。
  Future<MapCoordinate> current() =>
      _inFlight ??= _current().whenComplete(() => _inFlight = null);

  Future<MapCoordinate> _current() async {
    await ensureAvailable();
    return _toGcj(await _currentWgs84());
  }

  /// 持续位置流。先调 [ensureAvailable] 或 [current]。
  Stream<MapCoordinate> watch() => _watchWgs84().map(_toGcj);

  Future<void> openSettings(LocationFailure reason) async {
    if (reason == LocationFailure.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  static MapCoordinate _toGcj(MapCoordinate wgs) {
    final gcj = wgs84ToGcj02(wgs.longitude, wgs.latitude);
    return MapCoordinate(latitude: gcj.lat, longitude: gcj.lng);
  }

  static Future<MapCoordinate> _geolocatorCurrent() async {
    final Position p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return MapCoordinate(latitude: p.latitude, longitude: p.longitude);
  }

  static Stream<MapCoordinate> _geolocatorWatch() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
        ),
      ).map(
        (Position p) =>
            MapCoordinate(latitude: p.latitude, longitude: p.longitude),
      );
}
