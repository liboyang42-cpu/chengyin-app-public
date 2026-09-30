import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_scene.dart';
import '../../core/network/login_required.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/widgets/cy_search_field.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/activity.dart';
import '../../data/models/city_node_poi.dart';
import '../auth/login_gate.dart';
import '../map/map_controller.dart';
import 'search_controller.dart';
import 'search_filter_sheet.dart';

String searchMapLocation({String keyword = '', int? categoryId}) {
  final Map<String, String> query = <String, String>{
    if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    if (categoryId != null) 'categoryId': '$categoryId',
  };
  return Uri(
    path: '/search/map',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

class CityNodeSearchPage extends ConsumerStatefulWidget {
  const CityNodeSearchPage({
    super.key,
    this.initialKeyword = '',
    this.categoryId,
  });

  final String initialKeyword;
  final int? categoryId;

  @override
  ConsumerState<CityNodeSearchPage> createState() => _CityNodeSearchPageState();
}

class _CityNodeSearchPageState extends ConsumerState<CityNodeSearchPage> {
  late String _keyword;
  String _merchantTag = '';
  String _merchantCityRole = '';
  bool _locationRequested = false;
  MapCoordinate? _center;

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword;
  }

  CityNodeSearchQuery get _query {
    final SearchFilter filter = ref.read(searchFilterProvider);
    return CityNodeSearchQuery(
      keyword: _keyword.trim(),
      categoryId: filter.categoryId ?? widget.categoryId,
      tag: _merchantTag.isEmpty ? null : _merchantTag,
      cityRole: _merchantCityRole.isEmpty ? null : _merchantCityRole,
      center: _center,
      sortType: filter.sortType ?? 1,
      minPrice: filter.minPrice,
      maxPrice: filter.maxPrice,
      dateRange: filter.dateRange,
    );
  }

  void _searchAt(MapCoordinate center) {
    setState(() => _center = center);
  }

  void _search(String value) {
    setState(() {
      _keyword = value;
      _locationRequested = true;
    });
    ref.invalidate(cityNodeSearchProvider(_query));
  }

  Future<void> _openFilter() => showSearchFilterSheet(
    context,
    ref,
    initialMerchantTag: _merchantTag,
    initialMerchantCityRole: _merchantCityRole,
    onMerchantFieldsChanged: (String tag, String cityRole) {
      if (!mounted) return;
      setState(() {
        _merchantTag = tag;
        _merchantCityRole = cityRole;
      });
    },
    onSearch: () {
      if (!mounted) return;
      setState(() => _locationRequested = true);
      ref.invalidate(cityNodeSearchProvider(_query));
    },
  );

  @override
  Widget build(BuildContext context) {
    // 用户按下「使用当前位置搜索」前不打接口,也不看它(搜索页不静默要定位)。
    final AsyncValue<CityNodeSearchResult>? async = _locationRequested
        ? ref.watch(cityNodeSearchProvider(_query))
        : null;
    final CityNodeSearchResult? result = async?.value;

    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(middle: Text('城市节点搜索')),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(CyTokens.pageX),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: CySearchField(
                            value: _keyword,
                            placeholder: '搜索路线、地点等',
                            onChanged: (value) => _keyword = value,
                            onSubmitted: _search,
                          ),
                        ),
                        const SizedBox(width: CyTokens.space2),
                        CyNativeButton(
                          key: const Key('search-map-filter'),
                          role: CyNativeButtonRole.secondary,
                          label: '筛选',
                          onPressed: _openFilter,
                          icon: const CyNativeButtonIcon(
                            sfSymbol: 'line.3.horizontal.decrease',
                            fallback: CupertinoIcons.slider_horizontal_3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CyTokens.space3),
                    const CySectionTitle('地图图层说明'),
                    const SizedBox(height: CyTokens.space2),
                    _legend(result),
                  ],
                ),
              ),
              Expanded(child: _results(async)),
            ],
          ),
        ),
      ),
    );
  }

  /// 图层图例。商家节点这一路单独失败时按小程序文案变成「商家节点 · 未更新」。
  Widget _legend(CityNodeSearchResult? result) {
    final bool nodesFailed = result?.merchantNodesFailure != null;
    final CyPalette palette = CyPalette.of(context);
    return Wrap(
      spacing: CyTokens.space2,
      runSpacing: CyTokens.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const CyTag(label: '活动'),
        CyTag(label: nodesFailed ? '商家节点 · 未更新' : '商家节点'),
        const CyTag(label: '关联主题路线'),
        const CyTag(label: '探索标签'),
        // 入口是 #262 拍板补的;外观层收进图例同一档胶囊 + 系统 chevron,
        // 不再是一行游离的大字文本(看起来像第二个标题)。命中区仍 ≥44pt。
        CupertinoButton(
          onPressed: () => context.push('/merchant/discover'),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: CyTokens.space1),
          child: Container(
            height: 22, // 与 CyTag 同档
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.space2_5),
            decoration: BoxDecoration(
              color: palette.bgSubtle,
              borderRadius: BorderRadius.circular(CyTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '商家发现',
                  style: CyType.caption1.copyWith(
                    height: 22 / 12,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(width: CyTokens.space1),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 11,
                  color: palette.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _results(AsyncValue<CityNodeSearchResult>? async) {
    if (async == null) {
      final CyPalette palette = CyPalette.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(CyTokens.pageX),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 定位用途说明:footnote 次级小字(iOS 合规说明的取位),
              // 裸 Text 会落到 17pt 主文本档,读起来像标题。
              Text(
                '用于搜索当前位置附近的城市节点；经纬度只随本次请求发送，不会保存。',
                textAlign: TextAlign.center,
                style: CyType.footnote.copyWith(color: palette.textSecondary),
              ),
              const SizedBox(height: CyTokens.space3),
              CupertinoButton(
                minimumSize: const Size(44, CyTokens.btnH),
                padding: const EdgeInsets.symmetric(
                  horizontal: CyTokens.btnPadX,
                ),
                color: palette.actionPrimaryBg,
                foregroundColor: palette.actionPrimaryFg,
                borderRadius: BorderRadius.circular(CyTokens.radiusLg),
                onPressed: () => setState(() => _locationRequested = true),
                child: const Text(
                  '使用当前位置搜索',
                  style: TextStyle(
                    fontSize: CyTokens.typeCardTitle,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ★ 地图常驻(对齐小程序 searchmap 的全屏 <map>):加载/出错时地图不消失,
    //   状态只在地图上方/下方加浮层。此前地图块长在 data 分支里,
    //   任何一路失败 data 到不了 → 地图页从头到尾没有一张地图。
    final CityNodeSearchResult? result = async.value;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              AppleSceneView(
                scene:
                    result?.scene ?? MapScene.build(points: const <MapPoint>[]),
                onPointTap: result == null
                    ? null
                    : (MapPoint point) => _showPoint(result, point),
                onCenterChanged: _searchAt,
              ),
              if (async.isLoading)
                const Center(child: CupertinoActivityIndicator()),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(),
            // 游客必撞这里:`/api/city/nodes` 不在后端匿名放行名单里,无 token 一律 401
            // (小程序不会撞上,因为那边人人被微信静默登录)。401 是**有意拒绝**,
            // 得给登录引导,不能画原始 DioException。
            error: (Object error, _) => isLoginRequiredError(error)
                ? StatusView(
                    key: const Key('city-node-login-required'),
                    icon: CupertinoIcons.lock,
                    message: '登录后搜索附近的城市节点',
                    sub: '这一步需要登录,登录完会自动回到这一页。',
                    retryLabel: '去登录',
                    onRetry: () async {
                      if (!await requireLogin(context, ref)) return;
                      ref.invalidate(cityNodeSearchProvider(_query));
                    },
                  )
                : StatusView(
                    message: '地图结果没加载出来',
                    sub: _mapErrorSub(error),
                    icon: error is MapLocationException
                        ? Icons.location_off_outlined
                        : Icons.cloud_off,
                    // 永久拒绝/系统定位关闭时「重试」是死路:再多次也不会弹授权。
                    // 与 route_preview_sheet 同一写法,能去设置就给「去设置」。
                    retryLabel: _canOpenSettings(error) ? '去设置' : '重试',
                    onRetry: () => _recover(error),
                  ),
            data: (CityNodeSearchResult data) => _resultList(data),
          ),
        ),
      ],
    );
  }

  Widget _resultList(CityNodeSearchResult result) {
    final Object? activitiesFailure = result.activitiesFailure;
    final Object? nodesFailure = result.merchantNodesFailure;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        // 游客必撞这里:`/api/city/nodes` 不在后端匿名放行名单里,无 token 一律 401
        // (小程序不会撞上,因为那边人人被微信静默登录)。401 是**有意拒绝**,
        // 得给登录引导,不能只把图例淡成「未更新」让人以为这带没商家。
        if (nodesFailure != null && isLoginRequiredError(nodesFailure))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              0,
            ),
            child: StatusView(
              key: const Key('city-node-login-required'),
              icon: CupertinoIcons.lock,
              message: '登录后搜索附近的城市节点',
              sub: '这一步需要登录,登录完会自动回到这一页。',
              retryLabel: '去登录',
              onRetry: () async {
                if (!await requireLogin(context, ref)) return;
                ref.invalidate(cityNodeSearchProvider(_query));
              },
            ),
          ),
        if (activitiesFailure != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              0,
            ),
            child: StatusView(
              message: '活动没能加载出来',
              sub: _mapErrorSub(activitiesFailure),
              icon: Icons.cloud_off,
              onRetry: () => ref.invalidate(cityNodeSearchProvider(_query)),
            ),
          )
        else if (result.totalCount > 0)
          // 空结果时不再顶一行「查看全部 0 个结果」,让位给空态。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space3,
              CyTokens.pageX,
              CyTokens.space2,
            ),
            child: Text(
              '查看全部 ${result.totalCount} 个结果',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        if (result.noCoordinateActivityCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              0,
              CyTokens.pageX,
              CyTokens.space2,
            ),
            child: Text(
              '${result.noCoordinateActivityCount} 个活动暂未提供位置，仅在列表中显示',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (result.totalCount == 0 && activitiesFailure == null)
          const SizedBox(
            height: 220,
            child: StatusView(
              message: '这一带还没有活动或商家节点',
              sub: '换个关键词，或拖动地图看看别处',
              icon: Icons.place_outlined,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: CyTokens.pageX),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (result.activities.isNotEmpty) ...<Widget>[
                  const CySectionTitle('活动'),
                  for (final Activity activity in result.activities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space2),
                      child: _ActivityCard(activity: activity),
                    ),
                ],
                if (result.nodes.isNotEmpty) ...<Widget>[
                  const CySectionTitle('商家节点'),
                  for (final CityNodePoi node in result.nodes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: CyTokens.space2),
                      child: _NodeCard(node: node),
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  bool _canOpenSettings(Object error) =>
      error is MapLocationException && error.canOpenSettings;

  Future<void> _recover(Object error) async {
    if (_canOpenSettings(error)) {
      await Geolocator.openAppSettings();
      if (!mounted) return;
      // 从设置回来后权限状态可能已变,重读定位而不是复用被缓存的失败。
      ref.invalidate(currentMapLocationProvider);
    }
    ref.invalidate(cityNodeSearchProvider(_query));
  }

  /// 用户可见的错误副文案。逐档对齐仓内既有写法(my_plays_page._errorSub):
  /// 定位失败本身就是人话;后端给了中文原话就用原话;只有 dio 英文栈才兜底。
  String _mapErrorSub(Object error) {
    if (error is MapLocationException) return error.message;
    if (error is DioException) {
      final Object? data = error.response?.data;
      final String msg = data is Map
          ? (data['msg']?.toString().trim() ?? '')
          : '';
      return msg.isEmpty ? '网络开了点小差' : msg;
    }
    return '网络开了点小差';
  }

  Future<void> _showPoint(CityNodeSearchResult result, MapPoint point) async {
    final Activity? activity = point.id.startsWith('activity-')
        ? result.activities
              .where((item) => item.id == int.tryParse(point.id.substring(9)))
              .firstOrNull
        : null;
    final CityNodePoi? node = point.nodeId == null
        ? null
        : result.nodes.where((item) => item.poiId == point.nodeId).firstOrNull;
    if (activity == null && node == null) return;
    await showCupertinoSheet<void>(
      context: context,
      showDragHandle: true,
      topGap: 0.55,
      scrollableBuilder:
          (BuildContext sheetContext, ScrollController scrollController) =>
              CupertinoPageScaffold(
                backgroundColor: CyTokens.bgPage,
                navigationBar: CupertinoNavigationBar(
                  middle: Text(activity?.name ?? node!.name),
                ),
                child: SafeArea(
                  top: false,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(CyTokens.pageX),
                    children: <Widget>[
                      CyNativeButton(
                        width: double.infinity,
                        label: activity == null ? '查看节点详情' : '查看活动详情',
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          context.push(
                            activity == null
                                ? '/roam/poi/${node!.poiId}'
                                : '/activity/${activity.id}',
                          );
                        },
                      ),
                      if ((activity?.topicId ?? 0) > 0) ...<Widget>[
                        const SizedBox(height: CyTokens.space2),
                        CyNativeButton(
                          width: double.infinity,
                          role: CyNativeButtonRole.secondary,
                          label: '查看关联主题',
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            context.push('/topic/${activity!.topicId}');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context) {
    return CyCell(
      title: activity.name,
      subtitle: <String>[
        if ((activity.addressName ?? activity.address ?? '').isNotEmpty)
          activity.addressName ?? activity.address!,
        if (!activity.hasCoordinates) '位置暂未提供',
        if ((activity.topicId ?? 0) > 0) '关联主题路线',
      ].join(' · '),
      onTap: () => context.push('/activity/${activity.id}'),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node});

  final CityNodePoi node;

  @override
  Widget build(BuildContext context) {
    return CyCell(
      title: node.name,
      subtitle: <String>[
        if ((node.templateTitle ?? '').isNotEmpty)
          '关联主题路线 · ${node.templateTitle}',
        if ((node.merchantName ?? '').isNotEmpty) node.merchantName!,
        if (node.distanceText != null) node.distanceText!,
      ].join(' · '),
      onTap: () => context.push('/roam/poi/${node.poiId}'),
    );
  }
}
