// 路线预览 Sheet + 导航中顶部指令条(决策 D7:App 独有,不 1:1 跟小程序)。
//
// 小程序对应能力只有 `wx.openLocation` 与节点直线连线;这里是 Apple 原生的
// 真实道路路线(MKDirections)+ App 内分步引导 + 「在地图中打开」。

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../../core/map/device_location.dart';
import '../../core/map/directions.dart';
import '../../core/map/map_launcher.dart';
import '../../core/map/map_scene.dart';
import '../../core/map/route_guidance.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_tabs.dart';
import '../../core/widgets/status_view.dart';

/// 预览里点了「开始导航」:带回路线,由宿主页挂 [RouteNavigationOverlay]。
class RouteNavigationRequest {
  const RouteNavigationRequest({
    required this.destination,
    required this.name,
    required this.mode,
    required this.route,
  });

  final MapCoordinate destination;
  final String name;
  final DirectionsMode mode;
  final DirectionsRoute route;
}

Future<RouteNavigationRequest?> showRoutePreviewSheet(
  BuildContext context, {
  required MapCoordinate destination,
  required String name,
  required DirectionsClient directions,
  required DeviceLocation location,
}) => showCupertinoSheet<RouteNavigationRequest>(
  context: context,
  showDragHandle: true,
  topGap: 0.12,
  scrollableBuilder: (BuildContext context, ScrollController controller) =>
      RoutePreviewSheet(
        destination: destination,
        name: name,
        directions: directions,
        location: location,
        scrollController: controller,
      ),
);

/// 「在地图中打开」:先交 Apple 地图,打不开再走 map_launcher 的兜底链(含复制地址)。
Future<void> openRouteInMaps(
  BuildContext context, {
  required DirectionsClient directions,
  required MapCoordinate destination,
  required String name,
  required DirectionsMode mode,
}) async {
  if (await directions.openInMaps(destination, name: name, mode: mode)) return;
  final MapLaunchResult result = await launchNavigation(
    lat: destination.latitude,
    lng: destination.longitude,
    name: name,
    isIOS: Platform.isIOS,
  );
  final String message = mapLaunchMessage(result);
  if (message.isNotEmpty && context.mounted) {
    CyNativeNotice.show(context, message);
  }
}

class RoutePreviewSheet extends StatefulWidget {
  const RoutePreviewSheet({
    super.key,
    required this.destination,
    required this.name,
    required this.directions,
    required this.location,
    this.scrollController,
  });

  final MapCoordinate destination;
  final String name;
  final DirectionsClient directions;
  final DeviceLocation location;
  final ScrollController? scrollController;

  @override
  State<RoutePreviewSheet> createState() => _RoutePreviewSheetState();
}

