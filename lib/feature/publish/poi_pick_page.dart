import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/map/apple_scene_view.dart';
import '../../core/map/map_scene.dart';
import '../../core/map/place_search.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_native_button.dart';
import '../../core/widgets/status_view.dart';

/// 选址页:替代小程序 `wx.choosePoi` / `wx.chooseLocation` 的 App 内选点。
///
/// ★ 2026-09-15(Task 1.3)由「点地图上的 POI」改为「搜索 + 地图确认」:
///   高德的 `onPoiTouched` 是它自己的 POI 图层能力,MapKit 没有对应回调
///   (`AppleMap` 只给经纬度),硬搬会退化成「随便点一个坐标、没有名字」。
///   MapKit 的等价能力是 `MKLocalSearch`(原生桥见 `core/map/place_search.dart`),
///   所以入口改成搜关键词 → 选结果 → 地图上确认位置。
///
/// 地址取原生 `placemark.title`,为空时以 POI 名兜底(节点表 address 非必填)。
/// 未选中任何地点时「确定」不可用 —— 不可用的动作禁用,不点下去撞空值。
///
/// 返回:`context.pop((name, latitude, longitude))`;取消返回 null。
class PoiPickPage extends StatefulWidget {
  const PoiPickPage({super.key, this.title = '选择地点'});

  final String title;

  @override
  State<PoiPickPage> createState() => _PoiPickPageState();
}

class _PoiPickPageState extends State<PoiPickPage> {
  final TextEditingController _query = TextEditingController();
  List<PlaceResult> _results = const <PlaceResult>[];
  PlaceResult? _selected;
  bool _searching = false;
  String? _error;
  bool _searched = false;

  /// 只认最后一次搜索的回包 —— 连着敲两次回车时,先回来的旧结果不许盖掉新的。
  int _seq = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final String query = raw.trim();
    if (query.isEmpty) return;
    final int seq = ++_seq;
    setState(() {
      _searching = true;
      _error = null;
      _selected = null;
    });
    try {
      final List<PlaceResult> found = await searchPlaces(
        query,
        near: MapScene.defaultCenter,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = found;
        _searching = false;
        _searched = true;
      });
    } on PlatformException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _searching = false;
        _searched = true;
        _results = const <PlaceResult>[];
        // ★ 说清**替代做法** —— 这一步是发布流程里的一环,
        //   只说"失败"会让人卡在这里不知道能不能继续。
        _error = '搜索失败,可以先跳过选点,发布后再补上地点。${e.message ?? ''}'.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ★★ 与 map_page 一致的降级(决策 D1:Android 暂不做地图)。
    //   **这页原来没有** —— 2026-08-19 补 golden 时撞出来:缺原生实现时地图控件
    //   返回无界尺寸,整页布局崩(BoxConstraints forces an infinite width)。
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return _PoiPickNativePage(
        title: widget.title,
        child: const StatusView(
          icon: CupertinoIcons.map,
          message: '地图暂时不可用',
          sub: '可以先跳过选点,发布后再补上地点',
          large: true,
        ),
      );
    }

    return _PoiPickNativePage(
      title: widget.title,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              CyTokens.pageX,
              CyTokens.space2,
              CyTokens.pageX,
              CyTokens.space2,
            ),
            child: CupertinoSearchTextField(
              controller: _query,
              placeholder: '搜索地点名称',
              onSubmitted: _search,
            ),
          ),
          Expanded(
            child: _selected == null ? _buildResults(context) : _buildMap(),
          ),
          _buildConfirmBar(context),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final CyPalette p = CyPalette.of(context);
    if (_searching) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_error != null) {
      return StatusView(
        icon: Icons.search_off_outlined,
        message: _error!,
        large: true,
      );
    }
    if (_results.isEmpty) {
      return StatusView(
        icon: CupertinoIcons.location,
        message: _searched ? '没搜到这个地点' : '搜索地点名称,再从结果里选一个',
        sub: _searched ? '换个关键词试试,或者先跳过选点' : null,
        large: true,
      );
    }
    return ListView(
      children: <Widget>[
        CupertinoListSection.insetGrouped(
          backgroundColor: p.bgSurface,
          decoration: BoxDecoration(
            color: p.bgElevated,
            borderRadius: BorderRadius.circular(CyTokens.radiusLg),
          ),
          separatorColor: p.borderSubtle,
          children: <Widget>[
            for (final PlaceResult place in _results)
              CupertinoListTile(
                title: Text(place.name),
                subtitle: place.address.isEmpty ? null : Text(place.address),
                onTap: () => setState(() => _selected = place),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMap() {
    final PlaceResult place = _selected!;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            container: true,
            label: '已选地点地图',
            hint: '重新搜索可以换一个地点',
            // AppleMap 的 initialCameraPosition 只在建控件时读一次,
            // 换选中点必须换 key 才会飞过去。
            child: KeyedSubtree(
              key: ValueKey<String>('${place.latitude},${place.longitude}'),
              child: AppleSceneView(
                scene: MapScene.build(
                  points: <MapPoint>[
                    MapPoint(
                      id: 'picked',
                      latitude: place.latitude,
                      longitude: place.longitude,
                      title: place.name,
                      subtitle: place.address.isEmpty ? null : place.address,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmBar(BuildContext context) {
    final PlaceResult? place = _selected;
    final CyPalette palette = CyPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        CyTokens.pageX,
        CyTokens.space2,
        CyTokens.pageX,
        CyTokens.space3,
      ),
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border(top: BorderSide(color: palette.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                liveRegion: place != null,
                label: place == null ? '尚未选择地点' : '已选择 ${place.name}',
                child: ExcludeSemantics(
                  child: Text(
                    place == null
                        ? '搜索并选择一个地点'
                        : '${place.name}\n'
                              '${place.latitude.toStringAsFixed(6)}, '
                              '${place.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: CyTokens.typeBody,
                      color: place == null
                          ? palette.textSecondary
                          : palette.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: CyTokens.space3),
            CyNativeButton(
              onPressed: place == null
                  ? null
                  : () {
                      context
                          .pop<
                            ({String name, double latitude, double longitude})
                          >((
                            name: place.name,
                            latitude: place.latitude,
                            longitude: place.longitude,
                          ));
                    },
              label: '确定',
              width: 76,
            ),
          ],
        ),
      ),
    );
  }
}

class _PoiPickNativePage extends StatelessWidget {
  const _PoiPickNativePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: Colors.transparent,
        automaticBackgroundVisibility: false,
        border: null,
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? const CupertinoNavigationBarBackButton()
            : GoRouter.maybeOf(context) == null
            ? null
            : Semantics(
                button: true,
                label: '取消选点，返回发布',
                child: ExcludeSemantics(
                  child: CupertinoButton(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    onPressed: () => context.go('/publish'),
                    child: const Icon(CupertinoIcons.xmark),
                  ),
                ),
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(bottom: false, child: child),
      ),
    );
  }
}
