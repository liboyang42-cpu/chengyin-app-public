import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/map_api.dart';
import 'package:chengyin_app/data/models/city_resolve.dart';
import 'package:chengyin_app/data/models/nearby_node.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';

class _MapApi implements MapApi {
  double? reverseLongitude;
  double? reverseLatitude;

  @override
  Future<List<NearbyNode>> nearby({
    required double longitude,
    required double latitude,
    double radius = 2000,
    int limit = 50,
  }) async => <NearbyNode>[];

  @override
  Future<CityResolveResult> reverseGeocode({
    required double longitude,
    required double latitude,
  }) async {
    reverseLongitude = longitude;
    reverseLatitude = latitude;
    return const CityResolveResult(city: '上海市');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('地图首页用当次定位逆地理编码城市，不另造坐标', () async {
    final api = _MapApi();
    final container = ProviderContainer(
      overrides: <dynamic>[
        mapApiProvider.overrideWithValue(api),
        currentMapLocationProvider.overrideWith(
          (ref) async =>
              const MapCoordinate(latitude: 31.23, longitude: 121.47),
        ),
      ].cast(),
    );
    addTearDown(container.dispose);

    final data = await container.read(mapPageDataProvider.future);

    expect(api.reverseLongitude, 121.47);
    expect(api.reverseLatitude, 31.23);
    expect(data.city.city, '上海市');
  });
}
