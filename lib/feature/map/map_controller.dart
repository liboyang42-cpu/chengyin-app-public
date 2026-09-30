import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/util/coord.dart';
import '../../data/models/city_resolve.dart';
import '../../data/models/nearby_node.dart';
import 'map_scene_mapper.dart';

class MapLocationException implements Exception {
  const MapLocationException(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

class MapPageData {
  const MapPageData({
    required this.scene,
    required this.nodes,
    required this.city,
  });

  final MapScene scene;
  final List<NearbyNode> nodes;
  final CityResolveResult city;
}

final currentMapLocationProvider = FutureProvider.autoDispose<MapCoordinate>((
  ref,
) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const MapLocationException('请开启系统定位后重试', canOpenSettings: true);
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const MapLocationException(
      '定位权限已被永久关闭，请到系统设置中开启',
      canOpenSettings: true,
    );
  }
  if (permission == LocationPermission.denied) {
    throw const MapLocationException('需要定位权限才能发现附近节点');
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
  final gcj = wgs84ToGcj02(position.longitude, position.latitude);
  return MapCoordinate(latitude: gcj.lat, longitude: gcj.lng);
});

final mapPageDataProvider = FutureProvider.autoDispose<MapPageData>((
  ref,
) async {
  final location = await ref.watch(currentMapLocationProvider.future);
  final nodes = await ref
      .watch(mapApiProvider)
      .nearby(longitude: location.longitude, latitude: location.latitude);
  CityResolveResult city;
  try {
    city = await ref.watch(mapApiProvider).reverseGeocode(
          longitude: location.longitude,
          latitude: location.latitude,
        );
  } catch (_) {
    // 城市名是首页附加信息，失败不能拖垮地图；也不记录原始坐标或异常报文。
    city = const CityResolveResult();
  }
  return MapPageData(
    scene: MapScene.build(
      points: mapNearbyNodes(nodes),
      userLocation: location,
    ),
    nodes: nodes,
    city: city,
  );
});

final mapPrivacyAgreementProvider = FutureProvider<bool>((ref) {
  return ref.watch(mapPrivacyStoreProvider).hasAgreed();
});
