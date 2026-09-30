import 'package:flutter/services.dart';

import 'map_scene.dart';

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;
}

const MethodChannel _channel = MethodChannel('com.chengyin.app/place_search');

/// MapKit `MKLocalSearch`(原生桥在 `AppDelegate.swift`)。
///
/// ★ 中国境内返回 GCJ-02,与后端节点一致(Task 1.1 模拟器实测),原样使用。
/// 原生报错(`PlatformException`)向上抛,由页面显示失败态。
Future<List<PlaceResult>> searchPlaces(
  String query, {
  required MapCoordinate near,
}) async {
  final String q = query.trim();
  if (q.isEmpty) return const <PlaceResult>[];
  final List<Object?> raw =
      await _channel.invokeMethod<List<Object?>>('search', <String, Object>{
        'query': q,
        'latitude': near.latitude,
        'longitude': near.longitude,
      }) ??
      const <Object?>[];
  return <PlaceResult>[
    for (final Object? item in raw)
      if (item is Map &&
          item['name'] is String &&
          item['latitude'] is num &&
          item['longitude'] is num)
        PlaceResult(
          name: item['name'] as String,
          address: (item['address'] as String?) ?? '',
          latitude: (item['latitude'] as num).toDouble(),
          longitude: (item['longitude'] as num).toDouble(),
        ),
  ];
}
