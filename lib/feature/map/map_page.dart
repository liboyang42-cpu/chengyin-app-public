import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/device_location.dart';
import '../../core/map/directions.dart';
import '../../core/map/map_launcher.dart';
import '../../core/map/map_scene.dart';
import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/nearby_node.dart';
import '../npc/npc_controller.dart';
import 'map_controller.dart';
import 'route_preview_sheet.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';

class MapPage extends ConsumerWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(mapPrivacyAgreementProvider);
    return CupertinoPageScaffold(
      child: consent.when(
        loading: () => const LoadingView(),
        // ★ 隐私门是进入地图域的第一道界面(现 initialLocation=/feed)。原先文案写着「请重试」
        //   却**没有给 onRetry** —— 用户会永久卡在一个叫他重试、又无处可点的界面上,
        //   只能杀进程重开。叫得动手,就得给得了手。
        error: (_, _) => StatusView(
          icon: CupertinoIcons.lock_shield,
          message: '没能读取隐私设置',
          onRetry: () => ref.invalidate(mapPrivacyAgreementProvider),
        ),
        data: (agreed) {
          if (agreed) {
            return _MapContent(ref: ref);
          }
          return _MapPrivacyGate(
            onAgree: () async {
              await ref.read(mapPrivacyStoreProvider).setAgreed(true);
              ref.invalidate(mapPrivacyAgreementProvider);
            },
          );
        },
      ),
    );
  }
}

