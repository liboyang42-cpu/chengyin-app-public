import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/models/product.dart';

/// 后端是不是以「未登录」拒绝了这次商城请求。
///
/// 商城 7 个接口对无 token 的请求统一返回 HTTP 401
/// (`{"code":401,"msg":"登录状态已失效，请重新登录"}`,2026-09-18 生产实测),
/// 唯独列表 `/api/product/list` 放开 —— 列表公开、详情与购物车要登录。
/// 这是**有意拒绝**,不是故障:渲成「请检查网络」会让游客反复重试一条永远走不通的路。
/// 只认 401,不把断网/500 也当成要登录(那会把断网用户反复推去登录页)。
bool isMallLoginRequired(Object err) =>
    err is DioException && err.response?.statusCode == 401;

/// 商品列表(默认排序 0、不限商户)。
final productListProvider = FutureProvider.autoDispose<List<Product>>((ref) {
  return ref.watch(mallApiProvider).productList();
});

/// 商品详情(按 id)。
final productDetailProvider = FutureProvider.autoDispose.family<Product, int>((
  ref,
  id,
) {
  return ref.watch(mallApiProvider).productInfo(id);
});

/// 购物车列表。加购 / 改数量 / 删除后 invalidate 刷新。
final cartListProvider = FutureProvider.autoDispose<List<CartItem>>((ref) {
  return ref.watch(mallApiProvider).cartList();
});
