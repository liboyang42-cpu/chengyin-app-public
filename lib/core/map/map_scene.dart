enum MapPointState { normal, active, done, locked }

class MapCoordinate {
  const MapCoordinate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  @override
  bool operator ==(Object other) =>
      other is MapCoordinate &&
      latitude == other.latitude &&
      longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

class MapPoint extends MapCoordinate {
  const MapPoint({
    required this.id,
    required super.latitude,
    required super.longitude,
    this.title,
    this.subtitle,
    this.topicId,
    this.nodeId,
    this.sortOrder = 0,
    this.state = MapPointState.normal,
    this.fenceRadiusMeters,
  });

  final String id;
  final String? title;
  final String? subtitle;
  final int? topicId;
  final int? nodeId;
  final int sortOrder;
  final MapPointState state;
  final double? fenceRadiusMeters;
}

class MapScene {
  const MapScene({
    required this.points,
    required this.routePoints,
    required this.center,
    this.userLocation,
  });

  static const MapCoordinate defaultCenter = MapCoordinate(
    latitude: 31.2304,
    longitude: 121.4737,
  );

  final List<MapPoint> points;
  final List<MapPoint> routePoints;
  final MapCoordinate center;
  final MapCoordinate? userLocation;

  factory MapScene.build({
    required List<MapPoint> points,
    MapCoordinate? userLocation,
  }) {
    final validPoints = points.where((point) => point.isValid).toList();
    final validUserLocation = userLocation?.isValid == true
        ? userLocation
        : null;
    final routePoints = List<MapPoint>.of(validPoints)
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));

    return MapScene(
      points: List<MapPoint>.unmodifiable(validPoints),
      routePoints: List<MapPoint>.unmodifiable(routePoints),
      center:
          validUserLocation ??
          (validPoints.isNotEmpty ? validPoints.first : defaultCenter),
      userLocation: validUserLocation,
    );
  }
}
