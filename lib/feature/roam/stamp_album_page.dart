import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/cy_palette.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/roam.dart';
import '../auth/auth_controller.dart';
import '../auth/login_gate.dart';
import 'stamp_collage_layout.dart';

/// 集邮册。散落 collage,不是网格 —— 与小程序 stamp-album 同一套布局算法。
///
/// ★ 三个状态的**互斥关系**照搬小程序,它们各自解决一个真出过的问题:
///   ① `loaded` 与 `error` 不是一回事。读失败时若把 loaded 置真,
///      空态「还没有邮票」就会替失败背书 —— 用户以为册子被清空了。
///   ② 整屏失败态**只在一枚都没渲染出来时**用。已经有邮票时那是**续页**
///      失败,整屏报错会把看得好好的册子换成一张错误图。
///   ③ 计数「N 枚」是权威口吻的大字,**数据没回来就先不说** ——
///      不然会出现「0 枚」和「加载中…」同屏。
class StampAlbumPage extends ConsumerStatefulWidget {
  const StampAlbumPage({super.key});

  @override
  ConsumerState<StampAlbumPage> createState() => _StampAlbumPageState();
}

class _StampAlbumPageState extends ConsumerState<StampAlbumPage> {
  static const int _cols = 4;
  static const int _pageSize = 50;

  final ScrollController _scroll = ScrollController();
  final List<RoamStamp> _items = <RoamStamp>[];

  int _total = 0;
  int _pageNum = 1;
  bool _loading = false;
  bool _loaded = false;
  bool _error = false;
  bool _noMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || _noMore) return;
    // 游客:接口必然 401,先不发这个注定失败的请求,由页内登录门解释。
    if (!ref.read(authControllerProvider).isLoggedIn) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final RoamStampPage page = await ref
          .read(roamApiProvider)
          .stampList(pageNum: _pageNum, pageSize: _pageSize);
      if (!mounted) return;
      setState(() {
        // 违规(checkState=2)的后端已移出册子,这里再挡一次:
        // 未送检(0)照显示 —— 机审关闭时那是诚实值,藏掉会让册子整个空掉。
        _items.addAll(page.list.where((RoamStamp s) => s.visible));
        _total = page.total;
        _pageNum += 1;
        _noMore = !page.hasMore;
        _loading = false;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      // ★ 失败时 _loaded 保持原值,别置真 —— 否则空态会替失败背书。
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _retry() {
    setState(() => _noMore = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      navigationBar: const CupertinoNavigationBar(),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const CyPageTitle('集邮册'),
                  // ③ 数据没回来就先不说「N 枚」
                  if (_loaded)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CyTokens.space4,
                        vertical: CyTokens.space2,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Text(
                            '$_total',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(width: CyTokens.space1),
                          Text(
                            '枚',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: CyPalette.of(context).textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: _body()),
                ],
              ),
            ),
            // 原生页没有 Material FAB 槽，按原来的右下角落点叠加同一个动作。
            // 空态自带「打开集邮相机」，仍然不重复显示。
            if (_total > 0)
              Positioned(
                right: CyTokens.space4,
                bottom: MediaQuery.paddingOf(context).bottom + CyTokens.space4,
                child: Semantics(
                  label: '拍摄邮票',
                  button: true,
                  child: CupertinoButton(
                    key: const Key('stamp-camera-fab'),
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.all(CyTokens.space2),
                    color: CyPalette.of(context).actionPrimaryBg,
                    borderRadius: BorderRadius.circular(CyTokens.radiusXl),
                    onPressed: _goCamera,
                    child: Icon(
                      CupertinoIcons.camera_fill,
                      color: CyPalette.of(context).actionPrimaryFg,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    // ★ 游客深链落地时给登录门,而不是被静默弹回首页(B1 模拟器报告 P1)——
    //   路由那边已不再拦这两条深链,解释与登入口都放在这一屏。
    //   刻意不自动弹登录弹窗:冷启动深链直接盖一层 sheet 同样像"链接坏了"。
    if (!ref.watch(authControllerProvider).isLoggedIn) {
      return StatusView(
        key: const Key('stamp-album-login-gate'),
        message: '登录后查看集邮册',
        sub: '邮票存在账号里,登录完就能看到。',
        icon: CupertinoIcons.lock,
        large: true,
        retryLabel: '去登录',
        onRetry: () async {
          if (!await requireLogin(context, ref)) return;
          if (!mounted) return;
          _retry();
        },
      );
    }
    // ② 整屏失败只在一枚都没渲染出来时
    if (_error && _items.isEmpty) {
      return StatusView(
        message: '集邮册没打开',
        sub: '邮票都还在,只是这次没读到',
        icon: CupertinoIcons.exclamationmark_triangle,
        large: true,
        onRetry: _retry,
      );
    }
    if (_loading && _items.isEmpty) return const CySkeleton();
    if (_loaded && _total == 0) {
      return StatusView(
        message: '还没有邮票',
        sub: '上街拍一张，城市就进你的册子了',
        icon: CupertinoIcons.camera,
        large: true,
        retryLabel: '打开集邮相机',
        onRetry: _goCamera,
      );
    }
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints box) {
        final double usable = box.maxWidth - 24;
        final double cellW = usable / _cols;
        final double cellH = cellW * 1.25;
        final List<StampSlot> slots = collageLayout(
          _items.length,
          cols: _cols,
          cellW: cellW,
          cellH: cellH,
        );
        final double stageH = (_items.length / _cols).ceil() * cellH + 60;

        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: <Widget>[
              SizedBox(
                height: stageH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    for (int i = 0; i < _items.length; i++)
                      Positioned(
                        left: slots[i].x,
                        top: slots[i].y,
                        width: cellW * 0.86,
                        height: cellH * 0.86,
                        child: Transform.rotate(
                          angle: slots[i].rotDeg * 3.1415926535 / 180,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusSm,
                            ),
                            child: Image.network(
                              _items[i].picUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: CyPalette.of(ctx).bgElevated,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 续页的加载/失败只占页尾一行,不动已经看到的邮票。
              if (_loading && _items.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(CyTokens.space4),
                  child: Text('正在读取下一页'),
                )
              else if (_error && _items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(CyTokens.space4),
                  // 读屏文案照小程序 stamp-album/index.wxml 的 aria-label。
                  child: Semantics(
                    label: '重试加载这一页',
                    button: true,
                    child: CupertinoButton(
                      onPressed: _retry,
                      minimumSize: const Size(44, 44),
                      child: const Text('这一页没读到 · 点此重试'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _goCamera() => GoRouter.of(context).push('/roam/stamp-camera');
}