class _RoutePreviewSheetState extends State<RoutePreviewSheet> {
  DirectionsMode _mode = DirectionsMode.walking;
  MapCoordinate? _origin;
  DirectionsRoute? _route;
  Uint8List? _snapshot;
  LocationUnavailable? _failure;
  bool _planFailed = false;
  bool _badDestination = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    setState(() {
      _failure = null;
      _planFailed = false;
      _badDestination = false;
      _route = null;
      _snapshot = null;
    });
    // ★ 第二道 NaN 卫(b1-sim-small-domains P2-1):入口虽有 hasCoordinates
    //   挡着,上游脏数据/异常输入仍可能把 NaN 喂进来 —— 直线距离计算会
    //   「Infinity or NaN toInt」当场红屏。非法坐标走人话错误态,不进计算。
    if (!widget.destination.latitude.isFinite ||
        !widget.destination.longitude.isFinite) {
      setState(() => _badDestination = true);
      return;
    }
    try {
      _origin ??= await widget.location.current();
      final DirectionsRoute route = await widget.directions.directions(
        _origin!,
        widget.destination,
        mode: _mode,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _route = route);
      final Uint8List? snapshot = await widget.directions.snapshot(
        route,
        width: 343,
        height: 180,
        user: _origin,
        dark: CupertinoTheme.brightnessOf(context) == Brightness.dark,
      );
      if (mounted && generation == _generation) {
        setState(() => _snapshot = snapshot);
      }
    } on LocationUnavailable catch (failure) {
      if (mounted && generation == _generation) {
        setState(() => _failure = failure);
      }
    } catch (_) {
      // ★ 不属于「定位不可用」的失败原先**没有落点**:平台错、规划调用抛错都会
      //   让人永远停在「正在规划路线…」—— 没有错误、没有重试,只能退出去重进。
      //   给它和定位失败同形的一条出路。
      if (mounted && generation == _generation) {
        setState(() => _planFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final DirectionsRoute? route = _route;
    return ColoredBox(
      color: p.bgSurface,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(
          CyTokens.space4,
          CyTokens.space2,
          CyTokens.space4,
          CyTokens.space8,
        ),
        children: <Widget>[
          Text(
            widget.name,
            style: CyType.title3.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          CyTabs(
            variant: CyTabsVariant.segmented,
            tabs: <CyTab>[
              for (final DirectionsMode m in DirectionsMode.values)
                CyTab(key: m.name, label: m.label),
            ],
            active: _mode.name,
            onChanged: (String key) {
              final DirectionsMode next = DirectionsMode.values.byName(key);
              if (next == _mode) return;
              _mode = next;
              unawaited(_load());
            },
          ),
          const SizedBox(height: CyTokens.space4),
          if (_badDestination)
            StatusView(
              icon: CupertinoIcons.exclamationmark_triangle,
              message: '目的地坐标无效,没法规划路线',
              sub: '这个地点的位置数据不对',
            )
          else if (_failure != null)
            _LocationFailureBlock(
              failure: _failure!,
              onRetry: _load,
              onOpenSettings: () =>
                  widget.location.openSettings(_failure!.reason),
            )
          else if (_planFailed)
            StatusView(
              icon: CupertinoIcons.exclamationmark_triangle,
              message: '路线没能规划出来',
              sub: '重试会重新规划一次',
              onRetry: _load,
            )
          else if (route == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CyTokens.space6),
              child: Column(
                children: <Widget>[
                  const CupertinoActivityIndicator(),
                  const SizedBox(height: CyTokens.space2),
                  Text('正在规划路线…', style: TextStyle(color: p.textSecondary)),
                ],
              ),
            )
          else ...<Widget>[
            if (_snapshot != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                child: AspectRatio(
                  aspectRatio: 343 / 180,
                  child: Image.memory(_snapshot!, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: CyTokens.space3),
            _RouteSummary(route: route),
            if (route.notice != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Text(
                route.notice!,
                style: CyType.caption1.copyWith(color: p.statusWarning),
              ),
            ],
            const SizedBox(height: CyTokens.space4),
            Row(
              children: <Widget>[
                if (_mode != DirectionsMode.transit) ...<Widget>[
                  Expanded(
                    child: CyNativeButton(
                      label: '开始导航',
                      onPressed: () => Navigator.of(context).pop(
                        RouteNavigationRequest(
                          destination: widget.destination,
                          name: widget.name,
                          mode: _mode,
                          route: route,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: CyTokens.space3),
                ],
                Expanded(
                  child: CyNativeButton(
                    label: '在地图中打开',
                    role: CyNativeButtonRole.secondary,
                    onPressed: () => openRouteInMaps(
                      context,
                      directions: widget.directions,
                      destination: widget.destination,
                      name: widget.name,
                      mode: _mode,
                    ),
                  ),
                ),
              ],
            ),
            if (route.steps.isNotEmpty)
              CupertinoListSection.insetGrouped(
                margin: const EdgeInsets.only(top: CyTokens.space5),
                backgroundColor: p.bgSurface,
                decoration: BoxDecoration(
                  color: p.bgElevated,
                  borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                ),
                separatorColor: p.borderSubtle,
                header: Text('路线步骤', style: TextStyle(color: p.textSecondary)),
                children: <Widget>[
                  for (int i = 0; i < route.steps.length; i++)
                    CupertinoListTile(
                      leading: Text(
                        '${i + 1}',
                        style: TextStyle(color: p.textTertiary),
                      ),
                      title: Text(
                        route.steps[i].instruction,
                        maxLines: 2,
                        style: TextStyle(color: p.textPrimary),
                      ),
                      additionalInfo: Text(
                        formatRouteDistance(route.steps[i].distanceMeters),
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route});
  final DirectionsRoute route;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          route.eta == null ? '直线距离' : formatRouteEta(route.eta!),
          style: CyType.title1.copyWith(
            color: p.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: CyTokens.space2),
        Text(
          formatRouteDistance(route.distanceMeters),
          style: CyType.subhead.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}

class _LocationFailureBlock extends StatelessWidget {
  const _LocationFailureBlock({
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final LocationUnavailable failure;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return Column(
      children: <Widget>[
        const SizedBox(height: CyTokens.space4),
        Text(
          failure.title,
          style: CyType.headline.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: CyTokens.space2),
        Text(
          failure.message,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textSecondary),
        ),
        const SizedBox(height: CyTokens.space4),
        CyNativeButton(
          label: failure.canOpenSettings ? '去设置' : '重试',
          role: CyNativeButtonRole.secondary,
          onPressed: failure.canOpenSettings ? onOpenSettings : onRetry,
        ),
      ],
    );
  }
}

/// 导航中:顶部指令条 + 路线预览图。订阅位置流跑 [RouteGuidance],偏航自动重算。
class RouteNavigationOverlay extends StatefulWidget {
  const RouteNavigationOverlay({
    super.key,
    required this.request,
    required this.directions,
    required this.location,
    required this.onEnd,
  });

  final RouteNavigationRequest request;
  final DirectionsClient directions;
  final DeviceLocation location;
  final VoidCallback onEnd;

  @override
  State<RouteNavigationOverlay> createState() => _RouteNavigationOverlayState();
}

class _RouteNavigationOverlayState extends State<RouteNavigationOverlay> {
  late final RouteGuidance _guidance = RouteGuidance(widget.request.route);
  StreamSubscription<GuidanceState>? _subscription;
  GuidanceState? _state;
  MapCoordinate? _position;
  DirectionsRoute? _snapshotRoute;
  Uint8List? _snapshot;
  DateTime? _reroutedAt;

  @override
  void initState() {
    super.initState();
    _refreshSnapshot(widget.request.route);
    _subscription = _guidance
        .run(
          widget.location.watch().map((MapCoordinate c) => _position = c),
          reroute: (MapCoordinate from) => widget.directions.directions(
            from,
            widget.request.destination,
            mode: widget.request.mode,
          ),
        )
        .listen((GuidanceState state) {
          if (!mounted) return;
          if (state.rerouted) _reroutedAt = DateTime.now();
          if (!identical(state.route, _snapshotRoute)) {
            _refreshSnapshot(state.route);
          }
          setState(() => _state = state);
        });
  }

  Future<void> _refreshSnapshot(DirectionsRoute route) async {
    _snapshotRoute = route;
    final Uint8List? bytes = await widget.directions.snapshot(
      route,
      width: 343,
      height: 160,
      user: _position,
    );
    if (mounted && identical(route, _snapshotRoute)) {
      setState(() => _snapshot = bytes);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool justRerouted =
        _reroutedAt != null &&
        DateTime.now().difference(_reroutedAt!) < const Duration(seconds: 8);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(CyTokens.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RouteGuidanceBanner(
              state: _state,
              justRerouted: justRerouted,
              onEnd: widget.onEnd,
            ),
            if (_snapshot != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              ClipRRect(
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                child: AspectRatio(
                  aspectRatio: 343 / 160,
                  child: Image.memory(_snapshot!, fit: BoxFit.cover),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 导航指令条。[state] 为 null = 还在等第一次定位。
class RouteGuidanceBanner extends StatelessWidget {
  const RouteGuidanceBanner({
    super.key,
    required this.state,
    required this.onEnd,
    this.justRerouted = false,
  });

  final GuidanceState? state;
  final VoidCallback onEnd;
  final bool justRerouted;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    final GuidanceState? s = state;
    final String headline = s == null ? '正在获取你的位置…' : s.instruction;
    final String? lead = s == null || s.arrived
        ? null
        : '${formatRouteDistance(s.distanceToNextStepMeters)} 后';
    final String? detail = s == null
        ? null
        : s.rerouting
        ? '已偏离路线，正在重新规划…'
        : s.arrived
        ? null
        : <String>[
            '剩余 ${formatRouteDistance(s.remainingMeters)}',
            if (s.remainingTime != null)
              '约 ${formatRouteEta(s.remainingTime!)}',
            if (justRerouted) '已重新规划路线',
          ].join(' · ');
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          CyTokens.space4,
          CyTokens.space3,
          CyTokens.space2,
          CyTokens.space3,
        ),
        decoration: BoxDecoration(
          color: p.bgElevated,
          borderRadius: BorderRadius.circular(CyTokens.radiusXl),
          border: Border.all(color: p.borderStrong),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (lead != null)
                    Text(
                      lead,
                      style: CyType.caption1.copyWith(color: p.textSecondary),
                    ),
                  Text(
                    headline,
                    style: CyType.title3.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      style: CyType.caption1.copyWith(
                        color: s!.rerouting ? p.statusWarning : p.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: CyTokens.space3),
              onPressed: onEnd,
              child: Text(
                s?.arrived == true ? '完成' : '结束',
                style: TextStyle(color: p.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
