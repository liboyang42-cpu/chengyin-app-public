import 'dart:math' as math;

const String _geohashAlphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

class RoamTileBounds {
  const RoamTileBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  double get centerLatitude => (minLatitude + maxLatitude) / 2;
  double get centerLongitude => (minLongitude + maxLongitude) / 2;
}

/// 与后端漫游瓦片一致的 geohash key（默认精度 7，约百米级）。
String roamTileKey(double latitude, double longitude, {int precision = 7}) {
  var latMin = -90.0;
  var latMax = 90.0;
  var lngMin = -180.0;
  var lngMax = 180.0;
  var evenBit = true;
  var value = 0;
  var bit = 0;
  final StringBuffer out = StringBuffer();

  while (out.length < precision) {
    if (evenBit) {
      final double mid = (lngMin + lngMax) / 2;
      if (longitude >= mid) {
        value = (value << 1) | 1;
        lngMin = mid;
      } else {
        value <<= 1;
        lngMax = mid;
      }
    } else {
      final double mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        value = (value << 1) | 1;
        latMin = mid;
      } else {
        value <<= 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    bit++;
    if (bit == 5) {
      out.write(_geohashAlphabet[value]);
      bit = 0;
      value = 0;
    }
  }
  return out.toString();
}

RoamTileBounds? roamTileBounds(String key) {
  var latMin = -90.0;
  var latMax = 90.0;
  var lngMin = -180.0;
  var lngMax = 180.0;
  var evenBit = true;

  for (final int unit in key.codeUnits) {
    final int value = _geohashAlphabet.indexOf(String.fromCharCode(unit));
    if (value < 0) return null;
    for (int mask = 16; mask > 0; mask >>= 1) {
      if (evenBit) {
        final double mid = (lngMin + lngMax) / 2;
        if ((value & mask) != 0) {
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        final double mid = (latMin + latMax) / 2;
        if ((value & mask) != 0) {
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      evenBit = !evenBit;
    }
  }
  return RoamTileBounds(
    minLatitude: latMin,
    maxLatitude: latMax,
    minLongitude: lngMin,
    maxLongitude: lngMax,
  );
}

double roamDistanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const double earthRadiusM = 6371000;
  final double dLat = (lat2 - lat1) * math.pi / 180;
  final double dLng = (lng2 - lng1) * math.pi / 180;
  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadiusM * math.asin(math.sqrt(a));
}