class _MapPrivacyGate extends StatelessWidget {
  const _MapPrivacyGate({required this.onAgree});
  final Future<void> Function() onAgree;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(CyTokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ★ 用 textSecondary 而不是 nodeGlow(#00E5D4 青)。
          //   这是进入地图域的第一道界面,这个 52pt 图标是
          //   整屏最大的视觉元素 —— 用青色等于让用户对城瘾的第一印象是个青色 App,
          //   而城瘾是黑白系、品牌色就是文字色。
          //   nodeGlow 自己的定义里就写着「彩色只做点缀,不要拿来做按钮底或主色」,
          //   一屏之主的图标属于「主色」那一侧,不是点缀。
          //   参照:小程序对应的 components/cy/privacy-gate **根本没有图标**,
          //   整个组件只有 text-secondary 正文 + 下划线链接 + 白底按钮,零彩色。
          Icon(
            CupertinoIcons.map,
            size: 52,
            color: CyPalette.of(context).textSecondary,
          ),
          const SizedBox(height: 18),
          const CySectionTitle('启用城市地图'),
          const SizedBox(height: CyTokens.space3),
          Text(
            '地图由 Apple 地图提供。启用后将使用定位信息展示附近节点。',
            textAlign: TextAlign.center,
            style: CyType.body.copyWith(
              color: CyPalette.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: CyTokens.space5),
          CupertinoButton(
            minimumSize: const Size(44, CyTokens.btnH),
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.btnPadX),
            color: CyPalette.of(context).actionPrimaryBg,
            foregroundColor: CyPalette.of(context).actionPrimaryFg,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
            onPressed: onAgree,
            child: Text(
              '同意并启用地图',
              style: CyType.headline.copyWith(
                color: CyPalette.of(context).actionPrimaryFg,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MapContent extends StatefulWidget {
  const _MapContent({required this.ref});
  final WidgetRef ref;

  @override
  State<_MapContent> createState() => _MapContentState();
}

class _MapContentState extends State<_MapContent> {
  final DirectionsClient _directions = DirectionsClient();
  final DeviceLocation _location = DeviceLocation();
  RouteNavigationRequest? _navigation;

  WidgetRef get ref => widget.ref;

  Future<void> _openRoute(NearbyNode node) async {
    final RouteNavigationRequest? request = await showRoutePreviewSheet(
      context,
      destination: MapCoordinate(
        latitude: double.parse(node.latitude),
        longitude: double.parse(node.longitude),
      ),
      name: node.addressName.isEmpty ? '未命名节点' : node.addressName,
      directions: _directions,
      location: _location,
    );
    if (request != null && mounted) setState(() => _navigation = request);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      // ★ 决策 D1:Android 暂不做地图,
      //   整页降级并给替代去处;界面只说用户能懂的话。
      return const StatusView(
        icon: CupertinoIcons.map,
        message: '地图暂时不可用',
        sub: '可以先去「首页」看看正在进行的活动',
      );
    }
    final data = ref.watch(mapPageDataProvider);
    return data.when(
      loading: () => const LoadingView(),
      error: (error, _) => StatusView(
        icon: CupertinoIcons.location_slash,
        message: error is MapLocationException ? error.message : '地图没能加载出来',
        onRetry: () => ref.invalidate(mapPageDataProvider),
      ),
      data: (value) => Stack(
        children: <Widget>[
          Positioned.fill(child: AppleSceneView(scene: value.scene)),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Semantics(
                label: '打开定位设置',
                button: true,
                child: CupertinoButton(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.all(CyTokens.space2),
                  color: CyPalette.of(context).actionSecondaryBg,
                  borderRadius: BorderRadius.circular(CyTokens.radiusMd),
                  onPressed: () => Geolocator.openLocationSettings(),
                  child: const Icon(CupertinoIcons.location_fill, size: 20),
                ),
              ),
            ),
          ),
          if (value.city.resolved)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(CyTokens.space3),
                  child: CyTag(label: value.city.city),
                ),
              ),
            ),
          _NearbySheet(nodes: value.nodes, onRoute: _openRoute),
          if (_navigation != null)
            Align(
              alignment: Alignment.topCenter,
              child: RouteNavigationOverlay(
                key: ObjectKey(_navigation),
                request: _navigation!,
                directions: _directions,
                location: _location,
                onEnd: () => setState(() => _navigation = null),
              ),
            ),
          // 全局 NPC 入口浮层
          Consumer(
            builder: (context, ref, _) {
              final npcState = ref.watch(globalNpcProvider);
              if (npcState.profile == null) return const SizedBox.shrink();
              return Positioned(
                bottom: 80,
                right: 16,
                child: Semantics(
                  label: '${npcState.profile!.name}已陪伴本次漫游',
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(CyTokens.space3),
                      decoration: BoxDecoration(
                        color: CyPalette.of(
                          context,
                        ).bgElevated.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                        border: Border.all(
                          color: CyPalette.of(context).borderStrong,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.sparkles,
                            color: CyPalette.of(context).textPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: CyTokens.space1_5),
                          Text(
                            npcState.profile!.name,
                            style: CyType.caption1.copyWith(
                              color: CyPalette.of(context).textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NearbySheet extends StatelessWidget {
  const _NearbySheet({required this.nodes, required this.onRoute});
  final List<NearbyNode> nodes;
  final ValueChanged<NearbyNode> onRoute;

  @override
  Widget build(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.16,
      maxChildSize: 0.8,
      builder: (context, controller) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CyTokens.radiusXl),
        ),
        child: ColoredBox(
          color: p.bgSurface,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(CyTokens.space4),
            children: <Widget>[
              Text(
                nodes.isEmpty ? '附近暂无可玩节点' : '附近 ${nodes.length} 个节点',
                style: CyType.headline.copyWith(color: p.textPrimary),
              ),
              if (nodes.isNotEmpty)
                CupertinoListSection.insetGrouped(
                  margin: const EdgeInsets.only(top: CyTokens.space3),
                  backgroundColor: p.bgSurface,
                  separatorColor: p.borderSubtle,
                  decoration: BoxDecoration(
                    color: p.bgElevated,
                    borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                  ),
                  children: <Widget>[
                    for (final NearbyNode node in nodes)
                      CupertinoListTile(
                        padding: EdgeInsets.zero,
                        leading: Icon(
                          CupertinoIcons.location_fill,
                          size: 20,
                          color: p.textPrimary,
                        ),
                        title: Text(
                          node.addressName.isEmpty ? '未命名节点' : node.addressName,
                          style: CyType.body.copyWith(color: p.textPrimary),
                        ),
                        subtitle: node.address == null
                            ? null
                            : Text(
                                node.address!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CyType.subhead.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (node.distance != null)
                              Text(
                                node.distance! >= 1000
                                    ? '${(node.distance! / 1000).toStringAsFixed(1)} km'
                                    : '${node.distance!.round()} m',
                                style: CyType.subhead.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            // D7:真实道路路线 + 导航。没坐标的节点不给入口,别让按钮点了没反应。
                            if (hasCoordinates(
                              double.tryParse(node.latitude),
                              double.tryParse(node.longitude),
                            ))
                              CupertinoButton(
                                minimumSize: const Size(44, 44),
                                padding: const EdgeInsets.only(
                                  left: CyTokens.space3,
                                ),
                                onPressed: () => onRoute(node),
                                child: const Text('路线'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
