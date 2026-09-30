import '../../core/map/map_scene.dart';
import '../../data/models/checkin_models.dart';
import '../../data/models/nearby_node.dart';

List<MapPoint> mapNearbyNodes(List<NearbyNode> nodes) => nodes
    .map((node) {
      final latitude = double.tryParse(node.latitude);
      final longitude = double.tryParse(node.longitude);
      if (latitude == null || longitude == null) return null;
      final point = MapPoint(
        id: 'nearby-${node.id}',
        latitude: latitude,
        longitude: longitude,
        title: node.addressName,
        subtitle: node.address,
        topicId: node.topicId,
        nodeId: node.nodeId,
      );
      return point.isValid ? point : null;
    })
    .whereType<MapPoint>()
    .toList(growable: false);

List<MapPoint> mapPlayNodes(List<PlayNode> nodes) => nodes
    .map((node) {
      if (node.latitude == null || node.longitude == null) return null;
      final point = MapPoint(
        id: 'play-${node.nodeId}',
        latitude: node.latitude!,
        longitude: node.longitude!,
        title: node.name,
        subtitle: node.address,
        nodeId: node.nodeId,
        sortOrder: node.sortId,
        state: node.done ? MapPointState.done : MapPointState.normal,
        fenceRadiusMeters: node.needGps ? 50 : null,
      );
      return point.isValid ? point : null;
    })
    .whereType<MapPoint>()
    .toList(growable: false);
