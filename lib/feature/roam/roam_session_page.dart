import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_confirm.dart';
import '../../core/widgets/status_view.dart';
import '../../core/widgets/cy_native_notice.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../data/models/roam_session.dart';
import 'roam_route_math.dart';
import 'roam_share_actions.dart';

/// 单次漫游回看(对齐小程序 `subpackageRoam/session`):
/// 读本地 roam_sessions 里指定 ts 的一条记录,画路线图 + 统计 + 点亮 POI。
///
/// ★ 三态分家(与小程序同源):
///   · 读不出/坏数据 → 「漫游记录读不出来」(记录还在,可重试)
///   · 找不到 ts      → 「找不到这次漫游」(本地只留最近 50 条,可能被清理)
///   两者都不能退成空 session,否则页面会拿一张 0km/无足迹的漂亮空卡
///   冒充「你这次真的没走」。
class RoamSessionPage extends ConsumerStatefulWidget {
  const RoamSessionPage({
    super.key,
    required this.ts,
    this.shareActions = const SystemRoamShareActions(),
    this.shareCardEncoder = const BoundaryRoamShareCardEncoder(),
  });

  final int ts;
  final RoamShareActions shareActions;
  final RoamShareCardEncoder shareCardEncoder;

  @override
  ConsumerState<RoamSessionPage> createState() => _RoamSessionPageState();
}

enum _LoadState { loading, readError, notFound, ready }

