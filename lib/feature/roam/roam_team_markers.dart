/// 漫游地图上的「附近的队伍 + 主题 / 活动」marker 层。
///
/// 真源(只读快照 github/master):
///   · `subpackageRoam/nearby/index.js` —— 接线(P1 顶部计数条 / marker 点击分派 /
///     `fetchTeams` + `fetchTopics` / 失败只报不吞);
///   · `utils/map-team.js:178-201` —— 队伍点位(id 编码 `teamId*10+4`);
///   · `utils/roam-hangout.js:26-90` —— 主题/活动点位(id 编码 `id*10+{2 活动,3 主题}`)。
///
/// ★ **局(kind=hangout)一律不画**:真源原话「地图上不存在「局」了」(9-15 裁决,
///   搭子局 A 已下架)。所以这里只画队伍 + 主题 + 活动三类。
/// ★ 状态机**只有一份**:卡片五态 / errorCode 分支 / 文案都在
///   `lib/data/models/team_map.dart`(`decorateTeam`),半屏走
///   `showTeamMarkerSheet` —— 与 `/team/nearby` 列表页同一个实现。
/// ★ 投影交给 MapKit(标成 Annotation 由原生落点),本层只做「谁画、画在哪、
///   点了去哪」三件事,不自己算像素 —— `roam_live_math` 的等距近似只服务迷雾层。
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_tokens.dart';
import '../../data/models/roam_social.dart';
import '../../data/models/team_map.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import '../team/team_nearby_page.dart' show teamMapApiProvider;
import 'roam_live_controller.dart';
import 'roam_live_math.dart';

// ── marker id 编码:末位是类型标签(真源 `map-team.js:12` / `roam-hangout.js:81`)──

const int _kActivityTag = 2;
const int _kTopicTag = 3;
const int _kTeamTag = 4; // 与 1(局,本层不画)/2/3 不撞号

/// 队伍层查询半径 = 小程序默认档(稿 591:1020 角控件写死「范围 1 km」)。
const int kRoamTeamMarkerRadiusM = 1000;

/// 点位身份:哪一类 + 原始 id(队伍 id / 主题 id / 活动 id)。
enum RoamMarkerKind { team, activity, topic }

@immutable
class RoamMarkerHit {
  const RoamMarkerHit(this.kind, this.id);

  final RoamMarkerKind kind;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is RoamMarkerHit && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// 队伍点位 id(Figma 点位在真源里的编码)。
String roamTeamMarkerId(int teamId) => '${teamId * 10 + _kTeamTag}';

/// marker id → 点位身份;不是本层的点位(漫游自己的 poi / 附近的人)返回 null。
RoamMarkerHit? parseRoamMarkerId(String id) {
  final int? value = int.tryParse(id);
  if (value == null || value <= 0 || value < 10) return null;
  final int tag = value % 10;
  final int raw = value ~/ 10;
  return switch (tag) {
    _kTeamTag => RoamMarkerHit(RoamMarkerKind.team, raw),
    _kActivityTag => RoamMarkerHit(RoamMarkerKind.activity, raw),
    _kTopicTag => RoamMarkerHit(RoamMarkerKind.topic, raw),
    _ => null,
  };
}

/// 画到地图上的点:队伍(GCJ-02,服务端原样)+ 主题 / 活动(同接口的另一类)。
///
/// 没坐标的点跳过(`roam-hangout.js:11` 的空值先拦,别画到几内亚湾);
/// 局一律跳过。
List<MapPoint> roamNearbyMarkerPoints({
  required List<Map<String, dynamic>> teams,
  required List<RoamHangoutItem> items,
}) {
  final List<MapPoint> out = <MapPoint>[];
  for (final Map<String, dynamic> row in teams) {
    final TeamNearbyCard card = decorateTeam(row);
    final int? teamId = card.teamId;
    final double? latitude = card.latitude;
    final double? longitude = card.longitude;
    if (teamId == null || latitude == null || longitude == null) continue;
    out.add(
      MapPoint(
        id: roamTeamMarkerId(teamId),
        latitude: latitude,
        longitude: longitude,
        title: card.name,
        subtitle: card.heading,
        // 我已在队里(队友 / 队长)的点与别人区分开:真源 teamMarkerSpec 的
        // state=joined,token 里对应 active。
        state: card.viewerStatus == 'JOINED' || card.viewerStatus == 'LEADER'
            ? MapPointState.active
            : MapPointState.normal,
      ),
    );
  }
  for (final RoamHangoutItem item in items) {
    if (item.isHangout) continue;
    final double? latitude = item.latitude;
    final double? longitude = item.longitude;
    if (latitude == null || longitude == null) continue;
    out.add(
      MapPoint(
        id: '${item.id * 10 + (item.isTopic ? _kTopicTag : _kActivityTag)}',
        latitude: latitude,
        longitude: longitude,
        title: item.label,
        subtitle: item.isTopic ? '主题' : '限时活动',
      ),
    );
  }
  return out;
}

/// 一层点位的数据:`/api/team/nearby` 的原始行(视图一律走 `decorateTeam` 白名单)
/// + `/api/roam/hangout/nearby` 的主题 / 活动。
@immutable
class RoamNearbyLayer {
  const RoamNearbyLayer({
    this.teams = const <Map<String, dynamic>>[],
    this.items = const <RoamHangoutItem>[],
  });

  final List<Map<String, dynamic>> teams;
  final List<RoamHangoutItem> items;

  RoamNearbyLayer withTeams(List<Map<String, dynamic>> next) =>
      RoamNearbyLayer(teams: next, items: items);

