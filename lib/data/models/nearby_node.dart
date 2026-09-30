/// 周边节点模型(对齐后端 `NearbyNodeVO` / `/api/map/nearby`)。
class NearbyNode {
  NearbyNode({
    required this.id,
    required this.addressName,
    required this.longitude,
    required this.latitude,
    this.topicId,
    this.nodeId,
    this.address,
    this.picUrl,
    this.distance,
  });

  final int id;
  final String addressName;
  final String longitude;
  final String latitude;
  final int? topicId;
  final int? nodeId;
  final String? address;
  final String? picUrl;

  /// 距查询点直线距离(米),后端计算。
  final double? distance;

  factory NearbyNode.fromJson(Map<String, dynamic> json) => NearbyNode(
    id: (json['id'] as num?)?.toInt() ?? 0,
    addressName: (json['addressName'] ?? '') as String,
    longitude: (json['longitude'] ?? '') as String,
    latitude: (json['latitude'] ?? '') as String,
    topicId: (json['topicId'] as num?)?.toInt(),
    nodeId: (json['nodeId'] as num?)?.toInt(),
    address: json['address'] as String?,
    picUrl: json['picUrl'] as String?,
    distance: (json['distance'] as num?)?.toDouble(),
  );
}
