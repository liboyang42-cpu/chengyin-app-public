import 'dart:math';

/// 坐标系转换工具。
///
/// 手机 GPS(geolocator)返回的是 WGS84 坐标,而城瘾后端的节点坐标 / 围栏
/// 判定使用的是 gcj02(高德 / 国测局)。中国境内两者相差数十到数百米,
/// 直接拿 WGS84 去比对后端的 50m 围栏会误判"还没到",所以上报前必须先转换。
const double _a = 6378245.0;
const double _ee = 0.00669342162296594323;

bool _outOfChina(double lat, double lng) {
  return lng < 72.004 ||
      lng > 137.8347 ||
      lat < 0.8293 ||
      lat > 55.8271;
}

double _transformLat(double x, double y) {
  var ret = -100 +
      2 * x +
      3 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * sqrt(x.abs());
  ret += (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3;
  ret += (20 * sin(y * pi) + 40 * sin(y / 3 * pi)) * 2 / 3;
  ret += (160 * sin(y / 12 * pi) + 320 * sin(y * pi / 30)) * 2 / 3;
  return ret;
}

double _transformLng(double x, double y) {
  var ret = 300 +
      x +
      2 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * sqrt(x.abs());
  ret += (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3;
  ret += (20 * sin(x * pi) + 40 * sin(x / 3 * pi)) * 2 / 3;
  ret += (150 * sin(x / 12 * pi) + 300 * sin(x / 30 * pi)) * 2 / 3;
  return ret;
}

/// 把 WGS84 坐标转换为 gcj02 坐标。
///
/// 境外坐标原样返回(gcj02 仅在中国境内有偏移定义)。
({double lng, double lat}) wgs84ToGcj02(double lng, double lat) {
  if (_outOfChina(lat, lng)) {
    return (lng: lng, lat: lat);
  }
  var dLat = _transformLat(lng - 105.0, lat - 35.0);
  var dLng = _transformLng(lng - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * pi;
  var magic = sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = sqrt(magic);
  dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * pi);
  dLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * pi);
  return (lng: lng + dLng, lat: lat + dLat);
}
