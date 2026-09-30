import 'package:apple_maps_flutter/apple_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/cy_tokens.dart';
import 'map_scene.dart';

/// Apple Maps(MapKit)承载地图场景,构造签名与 `AmapSceneView` 一致。
///
/// ★ 坐标系:后端节点是 GCJ-02;MapKit 在中国境内的底图同样是 GCJ-02,
///   所以后端坐标**原样**喂进来(Task 1.1 模拟器实测过)。
/// ★ Android 暂不支持(决策 D1):闸放在组件里,不靠调用方各挡一次。
class AppleSceneView extends StatefulWidget {
  const AppleSceneView({
    super.key,
    required this.scene,
    this.onPointTap,
    this.onCenterChanged,
  });

  final MapScene scene;
  final ValueChanged<MapPoint>? onPointTap;
  final ValueChanged<MapCoordinate>? onCenterChanged;

  @override
  State<AppleSceneView> createState() => _AppleSceneViewState();
}

class _AppleSceneViewState extends State<AppleSceneView> {
  AppleMapController? _controller;
  MapCoordinate _lastCenter;

  _AppleSceneViewState() : _lastCenter = MapScene.defaultCenter;

  @override
  void didUpdateWidget(AppleSceneView old) {
    super.didUpdateWidget(old);
    final MapCoordinate next = widget.scene.center;
    if (next != _lastCenter) {
      _lastCenter = next;
      // 地图常驻的页面(如地图搜索)在加载完成后才拿到真实中心点:
      // initialCameraPosition 只在创建时生效,中心变了必须自己挪相机。
      _controller?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(next.latitude, next.longitude),
            zoom: 15,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final MapScene scene = widget.scene;
    _lastCenter = scene.center;
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const _MapUnavailable();
    }

    final annotations = scene.points.map((point) {
      return Annotation(
        annotationId: AnnotationId(point.id),
        position: LatLng(point.latitude, point.longitude),
        infoWindow: InfoWindow(title: point.title, snippet: point.subtitle),
        onTap: () => widget.onPointTap?.call(point),
      );
    }).toSet();
    final route = scene.routePoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    // MapKit 有原生圆,不必像高德那样用 32 边形近似。
    final fences = scene.points
        .where((point) => (point.fenceRadiusMeters ?? 0) > 0)
        .map(
          (point) => Circle(
            circleId: CircleId('fence_${point.id}'),
            center: LatLng(point.latitude, point.longitude),
            radius: point.fenceRadiusMeters!,
            strokeWidth: 2,
            strokeColor: AppColors.nodeGlow.withValues(alpha: 0.67),
            fillColor: AppColors.nodeGlow.withValues(alpha: 0.13),
          ),
        )
        .toSet();

    LatLng? lastCenter;
    return AppleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(scene.center.latitude, scene.center.longitude),
        zoom: 15,
      ),
      compassEnabled: true,
      myLocationEnabled: scene.userLocation != null,
      annotations: annotations,
      polylines: route.length > 1
          ? <Polyline>{
              Polyline(
                polylineId: PolylineId('route'),
                points: route,
                width: 6,
                color: AppColors.accentViolet,
                polylineCap: Cap.roundCap,
                jointType: JointType.round,
              ),
            }
          : const <Polyline>{},
      circles: fences,
      onMapCreated: (AppleMapController controller) => _controller = controller,
      onCameraMove: (position) => lastCenter = position.target,
      // 判空放进回调里:build 时 lastCenter 恒为 null。
      onCameraIdle: widget.onCenterChanged == null
          ? null
          : () {
              final center = lastCenter;
              if (center != null) {
                widget.onCenterChanged!(
                  MapCoordinate(
                    latitude: center.latitude,
                    longitude: center.longitude,
                  ),
                );
              }
            },
    );
  }
}

/// 地图不可用时的占位(文案/样式与 `amap_scene_view.dart` 一致)。
///
/// 可能出现在任何嵌地图的位置,所以做成**填满父容器的居中提示**,不自己设尺寸。
class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CyTokens.bgSurface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.map_outlined,
                size: 32,
                color: CyTokens.textSecondary,
              ),
              const SizedBox(height: CyTokens.space2),
              Text(
                '地图暂时不可用',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: CyTokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
