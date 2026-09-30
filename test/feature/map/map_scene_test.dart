import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/data/models/nearby_node.dart';
import 'package:chengyin_app/feature/map/map_scene_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MapScene.build', () {
    test('filters invalid coordinates and keeps route order', () {
      final scene = MapScene.build(
        points: const <MapPoint>[
          MapPoint(id: 'b', latitude: 31.2, longitude: 121.5, sortOrder: 2),
          MapPoint(id: 'bad', latitude: 100, longitude: 121.5, sortOrder: 1),
          MapPoint(id: 'a', latitude: 31.1, longitude: 121.4, sortOrder: 1),
        ],
      );

      expect(scene.points.map((point) => point.id), <String>['b', 'a']);
      expect(scene.routePoints.map((point) => point.id), <String>['a', 'b']);
    });

    test('uses valid user location before the first point', () {
      const userLocation = MapCoordinate(latitude: 31.23, longitude: 121.47);
      final scene = MapScene.build(
        userLocation: userLocation,
        points: const <MapPoint>[
          MapPoint(id: 'a', latitude: 31.1, longitude: 121.4),
        ],
      );

      expect(scene.center, userLocation);
    });

    test('falls back to first valid point when user location is invalid', () {
      final scene = MapScene.build(
        userLocation: const MapCoordinate(latitude: double.nan, longitude: 0),
        points: const <MapPoint>[
          MapPoint(id: 'bad', latitude: -91, longitude: 0),
          MapPoint(id: 'valid', latitude: 30, longitude: 120),
        ],
      );

      expect(scene.center, const MapCoordinate(latitude: 30, longitude: 120));
    });
  });

  test('maps nearby nodes and skips invalid string coordinates', () {
    final points = mapNearbyNodes(<NearbyNode>[
      NearbyNode(
        id: 7,
        addressName: '外滩',
        longitude: '121.49',
        latitude: '31.24',
        topicId: 8,
        nodeId: 9,
      ),
      NearbyNode(
        id: 10,
        addressName: '坏坐标',
        longitude: 'not-a-number',
        latitude: '31.2',
      ),
    ]);

    expect(points, hasLength(1));
    expect(points.single.id, 'nearby-7');
    expect(points.single.topicId, 8);
    expect(points.single.nodeId, 9);
  });

  test('maps play nodes in route order and preserves done state', () {
    final points = mapPlayNodes(const <PlayNode>[
      PlayNode(
        nodeId: 2,
        name: '第二站',
        address: 'B',
        sortId: 2,
        done: true,
        longitude: 121.5,
        latitude: 31.2,
      ),
      PlayNode(
        nodeId: 1,
        name: '第一站',
        address: 'A',
        sortId: 1,
        done: false,
        longitude: 121.4,
        latitude: 31.1,
      ),
    ]);

    final scene = MapScene.build(points: points);
    expect(scene.routePoints.map((point) => point.nodeId), <int>[1, 2]);
    expect(scene.points.first.state, MapPointState.done);
  });
}
