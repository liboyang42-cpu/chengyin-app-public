import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_launcher.dart';
import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_net_image.dart';
import '../../core/widgets/cy_system_date_picker.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/api/roam_api.dart';
import '../../data/models/roam.dart';
import '../../data/models/roam_social.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'roam_hangout_logic.dart';
import 'roam_live_controller.dart';

/// 附近的局(对齐小程序 `subpackageRoam/nearby`)。
///
/// ★ 一图三类(局 / 主题 / 限时活动混排)+ 常驻 HUD + 底部抽屉。
///   抽屉里的四件事(筛选 / 我的局 / 附近的人 / 我的队伍)与「开一局」
///   表单照小程序结构搬;外观用 iOS 原生(Cupertino Sheet + 分组行),
///   不照抄小程序那套自绘黑底 HUD 皮肤。
///
/// ★ 隐私口径照小程序与后端 ApiRoamController,一条都不放宽:
///   · 附近的人只显示服务端截位(≈100 m)后的位置与那几样字段;
///   · 「在线」不是开关,停止上报 5 分钟后服务端自行摘除;
///   · 不额外把精确坐标拼进任何展示。
class RoamHangoutPage extends ConsumerStatefulWidget {
  const RoamHangoutPage({super.key, this.hangoutId});

  /// 深链:从漫游页那张「附近有人在组局」卡片进来时,直接开这一局的卡。
  final int? hangoutId;

  @override
  ConsumerState<RoamHangoutPage> createState() => _RoamHangoutPageState();
}

class _RoamHangoutPageState extends ConsumerState<RoamHangoutPage> {
  static const int _defaultRadius = 3000;

  MapCoordinate _center = MapScene.defaultCenter;
  MapCoordinate? _me;
  int _radius = _defaultRadius;
  List<RoamHangoutItem> _items = <RoamHangoutItem>[];
  List<RoamRunner> _runners = <RoamRunner>[];
  List<RoamHangoutItem> _places = <RoamHangoutItem>[];
  int? _suggestedRadius;
  int? _suggestedCount;
  bool _loaded = false;
  bool _loadError = false;
  int _loadSeq = 0;
  bool _deepLinkOpened = false;
  bool _expandUsed = false;

