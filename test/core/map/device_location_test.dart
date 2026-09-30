import 'package:chengyin_app/core/map/device_location.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

DeviceLocation _location({
  bool serviceEnabled = true,
  LocationPermission check = LocationPermission.whileInUse,
  LocationPermission request = LocationPermission.whileInUse,
  List<String>? log,
}) => DeviceLocation(
  serviceEnabled: () async => serviceEnabled,
  checkPermission: () async => check,
  requestPermission: () async {
    log?.add('request');
    return request;
  },
  currentWgs84: () async {
    log?.add('current');
    return const MapCoordinate(latitude: 31.2304, longitude: 121.4737);
  },
);

void main() {
  test('系统定位关闭 → serviceDisabled,可去设置', () async {
    await expectLater(
      _location(serviceEnabled: false).current(),
      throwsA(
        isA<LocationUnavailable>()
            .having((e) => e.reason, 'reason', LocationFailure.serviceDisabled)
            .having((e) => e.message, 'message', '请开启系统定位后重试')
            .having((e) => e.canOpenSettings, 'settings', isTrue),
      ),
    );
  });

  test('首次拒绝 → denied,不给去设置(还能再问)', () async {
    final List<String> log = <String>[];
    await expectLater(
      _location(
        check: LocationPermission.denied,
        request: LocationPermission.denied,
        log: log,
      ).current(),
      throwsA(
        isA<LocationUnavailable>()
            .having((e) => e.reason, 'reason', LocationFailure.denied)
            .having((e) => e.title, 'title', '需要位置权限')
            .having((e) => e.canOpenSettings, 'settings', isFalse),
      ),
    );
    expect(log, <String>['request']);
  });

  test('永久拒绝 / 受限 → deniedForever,引导去设置,不再弹系统框', () async {
    final List<String> log = <String>[];
    await expectLater(
      _location(check: LocationPermission.deniedForever, log: log).current(),
      throwsA(
        isA<LocationUnavailable>()
            .having((e) => e.reason, 'reason', LocationFailure.deniedForever)
            .having((e) => e.message, 'message', '请在系统设置中开启位置权限，以便继续使用位置功能')
            .having((e) => e.canOpenSettings, 'settings', isTrue),
      ),
    );
    expect(log, isEmpty);
  });

  test('并发 current() 共用一次定位请求(geolocator iOS 并发时只回调最后一个)', () async {
    int calls = 0;
    final DeviceLocation location = DeviceLocation(
      serviceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async => LocationPermission.whileInUse,
      currentWgs84: () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return const MapCoordinate(latitude: 31.2304, longitude: 121.4737);
      },
    );
    final List<MapCoordinate> both = await Future.wait(<Future<MapCoordinate>>[
      location.current(),
      location.current(),
    ]);
    expect(calls, 1);
    expect(both[0], both[1]);
    await location.current();
    expect(calls, 2, reason: '完成后下一次仍重新定位,不缓存旧位置');
  });

  test('授权后返回 GCJ-02(设备 WGS84 经 coord.dart 换算)', () async {
    final MapCoordinate c = await _location().current();
    // 上海境内 WGS84→GCJ-02 偏移约 +0.0045 经度 / -0.0020 纬度。
    expect(c.longitude - 121.4737, closeTo(0.0045, 0.001));
    expect(c.latitude - 31.2304, closeTo(-0.0020, 0.001));
  });
}