  /// 按 teamId 找原始行(marker 点开半屏时用)。
  Map<String, dynamic>? rowOf(int teamId) {
    for (final Map<String, dynamic> row in teams) {
      if (decorateTeam(row).teamId == teamId) return row;
    }
    return null;
  }
}

/// 队伍层的取数格 ≈ 1.2 km(geohash 6):跨格才重拉,不跟定位每秒重拉。
///
/// 小程序是「拖图/缩放停 600 ms 后重拉」(`index.js:270` onRegionChange);
/// App 这张图不跟随拖动重拉(漫游原本就不跟),所以按格缓存等价于同一个口径。
final Provider<String?> roamNearbyCellProvider = Provider<String?>((ref) {
  final RoamLivePosition? position = ref.watch(
    roamLiveControllerProvider.select((RoamLiveState s) => s.location),
  );
  if (position == null) return null;
  return roamTileKey(position.latitude, position.longitude, precision: 6);
});

final AsyncNotifierProvider<RoamNearbyLayerController, RoamNearbyLayer>
roamNearbyLayerProvider =
    AsyncNotifierProvider.autoDispose<RoamNearbyLayerController, RoamNearbyLayer>(
      RoamNearbyLayerController.new,
      // 不自动重试:失败就在 HUD 上给「重试」(真源也是手动重试),401 更要人来过
      // 一道登录,不能拿退避重试去撞它。
      retry: (int retryCount, Object error) => null,
    );

class RoamNearbyLayerController extends AsyncNotifier<RoamNearbyLayer> {
  @override
  Future<RoamNearbyLayer> build() async {
    final String? cell = ref.watch(roamNearbyCellProvider);
    if (cell == null) return const RoamNearbyLayer();
    final RoamTileBounds? bounds = roamTileBounds(cell);
    if (bounds == null) return const RoamNearbyLayer();
    final double lat = bounds.centerLatitude;
    final double lng = bounds.centerLongitude;
    final List<Map<String, dynamic>> teams = await ref
        .read(teamMapApiProvider)
        .nearby(lat: lat, lng: lng, radiusM: kRoamTeamMarkerRadiusM);
    // 主题层拉不到只是少一层点,队伍层照常(真源 `fetchTopics` 的 `if (!d) return`)。
    List<RoamHangoutItem> items = const <RoamHangoutItem>[];
    try {
      final RoamHangoutNearby nearby = await ref
          .read(roamApiProvider)
          .hangoutNearby(lat: lat, lng: lng, radiusM: kRoamTeamMarkerRadiusM);
      items = nearby.items;
    } catch (_) {}
    if (!ref.mounted) return const RoamNearbyLayer();
    return RoamNearbyLayer(teams: teams, items: items);
  }

  /// 半屏里动作成功后的本地补丁(申请成功 → PENDING 等),不重拉。
  void patchTeam(int teamId, Map<String, Object?> patch) {
    final RoamNearbyLayer? data = state.value;
    if (data == null) return;
    state = AsyncData<RoamNearbyLayer>(
      data.withTeams(<Map<String, dynamic>>[
        for (final Map<String, dynamic> row in data.teams)
          if (decorateTeam(row).teamId == teamId)
            <String, dynamic>{...row, ...patch}
          else
            row,
      ]),
    );
  }

  /// 满员 / 开场 / 审核中 / 邀请制:从地图上撤下(快照 `_dropTeam`)。
  void dropTeam(int teamId) {
    final RoamNearbyLayer? data = state.value;
    if (data == null) return;
    state = AsyncData<RoamNearbyLayer>(
      data.withTeams(<Map<String, dynamic>>[
        for (final Map<String, dynamic> row in data.teams)
          if (decorateTeam(row).teamId != teamId) row,
      ]),
    );
  }

  /// 队长审批后重拉,并回答「这支队伍还在不在」——不在就把半屏收掉。
  Future<bool> refreshTeam(int teamId) async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {}
    return state.value?.rowOf(teamId) != null;
  }
}

/// HUD 里的队伍层一行(P1 顶部条)+ 三态。
///
/// 计数文案取自真源 `utils/map-team.js:105`(「附近的队伍 · N 支在招募」);
/// 失败文案取自 `subpackageRoam/nearby/index.wxml:25`
/// (「附近的队伍没能读到 / 地图还在,队伍这次没读到 / 重试」)。
class RoamNearbyLayerRow extends ConsumerWidget {
  const RoamNearbyLayerRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RoamNearbyLayer> layer = ref.watch(roamNearbyLayerProvider);
    final RoamNearbyLayer? data = layer.value;
    final bool loggedIn = ref.watch(authControllerProvider).isLoggedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: CyTokens.space2),
        Row(
          children: <Widget>[
            const Icon(
              CupertinoIcons.group,
              size: 14,
              color: CyTokens.textSecondary,
            ),
            const SizedBox(width: CyTokens.space1),
            Expanded(
              child: Text(
                // 失败档计数条不谎称「读取中」:真源 `index.js:55` 失败时顶部条
                // 保持 `headerText(上次结果)`(初始 0),错误另走下方一行。
                layer.hasError && data == null
                    ? teamHeaderText(0)
                    : data == null
                        ? '附近的队伍 · 读取中'
                        : teamHeaderText(data.teams.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (layer.hasError) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            '附近的队伍没能读到',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CyTokens.statusDanger,
            ),
          ),
          Text(
            loggedIn ? '地图还在,队伍这次没读到' : '登录状态已失效,登录后接着看',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CyTokens.textSecondary,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: CupertinoButton(
              key: const Key('roam-team-layer-retry'),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () async {
                if (!loggedIn) {
                  // 401 走登录引导,不是「检查网络」。
                  final bool ok = await requireLogin(context, ref);
                  if (!ok) return;
                }
                ref.invalidate(roamNearbyLayerProvider);
              },
              child: Text(loggedIn ? '重试' : '去登录'),
            ),
          ),
        ],
      ],
    );
  }
}