  RoamHangoutItem? _current;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final RoamLivePosition position = await ref
          .read(roamLocationSourceProvider)
          .current();
      if (!mounted) return;
      setState(() {
        _me = MapCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _center = _me!;
      });
    } catch (_) {
      // 定位拿不到就用兜底中心(人民广场),只用于首屏,不落库 —— 与小程序同款。
    }
    await _load();
  }

  Future<void> _load() async {
    final int seq = ++_loadSeq;
    // 游客:接口必然 401,先不发这个注定失败的请求 —— 列表位置给登录门
    // (B1 模拟器报告 P1:原来把 401 说成「列表没读到,重试」,重试永远是死路)。
    if (!ref.read(authControllerProvider).isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = true;
      });
      return;
    }
    try {
      final RoamHangoutNearby nearby = await ref
          .read(roamApiProvider)
          .hangoutNearby(
            lat: _center.latitude,
            lng: _center.longitude,
            radiusM: _radius,
          );
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _items = nearby.items;
        _suggestedRadius = nearby.suggestedRadius;
        _suggestedCount = nearby.suggestedCount;
        _loaded = true;
        _loadError = false;
      });
      unawaited(_fetchRunners());
      unawaited(_fetchPlaces());
      if (!_deepLinkOpened && widget.hangoutId != null) {
        _deepLinkOpened = true;
        unawaited(_openCard(widget.hangoutId!));
      }
    } catch (_) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loaded = true;
        _loadError = true;
      });
    }
  }

  /// 游客点「去登录」:登录完就地重拉列表,不把人踢去别的页。
  Future<void> _loginThenLoad() async {
    if (!await requireLogin(context, ref) || !mounted) return;
    setState(() => _loadError = false);
    await _load();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    CyNativeNotice.show(context, message, isError: isError);
  }

  /// 附近正在走的人:拉不到保持上一批,不清空(闪掉再回来更难看)。
  Future<void> _fetchRunners() async {
    try {
      final List<RoamRunner> rows = await ref
          .read(roamApiProvider)
          .nearbyRunners(lat: _center.latitude, lng: _center.longitude);
      if (!mounted) return;
      setState(() => _runners = rows);
    } catch (_) {
      // 静默:少一排人不影响这一屏的正事。
    }
  }

  /// 「别人打过卡的地方」:漫游 POI 里非商家的那些(小程序同款取数)。
  Future<void> _fetchPlaces() async {
    try {
      final List<RoamPoi> pois = await ref
          .read(roamApiProvider)
          .pois(lat: _center.latitude, lng: _center.longitude);
      if (!mounted) return;
      setState(() {
        _places = <RoamHangoutItem>[
          for (final RoamPoi poi in pois)
            if (poi.type != 2)
              RoamHangoutItem(
                kind: 'place',
                id: poi.id,
                name: poi.name,
                addressName: poi.address,
                latitude: poi.lat,
                longitude: poi.lng,
              ),
        ];
      });
    } catch (_) {
      // 拿不到就保持空:这一行是补充信息,不是正事。
    }
  }

  Future<void> _recenter() async {
    try {
      final RoamLivePosition position = await ref
          .read(roamLocationSourceProvider)
          .current();
      if (!mounted) return;
      setState(() {
        _me = MapCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _center = _me!;
      });
      await _load();
    } catch (_) {
      _toast('定位还没拿到', isError: true);
    }
  }

  // ══ 地图 ══════════════════════════════════════════════════════════

  MapScene _scene() {
    final List<MapPoint> points = <MapPoint>[
      for (final RoamHangoutItem item in _items)
        if (item.latitude != null && item.longitude != null)
          MapPoint(
            id: '${item.kind}-${item.id}',
            latitude: item.latitude!,
            longitude: item.longitude!,
            title: item.label,
            subtitle: item.isHangout
                ? '${item.memberCount} 人 · ${roamFmtKm(item.distance)}'
                : (item.isTopic ? '主题' : '限时活动'),
            state: item.isMember
                ? MapPointState.active
                : (item.full ? MapPointState.done : MapPointState.normal),
          ),
      // ⚠️ 附近的人**不画到这张图上** —— 小程序原话:「服务端已经把坐标截断过,
      //   这里不再画到地图上 —— 组局图上的针是局,不是人。」人只在
      //   「附近的人」那张列表里出现(explorePct/shops 那几样,不带坐标)。
      //   这条是可见性口径,不是皮肤,App 侧一条都不放宽。
    ];
    return MapScene.build(points: points, userLocation: _me);
  }

  void _onMarkerTap(MapPoint point) {
    final String id = point.id;
    final int? itemId = int.tryParse(
      id.replaceAll(RegExp(r'^(hangout|topic|activity)-'), ''),
    );
    final RoamHangoutItem? item = itemId == null
        ? null
        : _items.where((RoamHangoutItem it) => it.id == itemId).firstOrNull;
    if (item == null) return;
    if (item.isActivity) {
      context.push('/activity/${item.id}');
      return;
    }
    if (item.isTopic) {
      unawaited(_openTopicSheet(item));
      return;
    }
    unawaited(_openCard(item.id));
  }

  // ══ 半屏 ═══════════════════════════════════════════════════════════

  Future<T?> _sheet<T>(
    Widget Function(BuildContext context, ScrollController controller) builder,
  ) {
    return showCupertinoSheet<T>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (BuildContext context, ScrollController controller) =>
          builder(context, controller),
    );
  }

  List<RoamHangoutItem> get _myHangouts => _items
      .where(
        (RoamHangoutItem it) => it.isHangout && (it.isMember || it.isOwner),
      )
      .toList();

  Future<void> _openToolsSheet() {
    final int mine = _myHangouts.length;
    final ({String title, String sub, String primary, bool expand}) empty =
        roamEmptyStateCopy(
          radiusM: _radius,
          suggestedRadius: _suggestedRadius,
          suggestedCount: _suggestedCount,
        );
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _row(
            title: '筛选',
            sub: _items.isNotEmpty
                ? '${_items.length} 个 · ${roamFmtKm(_radius)}内'
                : '这一片还没有局',
            onTap: () {
              Navigator.of(context).pop();
              unawaited(_openListSheet(mineOnly: false));
            },
          ),
          _row(
            title: '我的局',
            sub: mine > 0 ? '已加入 $mine 个' : '还没加入过',
            onTap: () {
              Navigator.of(context).pop();
              unawaited(_openListSheet(mineOnly: true));
            },
          ),
          _row(
            title: '附近的人',
            sub: _runners.isNotEmpty ? '${_runners.length} 人在这片' : '这会儿没人在走',
            onTap: () {
              Navigator.of(context).pop();
              unawaited(_openRunnersListSheet());
            },
          ),
          _row(
            title: '我的队伍',
            sub: mine == 1
                ? '${_myHangouts.first.label} · ${_myHangouts.first.memberCount} 人'
                : (mine > 0 ? '$mine 个局在身上' : '还没加入哪一局'),
            onTap: () {
              Navigator.of(context).pop();
              final List<RoamHangoutItem> rows = _myHangouts;
              if (rows.length == 1) {
                unawaited(_openCard(rows.first.id));
              } else {
                unawaited(_openListSheet(mineOnly: true));
              }
            },
          ),
          _row(
            title: '设置',
            sub: '动态效果、位置权限',
            onTap: () {
              Navigator.of(context).pop();
              context.push('/settings');
            },
          ),
          if (_loaded && !_loadError && _items.isEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              child: Text(
                empty.sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CyPalette.of(context).textSecondary,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
            ),
            const SizedBox(height: CyTokens.space2),
            _primaryButton(
              label: empty.primary,
              onPressed: () {
                Navigator.of(context).pop();
                if (empty.expand && !_expandUsed) {
                  _expandUsed = true;
                  _radius = (_suggestedRadius ?? _defaultRadius).clamp(
                    _defaultRadius,
                    20000,
                  );
                  unawaited(_load());
                } else {
                  unawaited(_openCreateSheet());
                }
              },
            ),
            const SizedBox(height: CyTokens.space1),
            _ghostButton(
              label: '在这里开一局',
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_openCreateSheet());
              },
            ),
          ],
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openListSheet({required bool mineOnly}) {
    final List<RoamHangoutItem> rows = mineOnly
        ? _myHangouts
        : _items.where((RoamHangoutItem it) => !it.isActivity).toList();
    final String title = mineOnly ? '我的局' : '附近';
    final String sub = mineOnly
        ? '${rows.length} 个 · 已加入或我开的'
        : '${_items.length} 个局 · ${roamFmtKm(_radius)} 内 · 按距离';
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader(title, sub),
          for (final RoamHangoutItem item in rows)
            _row(
              leading: _itemLeading(item),
              title: _itemLabel(item),
              sub: _itemSub(item),
              chip: _itemChip(item),
              meta: item.isHangout
                  ? '${item.memberCount} 人'
                  : (item.isTopic ? '主题' : '活动'),
              onTap: () {
                Navigator.of(context).pop();
                if (item.isActivity) {
                  context.push('/activity/${item.id}');
                } else if (item.isTopic) {
                  unawaited(_openTopicSheet(item));
                } else {
                  unawaited(_openCard(item.id));
                }
              },
            ),
          const SizedBox(height: CyTokens.space3),
          _primaryButton(
            label: '开一局',
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_openCreateSheet());
            },
          ),
          const SizedBox(height: CyTokens.space1),
          _footText('免费 · 进群即加入'),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_openPlacesSheet());
            },
            child: const Text('看看别人打过卡的地方'),
          ),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openRunnersListSheet() {
    final String sub = _runners.isNotEmpty
        ? '${_runners.length} 人在这片 · 3 km 内'
        : '这会儿没人在走';
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader('附近的人', sub),
          for (final RoamRunner runner in _runners)
            _row(
              leading: CyAvatar(
                url: runner.avatar,
                fallback: runner.nickname,
                size: 40,
              ),
              title: runner.nickname,
              sub: roamSinceLabel(runner.elapsedSec),
              meta: roamElapsedLabel(runner.elapsedSec),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_openRunnerSheet(runner));
              },
            ),
          const SizedBox(height: CyTokens.space2),
          _footText('只显示这会儿正在走的人,走远了就不在这儿了'),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openRunnerSheet(RoamRunner runner) {
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader(
            runner.nickname,
            '${roamSinceLabel(runner.elapsedSec)} · ${roamElapsedLabel(runner.elapsedSec)}',
          ),
          _kvRow('地盘', '${runner.explorePct}%'),
          _kvRow('这一趟点亮的店', '${runner.shops} 家'),
          if (runner.shopPhotos.isNotEmpty) ...<Widget>[
            const SizedBox(height: CyTokens.space2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
              child: Row(
                children: <Widget>[
                  for (final RoamRunnerShopPhoto shop in runner.shopPhotos.take(
                    3,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(right: CyTokens.space2),
                      child: CyNetImage(
                        shop.image,
                        width: 72,
                        height: 72,
                        borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CyTokens.space2),
          _footText('位置已做模糊处理,只说明这一片有人在走'),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openPlacesSheet() {
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader(
            '别人打过卡的地方',
            _places.isNotEmpty
                ? '${_places.length} 处 · 公园、老门柱这类,不是商家'
                : '这一片还没有人打过卡',
          ),
          for (final RoamHangoutItem place in _places)
            _row(
              leading: CyAvatar(fallback: place.label, size: 40),
              title: place.label,
              sub: place.addressName ?? '不是商家',
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_openPlaceSheet(place));
              },
            ),
          const SizedBox(height: CyTokens.space2),
          _footText('这些是漫游里被点亮过的地方,走近了也能打卡'),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openPlaceSheet(RoamHangoutItem place) async {
    List<RoamShopVisitors> rows = const <RoamShopVisitors>[];
    try {
      rows = await ref
          .read(roamApiProvider)
          .shopVisitors(sourceType: 1, sourceIds: <int>[place.id]);
      if (!mounted) return;
    } catch (_) {
      // 拉不到就只显示名字 —— 头像是补充,不是这张卡的正事。
    }
    if (!mounted) return;
    final RoamShopVisitors? hit = rows
        .where((RoamShopVisitors r) => r.sourceId == place.id)
        .firstOrNull;
    final List<String> faces = hit?.avatars ?? const <String>[];
    final int total = hit?.total ?? 0;
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader(
            place.label,
            total > 0 ? '不是商家 · $total 个人在这儿打过卡' : '不是商家',
          ),
          if (faces.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.pageX,
                vertical: CyTokens.space2,
              ),
              child: Row(
                children: <Widget>[
                  for (final String face in faces.take(5))
                    Padding(
                      padding: const EdgeInsets.only(right: CyTokens.space1),
                      child: CyAvatar(url: face, size: 32),
                    ),
                ],
              ),
            ),
          if ((place.addressName ?? '').isNotEmpty)
            _kvRow('位置', place.addressName!),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openCard(int id) async {
    try {
      final RoamHangoutItem item = await ref
          .read(roamApiProvider)
          .hangoutDetail(id);
      if (!mounted) return;
      setState(() {
        _current = item;
        final double? lat = item.latitude;
        final double? lng = item.longitude;
        if (lat != null && lng != null) {
          _center = MapCoordinate(latitude: lat, longitude: lng);
        }
      });
      await _openCardSheet();
    } on RoamApiException catch (error) {
      _toast(error.message, isError: true);
    } catch (_) {
      _toast('这个局看不了', isError: true);
    }
  }

  Future<void> _openCardSheet() {
    final RoamHangoutItem? cur = _current;
    if (cur == null) return Future<void>.value();
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader(cur.label, _cardSubLine(cur)),
          if (cur.members.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.pageX,
                vertical: CyTokens.space2,
              ),
              child: Row(
                children: <Widget>[
                  for (final RoamHangoutMember member in cur.members.take(5))
                    Padding(
                      padding: const EdgeInsets.only(right: CyTokens.space1),
                      child: CyAvatar(
                        url: member.avatar,
                        fallback: member.nickname,
                        size: 32,
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.pageX,
              vertical: CyTokens.space1,
            ),
            child: Text(
              _membersText(cur),
              style: TextStyle(
                color: CyPalette.of(context).textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          if ((cur.isMember || cur.isOwner) &&
              cur.latitude != null &&
              cur.longitude != null)
            _primaryButton(
              label: '导航去集合点',
              onPressed: () => unawaited(_navToMeet(cur)),
            )
          else
            _primaryButton(
              label: cur.full && !cur.isMember ? '这局满了' : '加入这个局',
              loading: _joining,
              onPressed: cur.full && !cur.isMember
                  ? null
                  : () => unawaited(_join(cur)),
            ),
          const SizedBox(height: CyTokens.space1),
          _ghostButton(
            label: '看详情',
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(_openDetailSheet());
            },
          ),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  String _membersText(RoamHangoutItem cur) {
    final List<String> names = cur.members
        .take(3)
        .map((RoamHangoutMember m) => m.nickname)
        .where((String n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '还没人加入,你来第一个';
    final String tail = cur.members.length > 3
        ? ' 等 ${cur.memberCount >= cur.members.length ? cur.memberCount : cur.members.length} 人'
        : '';
    return '${names.join('、')}$tail 在群里'
        '${cur.isMerchantOwner ? ' · 商家承接,到店验证' : ''}';
  }

  String _cardSubLine(RoamHangoutItem cur) {
    final ({String label, String hm, String short}) when = roamWhenParts(
      cur.isHangout ? cur.startAt : (cur.startAt ?? cur.startDate),
    );
    final String address = (cur.addressName ?? '').isEmpty
        ? ''
        : '${cur.addressName}集合';
    return <String>[
      when.short,
      address,
      roamFmtKm(cur.distance).toUpperCase(),
    ].where((String s) => s.isNotEmpty).join(' · ');
  }

  Future<void> _openDetailSheet() {
    final RoamHangoutItem? cur = _current;
    if (cur == null) return Future<void>.value();
    final ({String label, String hm, String short}) when = roamWhenParts(
      cur.isHangout ? cur.startAt : (cur.startAt ?? cur.startDate),
    );
    final ({String num, String unit}) dist = roamSplitDist(cur.distance);
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          if (cur.isMember || cur.isOwner)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.pageX,
                vertical: CyTokens.space2,
              ),
              child: CyTag(
                label:
                    '已加入${cur.memberCount > 0 ? ' · ${cur.memberCount} 人' : ''}',
                brand: true,
              ),
            )
          else if (cur.full)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.pageX,
                vertical: CyTokens.space2,
              ),
              child: const CyTag(label: '这局满了'),
            ),
          _sheetHeader(
            cur.label,
            '由 ${cur.ownerNickname ?? '发起人'} 发起 · '
            '${cur.isMerchantOwner ? '商家局' : '公开局'}',
          ),
          _kvRow('时间', when.short.isEmpty ? '常驻 · 不限时间' : when.short),
          if ((cur.addressName ?? '').isNotEmpty)
            _kvRow('集合', cur.addressName!),
          if ((cur.description ?? '').isNotEmpty)
            _kvRow('说明', cur.description!),
          _kvRow('距离', dist.num.isEmpty ? '--' : '${dist.num}${dist.unit}'),
          _kvRow('人数', _membersText(cur)),
          if (cur.members.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CyTokens.pageX,
                vertical: CyTokens.space2,
              ),
              child: Row(
                children: <Widget>[
                  for (final RoamHangoutMember member in cur.members.take(5))
                    Padding(
                      padding: const EdgeInsets.only(right: CyTokens.space1),
                      child: CyAvatar(
                        url: member.avatar,
                        fallback: member.nickname,
                        size: 32,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: CyTokens.space2),
          if (cur.isOwner)
            _dangerButton(
              label: '关局',
              onPressed: () => unawaited(_danger(cur, close: true)),
            )
          else if (cur.isMember)
            _dangerButton(
              label: '退出',
              onPressed: () => unawaited(_danger(cur, close: false)),
            )
          else if (cur.reported)
            _footText('已举报')
          else
            CupertinoButton(
              minimumSize: const Size(44, 44),
              onPressed: () => unawaited(_openReportSheet()),
              child: const Text('举报'),
            ),
          if ((cur.isMember || cur.isOwner) &&
              cur.latitude != null &&
              cur.longitude != null)
            _primaryButton(
              label: '导航去集合点',
              onPressed: () => unawaited(_navToMeet(cur)),
            )
          else
            _primaryButton(
              label: cur.full && !cur.isMember ? '这局满了' : '加入这个局',
              loading: _joining,
              onPressed: cur.full && !cur.isMember
                  ? null
                  : () => unawaited(_join(cur)),
            ),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openTopicSheet(RoamHangoutItem topic) {
    final bool free = topic.productType == 2;
    final ({String num, String unit}) dist = roamSplitDist(topic.distance);
    final ({String label, String hm, String short}) when = roamWhenParts(
      topic.startAt ?? topic.startDate,
    );
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader(
            topic.label,
            <String>[
              when.short,
              topic.addressName ?? '',
            ].where((String s) => s.isNotEmpty).join(' · '),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CyTag(label: free ? '自由探索' : '城市定向', brand: free),
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            child: Text(
              topic.description ??
                  (free ? '不规定顺序、不要求一天跑完,只用一家也成立。' : '按顺序一站站走完。'),
              style: TextStyle(
                color: CyPalette.of(context).textSecondary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          _statsRow(<(String, String)>[
            ('${dist.num}${dist.unit}', '距离'),
            (free ? '不限顺序' : '按顺序', '玩法'),
            (topic.ownerNickname ?? '官方', '发布者'),
          ]),
          const SizedBox(height: CyTokens.space3),
          _primaryButton(
            label: '查看详情',
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/topic/${topic.id}');
            },
          ),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _openReportSheet() {
    const List<String> reasons = <String>['虚假信息', '骚扰 / 引流', '违法违规内容'];
    return _sheet<void>(
      (BuildContext context, ScrollController controller) => ListView(
        controller: controller,
        children: <Widget>[
          _sheetHeader('举报这个局', '举报会进人工审核,不会通知对方'),
          for (final String reason in reasons)
            _row(
              title: reason,
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_report(reason));
              },
            ),
          const SizedBox(height: CyTokens.space4),
        ],
      ),
    );
  }

  Future<void> _report(String reason) async {
    final RoamHangoutItem? cur = _current;
    if (cur == null) return;
    try {
      await ref.read(roamApiProvider).hangoutReport(id: cur.id, reason: reason);
      if (!mounted) return;
      setState(() => _current = _copyItem(cur, reported: true));
      // 成功不弹 toast:卡片上的「已举报」这一界面状态就是回执。
      await _openCardSheet();
    } on RoamApiException catch (error) {
      _toast(error.message, isError: true);
    } catch (_) {
      _toast('举报失败', isError: true);
    }
  }

  Future<void> _join(RoamHangoutItem cur) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final int conversationId = await ref
          .read(roamApiProvider)
          .hangoutJoin(cur.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      context.push(
        '/im/chat/$conversationId',
        extra: <String, String>{'name': cur.label},
      );
      unawaited(_load());
    } on RoamApiException catch (error) {
      _toast(error.message, isError: true);
    } catch (_) {
      _toast('进群失败', isError: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _danger(RoamHangoutItem cur, {required bool close}) async {
    final bool accepted = await cyConfirm(
      context,
      title: close ? '关掉「${cur.label}」?' : '退出「${cur.label}」?',
      content: close
          ? '关局后群聊一起关闭,所有人都不能再发言。此操作不可撤销。'
          : '群聊会从你的消息列表消失;局还开着的话,随时可以再加入。',
      confirmText: close ? '关局' : '退出这局',
      cancelText: close ? '再想想' : '继续待着',
      danger: close,
    );
    if (!accepted || !mounted) return;
    try {
      if (close) {
        await ref.read(roamApiProvider).hangoutClose(cur.id);
      } else {
        await ref.read(roamApiProvider).hangoutLeave(cur.id);
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
      await _load();
    } on RoamApiException catch (error) {
      _toast(error.message, isError: true);
    } catch (_) {
      _toast(close ? '关局失败' : '退出失败', isError: true);
    }
  }

  Future<void> _navToMeet(RoamHangoutItem cur) async {
    if (cur.latitude == null || cur.longitude == null) {
      _toast('这个局还没定碰头点');
      return;
    }
    final MapLaunchResult result = await launchNavigation(
      lat: cur.latitude!,
      lng: cur.longitude!,
      name: (cur.addressName ?? '').isNotEmpty ? cur.addressName! : cur.label,
      address: cur.addressName ?? '',
      isIOS: Platform.isIOS,
    );
    if (!mounted) return;
    final String message = mapLaunchMessage(result);
    if (message.isNotEmpty) _toast(message, isError: true);
  }

  Future<void> _openCreateSheet() async {
    // 开局要账号:游客在这里就地弹登录,别等填完表单提交才 401。
    if (!await requireLogin(context, ref) || !mounted) return;
    final bool? submitted = await _sheet<bool>(
      (BuildContext context, ScrollController controller) =>
          _HangoutCreateSheet(scrollController: controller),
    );
    if (submitted == true && mounted) unawaited(_load());
  }

  // ══ 小组件 ═════════════════════════════════════════════════════════

  Widget _sheetHeader(String title, String sub) => Padding(
    padding: const EdgeInsets.fromLTRB(
      CyTokens.pageX,
      CyTokens.space2,
      CyTokens.pageX,
      CyTokens.space2,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: CyPalette.of(context).textPrimary,
            fontSize: CyTokens.typeDisplay,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (sub.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space1),
          Text(
            sub,
            style: TextStyle(
              color: CyPalette.of(context).textSecondary,
              fontSize: CyTokens.typeLabel,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _row({
    Widget? leading,
    required String title,
    String? sub,
    String? chip,
    String? meta,
    VoidCallback? onTap,
  }) {
    final CyPalette palette = CyPalette.of(context);
    return CupertinoButton(
      minimumSize: const Size(44, 52),
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      onPressed: onTap,
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading,
            const SizedBox(width: CyTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: CyTokens.typeCardTitle,
                  ),
                ),
                if (sub != null && sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: CyTokens.typeLabel,
                    ),
                  ),
              ],
            ),
          ),
          if (chip != null && chip.isNotEmpty) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            CyTag(label: chip),
          ],
          if (meta != null && meta.isNotEmpty) ...<Widget>[
            const SizedBox(width: CyTokens.space2),
            Text(
              meta,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ],
          Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: palette.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _itemLeading(RoamHangoutItem item) {
    final String? pic = item.isHangout
        ? (item.coverUrl ?? item.ownerAvatar)
        : item.picUrl;
    return CyAvatar(
      url: pic,
      fallback: item.label.isEmpty ? '局' : item.label,
      size: 40,
    );
  }

  String _itemLabel(RoamHangoutItem item) =>
      item.label.isEmpty ? '未命名' : item.label;

  String _itemSub(RoamHangoutItem item) {
    final ({String label, String hm, String short}) when = roamWhenParts(
      item.isHangout ? item.startAt : (item.startAt ?? item.startDate),
    );
    final String km = roamFmtKm(item.distance);
    if (item.isHangout) {
      return <String>[
        when.short,
        item.addressName ?? '',
        km,
      ].where((String s) => s.isNotEmpty).join(' · ');
    }
    if (item.isTopic) {
      final String owner = (item.ownerNickname ?? '').isEmpty
          ? ''
          : '${item.isMerchantOwner ? '商家 ' : ''}${item.ownerNickname} 发布';
      return <String>[
        owner,
        item.addressName ?? '',
        km,
      ].where((String s) => s.isNotEmpty).join(' · ');
    }
    return <String>[
      '活动',
      item.addressName ?? '',
      km,
    ].where((String s) => s.isNotEmpty).join(' · ');
  }

  String _itemChip(RoamHangoutItem item) {
    if (item.isMember) return '已加入';
    if (item.full) return '满';
    if (item.isActivity) return '限时';
    if (item.isTopic) return item.productType == 2 ? '自由探索' : '城市定向';
    return item.isMerchantOwner ? '商家局' : '';
  }

  Widget _kvRow(String key, String value) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.pageX,
        vertical: CyTokens.space1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              key,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(List<(String, String)> stats) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: Row(
        children: <Widget>[
          for (final (String value, String label) in stats)
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    value,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: CyTokens.typeCardTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: CyTokens.typeMicro,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    VoidCallback? onPressed,
    bool loading = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: SizedBox(
        height: CyTokens.btnH,
        child: CyNativeButton(
          label: label,
          onPressed: onPressed,
          loading: loading,
        ),
      ),
    );
  }

  Widget _ghostButton({required String label, VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: SizedBox(
        height: CyTokens.btnH,
        width: double.infinity,
        child: CupertinoButton(
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }

  Widget _dangerButton({required String label, VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
      child: CupertinoButton(
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(color: CyTokens.statusDanger),
        ),
      ),
    );
  }

  Widget _footText(String text) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: CyTokens.pageX,
      vertical: CyTokens.space1,
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: CyPalette.of(context).textSecondary,
        fontSize: CyTokens.typeLabel,
      ),
    ),
  );

  RoamHangoutItem _copyItem(RoamHangoutItem item, {bool? reported}) {
    return RoamHangoutItem(
      kind: item.kind,
      id: item.id,
      title: item.title,
      name: item.name,
      description: item.description,
      coverUrl: item.coverUrl,
      picUrl: item.picUrl,
      ownerId: item.ownerId,
      ownerAvatar: item.ownerAvatar,
      ownerNickname: item.ownerNickname,
      ownerRole: item.ownerRole,
      full: item.full,
      latitude: item.latitude,
      longitude: item.longitude,
      addressName: item.addressName,
      startAt: item.startAt,
      startDate: item.startDate,
      status: item.status,
      memberCount: item.memberCount,
      isMember: item.isMember,
      isOwner: item.isOwner,
      distance: item.distance,
      conversationId: item.conversationId,
      productType: item.productType,
      members: item.members,
      reported: reported ?? item.reported,
    );
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool guest = !ref.watch(authControllerProvider).isLoggedIn;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('附近的局'),
        // ★ 深链直达时栈底就是本页:没有返回钮、不在 Tab Bar 五页里,
        //   边缘右滑是唯一出口(B1 二轮报告 N2)。照小程序 merchant/profile
        //   的口径「回首页恒在,返回按栈深出」——无栈时 leading 给回首页。
        automaticallyImplyLeading: false,
        // ⚠️ 判「有没有栈」要用 ModalRoute 自己的 canPop,不是 Navigator 的:
        //   页上叠了半屏 sheet 时 Navigator.canPop 为真,但本页仍是栈底,
        //   这时渲染系统返回钮直接触发框架断言(它只允许在可弹栈的路由上建)。
        leading: (ModalRoute.of(context)?.canPop ?? false)
            ? const CupertinoNavigationBarBackButton()
            : GoRouter.maybeOf(context) == null
            ? null
            : CupertinoButton(
                key: const Key('hangout-home-exit'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.space2,
                ),
                onPressed: () => GoRouter.of(context).go(kHomeRoute),
                child: const Text('回首页'),
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            AppleSceneView(
              scene: _scene(),
              onPointTap: _onMarkerTap,
              onCenterChanged: (MapCoordinate center) => _center = center,
            ),
            Positioned(
              left: CyTokens.pageX,
              right: CyTokens.pageX,
              top: CyTokens.space3,
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CyTokens.space3,
                      vertical: CyTokens.space1,
                    ),
                    decoration: BoxDecoration(
                      color: CyTokens.bgGlass,
                      borderRadius: BorderRadius.circular(CyTokens.radiusPill),
                      border: Border.all(color: palette.borderSubtle),
                    ),
                    child: Text(
                      // 首拉没回来前不许说「0 个局」—— 那是把 loading 报成 empty。
                      '附近 · ${_loaded ? '${_items.length} 个局' : '读取中…'} · ${roamFmtKm(_radius)}',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: CyTokens.typeLabel,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 纯图标钮必须有名字,不写 VoiceOver 只念「按钮」(§9.4-10)。
                  // 层级同 coop 结算页返回钮:动作留在按钮上,只摘图标的语义。
                  Semantics(
                    label: '回到我的位置',
                    button: true,
                    child: CupertinoButton(
                      key: const Key('hangout-recenter'),
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      onPressed: () => unawaited(_recenter()),
                      child: ExcludeSemantics(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: CyTokens.bgGlass,
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.borderSubtle),
                          ),
                          child: Icon(
                            CupertinoIcons.location_fill,
                            size: 20,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loadError && _items.isEmpty)
              Positioned(
                left: CyTokens.pageX,
                right: CyTokens.pageX,
                top: CyTokens.space3 + 52,
                child: Container(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  decoration: BoxDecoration(
                    color: CyTokens.bgGlass,
                    borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                    border: Border.all(color: palette.borderSubtle),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          guest
                              ? '登录后查看附近的局\n地图还能用,登录完列表就回来'
                              : '附近的局没能打开\n地图还在,列表这次没读到',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: CyTokens.typeLabel,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        onPressed: () =>
                            unawaited(guest ? _loginThenLoad() : _load()),
                        child: Text(guest ? '去登录' : '重试'),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom:
                  MediaQuery.viewPaddingOf(context).bottom + CyTokens.space2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Semantics(
                    button: true,
                    label: '展开附近的局与工具',
                    child: CupertinoButton(
                      key: const Key('hangout-tools-grab'),
                      minimumSize: const Size(88, 44),
                      padding: EdgeInsets.zero,
                      onPressed: () => unawaited(_openToolsSheet()),
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: palette.borderStrong,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: CyTokens.space2),
                  CupertinoButton(
                    key: const Key('hangout-stamp-camera'),
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => context.push('/roam/citystamp'),
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: palette.bgElevated,
                            shape: BoxShape.circle,
                            border: Border.all(color: palette.borderSubtle),
                          ),
                          child: Icon(
                            CupertinoIcons.camera_fill,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: CyTokens.space1),
                        Text(
                          '拍照',
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: CyTokens.typeMicro,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 开一局表单(独立 StatefulWidget:它活在 sheet 自己的路由里,
/// 页面的 setState 刷不到它 —— 表单状态必须自带)。
class _HangoutCreateSheet extends ConsumerStatefulWidget {
  const _HangoutCreateSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  ConsumerState<_HangoutCreateSheet> createState() =>
      _HangoutCreateSheetState();
}

class _HangoutCreateSheetState extends ConsumerState<_HangoutCreateSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();

  double? _lat;
  double? _lng;
  String _addressName = '';
  String _coverUrl = '';
  String _startAt = '';
  String _error = '';
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickPlace() async {
    final ({String name, double latitude, double longitude})? result =
        await context.push<({String name, double latitude, double longitude})>(
          '/publish/poi',
        );
    if (!mounted || result == null) return;
    setState(() {
      _lat = result.latitude;
      _lng = result.longitude;
      _addressName = result.name;
      _error = '';
    });
  }

  Future<void> _pickStartAt() async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: now,
      minimumDate: DateTime(now.year, now.month, now.day),
      maximumDate: now.add(const Duration(days: 365)),
      title: '哪天',
    );
    if (!mounted || date == null) return;
    final DateTime? time = await showCySystemDatePicker(
      context: context,
      mode: CupertinoDatePickerMode.time,
      initialDateTime: DateTime(date.year, date.month, date.day, 20),
      minimumDate: DateTime(date.year),
      maximumDate: DateTime(date.year + 1),
      title: '几点',
    );
    if (!mounted) return;
    final DateTime chosen =
        time ?? DateTime(date.year, date.month, date.day, 20);
    setState(() {
      _startAt =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')} '
          '${chosen.hour.toString().padLeft(2, '0')}:'
          '${chosen.minute.toString().padLeft(2, '0')}';
      _error = '';
    });
  }

  Future<void> _pickCover() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (file == null || !mounted) return;
    setState(() => _error = '');
    try {
      final String url = await ref
          .read(publishApiProvider)
          .uploadImage(file.path);
      if (!mounted) return;
      setState(() => _coverUrl = url);
    } catch (_) {
      if (mounted) setState(() => _error = '封面没传上去,可以稍后再补');
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final String? error = validateRoamHangoutForm(
      title: _title.text,
      description: _description.text,
      lat: _lat,
      lng: _lng,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      final RoamHangoutCreated created = await ref
          .read(roamApiProvider)
          .hangoutCreate(
            title: _title.text,
            description: _description.text,
            coverUrl: _coverUrl,
            latitude: _lat!,
            longitude: _lng!,
            addressName: _addressName,
            startAt: _startAt,
          );
      if (!mounted) return;
      CyNativeNotice.show(context, '开局了,进群里说一句吧');
      context.push(
        '/im/chat/${created.conversationId}',
        extra: <String, String>{'name': _title.text.trim()},
      );
      Navigator.of(context).pop(true);
    } on RoamApiException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } catch (_) {
      if (mounted) setState(() => _error = '开局失败,请重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return ListView(
      controller: widget.scrollController,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CyTokens.pageX,
            CyTokens.space2,
            CyTokens.pageX,
            CyTokens.space2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '开一局',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: CyTokens.typeDisplay,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '免费 · 进群即加入',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: CyTokens.typeLabel,
                ),
              ),
            ],
          ),
        ),
        _FieldRow(
          label: '想做什么',
          child: CupertinoTextField(
            key: const Key('hangout-create-title'),
            controller: _title,
            placeholder: '打 UNO 找搭子',
            maxLength: kHangoutTitleMax,
            textAlign: TextAlign.right,
            onChanged: (_) => setState(() => _error = ''),
          ),
        ),
        _FieldRow(
          label: '在哪碰头',
          value: _addressName.isEmpty ? '选一个点' : _addressName,
          placeholder: _addressName.isEmpty,
          onTap: () => unawaited(_pickPlace()),
        ),
        _FieldRow(
          label: '什么时候',
          value: _startAt.isEmpty ? '可选 · 不填就是常驻局' : _startAt,
          placeholder: _startAt.isEmpty,
          onTap: () => unawaited(_pickStartAt()),
        ),
        if (_startAt.isNotEmpty)
          _FieldRow(
            label: '不定时间',
            value: '清掉时间',
            placeholder: true,
            onTap: () => setState(() => _startAt = ''),
          ),
        _FieldRow(
          label: '封面',
          value: _coverUrl.isEmpty ? '可选' : '已选一张',
          placeholder: _coverUrl.isEmpty,
          onTap: () => unawaited(_pickCover()),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space2,
          ),
          child: CupertinoTextField(
            controller: _description,
            placeholder: '带什么 / 人数 / 费用 AA 之类,可选',
            maxLines: 3,
            maxLength: kHangoutDescMax,
            onChanged: (_) => setState(() => _error = ''),
          ),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CyTokens.pageX,
              vertical: CyTokens.space1,
            ),
            child: Text(
              _error,
              style: const TextStyle(
                color: CyTokens.statusDanger,
                fontSize: CyTokens.typeLabel,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CyTokens.pageX,
            vertical: CyTokens.space1,
          ),
          child: Text(
            '每人最多同时开 3 局 · 内容会经过审核',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: CyTokens.typeLabel,
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
          child: SizedBox(
            height: CyTokens.btnH,
            child: CyNativeButton(
              label: _submitting ? '正在开局…' : '开局',
              loading: _submitting,
              onPressed: _submitting ? null : () => unawaited(_submit()),
            ),
          ),
        ),
        const SizedBox(height: CyTokens.space4),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    this.value,
    this.placeholder = false,
    this.child,
    this.onTap,
  });

  final String label;
  final String? value;
  final bool placeholder;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CyTokens.pageX,
        vertical: CyTokens.space1,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: CyTokens.typeBody,
              ),
            ),
          ),
          Expanded(
            child:
                child ??
                CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  onPressed: onTap,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      value ?? '',
                      style: TextStyle(
                        color: placeholder
                            ? palette.textPlaceholder
                            : palette.textPrimary,
                        fontSize: CyTokens.typeBody,
                      ),
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
