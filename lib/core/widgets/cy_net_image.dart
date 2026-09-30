import 'package:flutter/material.dart';

import '../theme/cy_palette.dart';

/// 网络图片,带**统一兜底**。
///
/// ★★ 为什么要有它:全仓 58 处 `Image.network`,其中 13 处**没有 errorBuilder**
///   (2026-08-19 扫出来的)。URL 挂了、图被删了、或者后端下发空串时,
///   Flutter 会画一个系统碎图标 —— 那东西在深色底上是个刺眼的灰白方块,
///   而且它**长得像 bug 而不像"这张图没了"**。
///
///   和地图 Key 那次是同一个病:靠"每个调用方记得写 errorBuilder"的约定
///   必然漏掉一批。收口成组件,新代码天然有兜底。
///
/// ★ 兜底不画图标、只铺一块与卡片同色的底 —— 一张加载不出来的封面,
///   最好的表现是"安静地不在那里",而不是"这里有个错误"。
///   真需要提示的场景(如"这张照片有问题")由调用方自己传 [fallback]。
class CyNetImage extends StatelessWidget {
  const CyNetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  /// 图片地址。**可空且允许空串** —— 后端很多字段是 `String?`,
  /// 调用方不必自己先判一次。
  final String? url;

  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// 自定义兜底。不传就用一块同色底。
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    // ★ 兜底色必须**跟着主题走**:商家域是浅色页,写死深色 token
    //   会在白底上变成一个黑方块(门禁 light_pages_no_static_colors 抓到过)。
    final Widget placeholder = fallback ??
        SizedBox(
          width: width,
          height: height,
          child: ColoredBox(color: CyPalette.of(context).bgSurfaceSubtle),
        );

    final String? u = url;
    // ★ 空 URL 直接走兜底,不进 Image.network ——
    //   传空串给它会抛 "Invalid argument(s): No host specified in URI"。
    if (u == null || u.trim().isEmpty) return _clip(placeholder);

    return _clip(Image.network(
      u,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    ));
  }

  Widget _clip(Widget child) {
    final BorderRadius? r = borderRadius;
    return r == null ? child : ClipRRect(borderRadius: r, child: child);
  }
}
