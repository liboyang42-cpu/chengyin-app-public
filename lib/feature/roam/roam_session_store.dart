import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/roam_session.dart';

/// 漫游会话本地存储。对齐小程序 `wx.setStorageSync('roam_sessions')`:
/// 同一个 key 存 JSON 数组,最近 50 条封顶,新会话插到最前。
///
/// ★ 读失败与「没有记录」是两个态:读失败 = 记录还在、可重试;
///   没有记录 = 真没走过,显示空态。两者不能合并,否则空态会冒充
///   「你这次真的没走」。
class RoamSessionStore {
  RoamSessionStore(this._storage);

  static const String _key = 'roam_sessions';

  /// 同小程序:本地只留最近 50 条。
  static const int _maxSessions = 50;

  final FlutterSecureStorage _storage;

  /// 读全部会话(按 ts 倒序,同小程序 unshift 存储顺序)。
  /// 抛出 = 读失败(如底层存储不可用),调用方显示可重试的错误态。
  Future<List<RoamSession>> readAll() async {
    final String? raw = await _storage.read(key: _key);
    // 微信侧未命中 key 可能回空字符串;这里空串同样表示没有历史记录。
    if (raw == null || raw.isEmpty) return <RoamSession>[];
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('roam_sessions 不是数组');
    }
    final List<RoamSession> out = <RoamSession>[];
    for (final Object? item in decoded) {
      final RoamSession? s = RoamSession.tryParse(item);
      if (s == null) {
        // 坏记录不能静默跳过 —— 静默会让「坏了一条」表现为「少了 N 次漫游」,
        // 和读失败一样上报,让页面说「记录读不出来」而不是悄悄丢数据。
        throw const FormatException('roam_sessions 含非法记录');
      }
      out.add(s);
    }
    return out;
  }

  /// 按 ts 找一次会话。找不到返回 null(「找不到这次漫游」态,与读失败分开)。
  Future<RoamSession?> findByTs(int ts) async {
    final List<RoamSession> all = await readAll();
    for (final RoamSession s in all) {
      if (s.ts == ts) return s;
    }
    return null;
  }

  /// 追加一次会话到最前,封顶 [_maxSessions]。
  /// 实时漫游在服务端结算成功后调用，护照与回看共用这份真源。
  Future<void> prepend(RoamSession session) async {
    final List<RoamSession> all = await readAll();
    all.removeWhere((RoamSession s) => s.ts == session.ts);
    all.insert(0, session);
    final List<RoamSession> kept = all.length > _maxSessions
        ? all.sublist(0, _maxSessions)
        : all;
    await _storage.write(
      key: _key,
      value: jsonEncode(kept.map(_toJson).toList()),
    );
  }

  static Map<String, dynamic> _toJson(RoamSession s) => <String, dynamic>{
    'ts': s.ts,
    'zone': s.zone,
    'date': s.date,
    'dateLine': s.dateLine,
    'distance': s.distance,
    'explorePct': s.explorePct,
    'shops': s.shops,
    'time': s.time,
    'durSec': s.durSec,
    'photos': s.photos,
    'pois': s.pois
        .map(
          (RoamPoi p) => <String, dynamic>{
            'id': p.id,
            'name': p.name,
            'cat': p.cat,
            'lat': p.lat,
            'lng': p.lng,
          },
        )
        .toList(),
    'track': s.track
        .map((RoamPoint p) => <String, dynamic>{'lat': p.lat, 'lng': p.lng})
        .toList(),
    'medal': s.medal,
    'shopMedalName': s.shopMedalName,
  };
}