class _RoamSessionPageState extends ConsumerState<RoamSessionPage> {
  _LoadState _state = _LoadState.loading;
  RoamSession? _session;
  RoamRouteLayout _layout = const RoamRouteLayout();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final RoamSession? s = await ref
          .read(roamSessionStoreProvider)
          .findByTs(widget.ts);
      if (!mounted) return;
      if (s == null) {
        setState(() {
          _state = _LoadState.notFound;
          _session = null;
        });
        return;
      }
      setState(() {
        _session = s;
        _layout = layoutRoamRoute(s, size: const Size(335, 260), pad: 30);
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.readError;
        _session = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: switch (_state) {
          _LoadState.loading => const Center(
            child: CupertinoActivityIndicator(),
          ),
          _LoadState.readError => StatusView(
            icon: CupertinoIcons.exclamationmark_triangle,
            message: '漫游记录读不出来',
            sub: '记录还在本机，检查存储权限后重试',
            onRetry: _load,
          ),
          _LoadState.notFound => const StatusView(
            icon: CupertinoIcons.info_circle,
            message: '找不到这次漫游',
            sub: '本地只保留最近 50 次漫游，这次可能已被清理',
          ),
          _LoadState.ready => _buildSession(),
        },
      ),
    );
  }

  Widget _buildSession() {
    final RoamSession s = _session!;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(CyTokens.space4),
      children: <Widget>[
        Text(
          s.routeName,
          style: textTheme.titleMedium?.copyWith(
            fontSize: CyTokens.typeSectionTitle,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          s.completeFact,
          style: textTheme.bodyMedium?.copyWith(
            fontSize: CyTokens.typeBody,
            color: CyTokens.textSecondary,
          ),
        ),
        const SizedBox(height: CyTokens.space1),
        Text(
          s.dateFull,
          style: textTheme.bodySmall?.copyWith(
            fontSize: CyTokens.typeLabel,
            color: CyTokens.textTertiary,
          ),
        ),
        const SizedBox(height: CyTokens.space3),
        // ★ 「没记录到」和「真的是 0」必须分开 —— 与小程序
        //   scene-roam-session 同口径:距离缺失 '—'、探索度缺失 '--'。
        //   写成 `?? 0` 会把「这次没拿到数据」说成「你一步没走」。
        _StatsRow(
          items: <(String, String)>[
            (s.distance?.toStringAsFixed(1) ?? '—', 'km'),
            (s.explorePct == null ? '--%' : '${s.explorePct}%', '探索度'),
            // 探店数缺失按 0 算(小程序 `shops || 0` 同口径:没点亮就是没点亮)。
            ('${s.shops ?? 0}', '点亮'),
            // ★ timeText 两个来源都没有时会兜成 '00:00' —— 同上,
            //   那是「没记到时长」不是「走了 0 秒」。判据抄 statsLine。
            (s.hasDuration ? s.timeText : '—', '用时'),
          ],
        ),
        const SizedBox(height: CyTokens.space3),
        Container(
          padding: const EdgeInsets.all(CyTokens.space2),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(CyTokens.radiusMd),
          ),
          child: AspectRatio(
            aspectRatio: 335 / 260,
            child: CustomPaint(painter: _RoutePainter(layout: _layout)),
          ),
        ),
        if (s.pois.isNotEmpty) ...<Widget>[
          const SizedBox(height: CyTokens.space3),
          const CySectionTitle('这次点亮'),
          const SizedBox(height: CyTokens.space2),
          ...s.pois.map(
            // 行本体交给共用层 CyCell(系统 CupertinoListTile)—— 原来用
            // Material 的 ListTile,是这一页唯一的 Material 控件。
            (RoamPoi p) => CyCell(
              title: p.name,
              subtitle: p.cat == 'merchant' ? '商家' : null,
              leading: _PoiIcon(iconName: p.iconName),
              showChevron: false,
            ),
          ),
        ],
        const SizedBox(height: CyTokens.space4),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton.tinted(
            minimumSize: const Size.fromHeight(44),
            onPressed: () => showCupertinoSheet<void>(
              context: context,
              showDragHandle: true,
              topGap: 0.04,
              scrollableBuilder:
                  (BuildContext context, ScrollController scrollController) =>
                      _RoamShareSheet(
                        session: s,
                        layout: _layout,
                        actions: widget.shareActions,
                        encoder: widget.shareCardEncoder,
                        scrollController: scrollController,
                      ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(CupertinoIcons.share, size: 18),
                SizedBox(width: CyTokens.space2),
                Text('生成足迹卡'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoamShareSheet extends StatefulWidget {
  const _RoamShareSheet({
    required this.session,
    required this.layout,
    required this.actions,
    required this.encoder,
    required this.scrollController,
  });

  final RoamSession session;
  final RoamRouteLayout layout;
  final RoamShareActions actions;
  final RoamShareCardEncoder encoder;
  final ScrollController scrollController;

  @override
  State<_RoamShareSheet> createState() => _RoamShareSheetState();
}

class _RoamShareSheetState extends State<_RoamShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;
  String? _error;

  String get _fileName => 'cityfog-${widget.session.ts}.png';

  Future<Uint8List> _captureCard() async {
    final RenderObject? renderObject = _cardKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('足迹卡尚未准备好');
    }
    return widget.encoder.capture(renderObject);
  }

  Future<void> _saveToAlbum() async {
    // 弹层走共用层 cyConfirm:iOS 26+ 是真系统 alert(Liquid Glass),
    // 旧系统回退 CupertinoAlertDialog —— 手册 S4「确认 = cyConfirm」。
    final bool accepted = await cyConfirm(
      context,
      title: '保存足迹卡到相册',
      content: '用于把这张足迹卡写入系统相册，方便你留存或之后分享。',
      confirmText: '继续',
      cancelText: '取消',
    );
    if (!accepted || !mounted) return;
    await _run(() async {
      final Uint8List bytes = await _captureCard();
      await widget.actions.saveToAlbum(bytes, fileName: _fileName);
      if (!mounted) return;
      CyNativeNotice.show(context, '已保存到相册');
    }, '保存失败，请检查相册权限后重试');
  }

  Future<void> _share() async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final Rect origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    await _run(() async {
      final Uint8List bytes = await _captureCard();
      await widget.actions.share(
        bytes,
        fileName: _fileName,
        sharePositionOrigin: origin,
      );
    }, '无法打开系统分享，请重试');
  }

  Future<void> _run(Future<void> Function() action, String error) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final CyPalette palette = CyPalette.of(context);
    final bool usesLargeText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final Widget saveButton = CupertinoButton.filled(
      key: const Key('roam-save-album'),
      minimumSize: const Size.fromHeight(44),
      color: palette.actionPrimaryBg,
      foregroundColor: palette.actionPrimaryFg,
      onPressed: _busy ? null : _saveToAlbum,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(CupertinoIcons.photo_on_rectangle, size: 18),
          SizedBox(width: CyTokens.space1),
          Flexible(child: Text('保存到相册')),
        ],
      ),
    );
    final Widget shareButton = CupertinoButton.tinted(
      key: const Key('roam-system-share'),
      minimumSize: const Size.fromHeight(44),
      onPressed: _busy ? null : _share,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(CupertinoIcons.share, size: 18),
          SizedBox(width: CyTokens.space1),
          Flexible(child: Text('系统分享')),
        ],
      ),
    );
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('分享足迹卡')),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(
            CyTokens.space4,
            CyTokens.space3,
            CyTokens.space4,
            CyTokens.space4,
          ),
          children: <Widget>[
            RepaintBoundary(
              key: _cardKey,
              child: _ShareCard(session: widget.session, layout: widget.layout),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: CyTokens.space2),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('roam-share-error'),
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ),
            ],
            const SizedBox(height: CyTokens.space3),
            if (usesLargeText)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  saveButton,
                  const SizedBox(height: CyTokens.space2),
                  shareButton,
                ],
              )
            else
              Row(
                children: <Widget>[
                  Expanded(child: saveButton),
                  const SizedBox(width: CyTokens.space2),
                  Expanded(child: shareButton),
                ],
              ),
            CupertinoButton(
              key: const Key('roam-share-back'),
              minimumSize: const Size.fromHeight(44),
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('返回本次漫游'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: items
          .map(
            ((String, String) item) => Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    item.$1,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: CyTokens.typeSectionTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.$2,
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: CyTokens.typeCaption,
                      color: CyTokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PoiIcon extends StatelessWidget {
  const _PoiIcon({required this.iconName});

  final String iconName;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (iconName) {
      'poi-shop' => Icons.storefront_outlined,
      'poi-park' => Icons.park_outlined,
      _ => Icons.place_outlined,
    };
    return Icon(icon, size: 20, color: CyTokens.textSecondary);
  }
}

/// 路线画笔:深底上画灰白路线 + 彩色圆点。
/// 布局由 [layoutRoamRoute] 纯函数算好,这里只负责画。
class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.layout});

  final RoamRouteLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = roamRouteColors.first
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final RoamRouteSegment seg in layout.segs) {
      final double rad = seg.deg * 3.141592653589793 / 180;
      final Offset start = Offset(seg.x.toDouble(), seg.y.toDouble());
      canvas.drawLine(
        start,
        start + Offset(seg.len * math.cos(rad), seg.len * math.sin(rad)),
        line,
      );
    }
    for (final RoamRouteDot dot in layout.dots) {
      canvas.drawCircle(
        Offset(dot.x.toDouble(), dot.y.toDouble()),
        8,
        Paint()..color = dot.color,
      );
      canvas.drawCircle(
        Offset(dot.x.toDouble(), dot.y.toDouble()),
        8,
        Paint()
          ..color = roamRouteColors.first
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    if (layout.segs.isEmpty) {
      final TextPainter tp = TextPainter(
        text: const TextSpan(
          text: '这次没有记录到轨迹',
          style: TextStyle(fontSize: 13, color: Color(0xFF737373)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) => false;
}

/// 足迹卡(对齐小程序 session 分享卡版式):深色渐变底 + 路线图 + 标题 +
/// 统计行 + 水印。App 未接相册保存插件,这里先做卡内预览。
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.session, required this.layout});

  final RoamSession session;
  final RoamRouteLayout layout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(CyTokens.space4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF171717), Color(0xFF0B0B0B)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(CyTokens.radiusLg)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 335 / 260,
            child: CustomPaint(painter: _RoutePainter(layout: layout)),
          ),
          const SizedBox(height: CyTokens.space3),
          Text(
            session.routeName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: CyTokens.typeCardTitle,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFFFFF),
            ),
          ),
          const SizedBox(height: CyTokens.space1),
          Text(
            session.completeFact,
            style: const TextStyle(
              fontSize: CyTokens.typeCaption,
              color: Color(0xFFD9D9D9),
            ),
          ),
          const SizedBox(height: CyTokens.space2),
          Text(
            session.dateFull,
            style: const TextStyle(
              fontSize: CyTokens.typeCaption,
              color: Color(0xFF737373),
            ),
          ),
          const SizedBox(height: CyTokens.space3),
          Row(
            // ★ 与页面统计行同口径。这里更要紧:足迹卡是用户**存进相册、
            //   发出去**的一张图,上面印一个假的「0.0 km」是永久的。
            children:
                <(String, String)>[
                  (session.distance?.toStringAsFixed(1) ?? '—', 'km'),
                  (
                    session.explorePct == null
                        ? '--%'
                        : '${session.explorePct}%',
                    '探索度',
                  ),
                  ('${session.shops ?? 0}', '点亮'),
                ].map(((String, String) item) {
                  return Expanded(
                    child: Column(
                      children: <Widget>[
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontSize: CyTokens.typeSectionTitle,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: CyTokens.typeCaption,
                            color: Color(0xFF737373),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: CyTokens.space3),
          const Center(
            child: Text(
              '城瘾 · CityFog',
              style: TextStyle(
                fontSize: CyTokens.typeCaption,
                color: Color(0xFF404040),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
