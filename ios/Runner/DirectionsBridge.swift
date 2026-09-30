import Flutter
import MapKit
import UIKit

/// `com.chengyin.app/directions`:MKDirections 路线、MKMapItem.openMaps、路线快照。
/// 进出坐标均为 GCJ-02(国行 MapKit 道路数据同系),Dart 侧负责设备 WGS84 换算。
final class DirectionsBridge {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.chengyin.app/directions", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "calculate": DirectionsBridge.calculate(args, result)
      case "openInMaps": DirectionsBridge.openInMaps(args, result)
      case "snapshot": DirectionsBridge.snapshot(args, result)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func coordinate(_ args: [String: Any], _ lat: String, _ lng: String) -> CLLocationCoordinate2D? {
    guard let la = args[lat] as? Double, let ln = args[lng] as? Double else { return nil }
    let c = CLLocationCoordinate2D(latitude: la, longitude: ln)
    return CLLocationCoordinate2DIsValid(c) ? c : nil
  }

  private static func invalid(_ result: FlutterResult) {
    result(FlutterError(code: "invalid_arguments", message: "Directions arguments are incomplete", details: nil))
  }

  private static func calculate(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let from = coordinate(args, "fromLat", "fromLng"), let to = coordinate(args, "toLat", "toLng") else {
      return invalid(result)
    }
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
    switch args["mode"] as? String {
    case "driving": request.transportType = .automobile
    case "transit": request.transportType = .transit
    default: request.transportType = .walking
    }
    let directions = MKDirections(request: request)
    let noRoute = { (error: Error?) in
      result(FlutterError(code: "no_route", message: error?.localizedDescription, details: nil))
    }
    // MKDirections.calculate 不给公交路线(iOS 13–26 一致),公交只取 ETA;Dart 侧补直线与提示。
    if request.transportType == .transit {
      directions.calculateETA { response, error in
        _ = directions
        guard let eta = response else { return noRoute(error) }
        result([
          "distance": eta.distance,
          "expectedTravelTime": eta.expectedTravelTime,
          "polyline": [Double](),
          "steps": [Any](),
        ])
      }
      return
    }
    directions.calculate { response, error in
      _ = directions
      guard let route = response?.routes.first else { return noRoute(error) }
      result([
        "distance": route.distance,
        "expectedTravelTime": route.expectedTravelTime,
        "polyline": flatten(route.polyline),
        "steps": route.steps.map { step -> [String: Any] in
          let start = step.polyline.pointCount > 0
            ? step.polyline.points()[0].coordinate
            : step.polyline.coordinate
          return [
            "instruction": step.instructions,
            "distance": step.distance,
            "latitude": start.latitude,
            "longitude": start.longitude,
          ]
        },
      ])
    }
  }

  private static func flatten(_ polyline: MKPolyline) -> [Double] {
    let points = polyline.points()
    var out = [Double]()
    out.reserveCapacity(polyline.pointCount * 2)
    for i in 0..<polyline.pointCount {
      let c = points[i].coordinate
      out.append(c.latitude)
      out.append(c.longitude)
    }
    return out
  }

  private static func openInMaps(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let to = coordinate(args, "lat", "lng") else { return invalid(result) }
    let item = MKMapItem(placemark: MKPlacemark(coordinate: to))
    item.name = args["name"] as? String
    let mode: String
    switch args["mode"] as? String {
    case "driving": mode = MKLaunchOptionsDirectionsModeDriving
    case "transit": mode = MKLaunchOptionsDirectionsModeTransit
    default: mode = MKLaunchOptionsDirectionsModeWalking
    }
    result(MKMapItem.openMaps(
      with: [MKMapItem.forCurrentLocation(), item],
      launchOptions: [MKLaunchOptionsDirectionsModeKey: mode]
    ))
  }

  /// 路线预览图:Apple 地图底图 + 路线折线 + 起终点(+ 当前位置)。返回 PNG。
  private static func snapshot(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let flat = args["polyline"] as? [Double] ?? []
    let width = args["width"] as? Double ?? 0
    let height = args["height"] as? Double ?? 0
    guard flat.count >= 4, width > 0, height > 0 else { return invalid(result) }
    var coords = [CLLocationCoordinate2D]()
    for i in stride(from: 0, to: flat.count - 1, by: 2) {
      coords.append(CLLocationCoordinate2D(latitude: flat[i], longitude: flat[i + 1]))
    }
    let user = coordinate(args, "userLat", "userLng")
    var rect = MKPolyline(coordinates: coords, count: coords.count).boundingMapRect
    if let user {
      rect = rect.union(MKMapRect(origin: MKMapPoint(user), size: MKMapSize(width: 0, height: 0)))
    }
    let pad = max(rect.size.width, rect.size.height) * 0.18 + 300
    let options = MKMapSnapshotter.Options()
    options.mapRect = rect.insetBy(dx: -pad, dy: -pad)
    options.size = CGSize(width: width, height: height)
    options.traitCollection = UITraitCollection(userInterfaceStyle: args["dark"] as? Bool == true ? .dark : .light)
    let snapshotter = MKMapSnapshotter(options: options)
    snapshotter.start(with: .main) { snapshot, error in
      _ = snapshotter
      guard let snapshot else {
        return result(FlutterError(code: "snapshot_failed", message: error?.localizedDescription, details: nil))
      }
      let image = UIGraphicsImageRenderer(size: options.size).image { _ in
        snapshot.image.draw(at: .zero)
        let path = UIBezierPath()
        for (i, c) in coords.enumerated() {
          let p = snapshot.point(for: c)
          if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.lineWidth = 6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        UIColor.systemBlue.setStroke()
        path.stroke()
        dot(snapshot.point(for: coords[0]), fill: .white, stroke: .systemBlue)
        dot(snapshot.point(for: coords[coords.count - 1]), fill: .systemRed, stroke: .white)
        if let user { dot(snapshot.point(for: user), fill: .systemBlue, stroke: .white) }
      }
      guard let png = image.pngData() else {
        return result(FlutterError(code: "snapshot_failed", message: nil, details: nil))
      }
      result(FlutterStandardTypedData(bytes: png))
    }
  }

  private static func dot(_ center: CGPoint, fill: UIColor, stroke: UIColor) {
    let circle = UIBezierPath(ovalIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
    fill.setFill()
    circle.fill()
    circle.lineWidth = 3
    stroke.setStroke()
    circle.stroke()
  }
}
