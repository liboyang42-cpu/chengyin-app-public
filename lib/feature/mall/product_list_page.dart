import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/status_view.dart';
import '../../data/models/product.dart';
import 'mall_controller.dart';
import '../../core/theme/cy_tokens.dart';
import '../../core/widgets/cy_widgets.dart';
import '../../core/widgets/cy_net_image.dart';

/// 商城:商品网格(图 + 名 + 价格),三态,点进详情。右上角入口去购物车。
class ProductListPage extends ConsumerWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productListProvider);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        trailing: Semantics(
          button: true,
          label: '购物车',
          child: SizedBox.square(
            dimension: 44,
            child: CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              onPressed: () => context.push('/cart'),
              child: const Icon(CupertinoIcons.cart),
            ),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: Column(
            // 页标题左对齐:Column 默认 crossAxisAlignment 是 center,
            // 不显式 stretch 会把 58rpx 大标题推到屏幕正中,与小程序完全不同。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const CyPageTitle('商城'),
              Expanded(
                child: products.when(
                  loading: () =>
                      const CySkeleton(type: CySkeletonType.card, count: 6),
                  error: (Object err, StackTrace st) => StatusView(
                    message: '商品拉取失败',
                    sub: '请检查网络或稍后再试。',
                    icon: CupertinoIcons.exclamationmark_triangle,
                    scrollable: true,
                    onRetry: () => ref.invalidate(productListProvider),
                  ),
                  data: (List<Product> list) {
                    if (list.isEmpty) {
                      return StatusView(
                        message: '暂无商品',
                        sub: '商家上架商品后会显示在这里。',
                        icon: Icons.storefront_outlined,
                        scrollable: true,
                        onRetry: () => ref.invalidate(productListProvider),
                      );
                    }
                    return RefreshIndicator.adaptive(
                      onRefresh: () async =>
                          ref.invalidate(productListProvider),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(CyTokens.space4),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: CyTokens.space3,
                              crossAxisSpacing: CyTokens.space3,
                              childAspectRatio: 0.68,
                            ),
                        itemCount: list.length,
                        itemBuilder: (context, i) =>
                            _ProductCard(product: list[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: CupertinoButton(
        onPressed: () => context.push('/product/${product.id}'),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ★ 售罄要在**列表上**就能看出来。详情页早就有 `soldOut`(按钮置灰),
            //   但列表卡完全无视 stock —— 价格照常显示,看着完全能买,
            //   用户点进去才发现买不了。同一个事实两个页面说法不一致。
            //   (商城是 App 独有,小程序没有对应页,所以没有可对标的样式;
            //    这里跟详情页保持同一套判据 stock <= 0。)
            Stack(
              children: <Widget>[
                AspectRatio(
                  aspectRatio: 1,
                  child: _ProductImage(url: product.pic),
                ),
                if (product.stock <= 0)
                  Positioned.fill(
                    child: ColoredBox(
                      color: CyTokens.overlay,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: CyTokens.space3,
                            vertical: CyTokens.space1,
                          ),
                          decoration: BoxDecoration(
                            color: CyTokens.bgSurfaceStrong,
                            borderRadius: BorderRadius.circular(
                              CyTokens.radiusPill,
                            ),
                          ),
                          child: Text(
                            '已售罄',
                            style: CyType.caption1.copyWith(
                              color: CyTokens.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // ★ 网格单元高度是固定的(childAspectRatio: 0.68),图片又占满整个
            //   宽度的 1:1 —— 留给文字的高度是**算出来的余量**,不是想多高有多高。
            //   原来这里是裸 Padding + Column,商品名一到两行就把卡片撑爆 14px
            //   (RenderFlex overflow)。理想数据永远看不到:短名字只有一行。
            //   Expanded 把余量交给文字区,Flexible 让标题在余量不够时真的省略,
            //   价格行始终贴底 —— 名字长短都不会顶到别人。
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(CyTokens.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        product.productName.isEmpty
                            ? '未命名商品'
                            : product.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CyType.subhead.copyWith(
                          color: CyTokens.textPrimary,
                        ),
                      ),
                    ),
                    // spaceBetween 已经把两端顶开,不再需要固定间距
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          formatPoints(product.pricePoints),
                          style: CyType.callout.copyWith(
                            fontWeight: FontWeight.w600,
                            color: CyTokens.textPrimary,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        if (product.originalPricePoints != null) ...<Widget>[
                          const SizedBox(width: CyTokens.space1_5),
                          Text(
                            formatPoints(product.originalPricePoints),
                            style: CyType.caption1.copyWith(
                              color: CyTokens.textTertiary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    // 兜底走共用件:加载不出来安静铺一块同色底,不摆 Material 碎图标。
    return CyNetImage(url);
  }
}
