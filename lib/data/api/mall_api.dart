import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/product.dart';

/// 积分商城接口(对齐后端 ApiProductController / ApiCartController)。
class MallApi {
  MallApi(this._client);
  final DioClient _client;

  /// 校验 AjaxResult.code==200,返回 data;否则抛异常进 error 态。
  Map<String, dynamic> _body(Response<Map<String, dynamic>> resp) {
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '请求失败').toString());
    }
    return body;
  }

  /// 商品列表:`POST /api/product/list`,getDataTable → data.rows。
  /// sortType:0默认 1时间倒 2时间升 3价格倒 4价格升;merchantId>0 才传。
  Future<List<Product>> productList({
    int? merchantId,
    int sortType = 0,
    String? keyword,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/product/list',
      data: FormData.fromMap(<String, dynamic>{
        if (merchantId != null && merchantId > 0)
          'merchant_id': merchantId.toString(),
        'sort_type': sortType.toString(),
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      }),
    );
    final data = _body(resp)['data'] as Map<String, dynamic>?;
    final rows = (data?['rows'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 商品详情:`POST /api/product/info`,success(对象) → data 即商品。
  Future<Product> productInfo(int id) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/product/info',
      data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
    );
    final data = _body(resp)['data'] as Map<String, dynamic>?;
    if (data == null) throw Exception('商品不存在');
    return Product.fromJson(data);
  }

  /// 购物车列表:`POST /api/cart/list`,getDataTable → data.rows(ViewMemberCart)。
  Future<List<CartItem>> cartList() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/cart/list',
      data: FormData.fromMap(<String, dynamic>{}),
    );
    final data = _body(resp)['data'] as Map<String, dynamic>?;
    final rows = (data?['rows'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => CartItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 加入购物车:`POST /api/cart/cart/add`。
  /// 后端要求 product_id/sku_id/quantity/is_buy **四项均非空**;is_buy=0 表示加购非直购。
  Future<void> cartAdd({
    required int productId,
    required int skuId,
    required int quantity,
    int isBuy = 0,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/cart/cart/add',
      data: FormData.fromMap(<String, dynamic>{
        'product_id': productId.toString(),
        'sku_id': skuId.toString(),
        'quantity': quantity.toString(),
        'is_buy': isBuy.toString(),
      }),
    );
    _body(resp);
  }

  /// 改数量:`POST /api/cart/update`,参数 cart_id/quantity/sku_id。
  Future<void> cartUpdate({
    required int cartId,
    required int quantity,
    required int skuId,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/cart/update',
      data: FormData.fromMap(<String, dynamic>{
        'cart_id': cartId.toString(),
        'quantity': quantity.toString(),
        'sku_id': skuId.toString(),
      }),
    );
    _body(resp);
  }

  /// 删除:`POST /api/cart/delete`,参数 cartids(逗号分隔,这里单个)。
  Future<void> cartDelete(int cartId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/cart/delete',
      data: FormData.fromMap(<String, dynamic>{'cartids': cartId.toString()}),
    );
    _body(resp);
  }

  /// 购物车结算预览：`POST /api/cart/settlement`。
  Future<CartSettlementPreview> previewSettlement(List<int> cartIds) async {
    final String encoded = _cartIds(cartIds);
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/cart/settlement',
      data: FormData.fromMap(<String, dynamic>{'cartids': encoded}),
    );
    final Object? data = _body(resp)['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('结算信息缺失');
    }
    return CartSettlementPreview.fromJson(data);
  }

  /// 确认积分兑换：`POST /api/cart/order/settlement`，返回首个订单 id。
  Future<int> settleOrder({
    required List<int> cartIds,
    required String remark,
    required int addressId,
  }) async {
    final String encoded = _cartIds(cartIds);
    if (addressId <= 0) {
      throw ArgumentError.value(addressId, 'addressId', '必须是正整数');
    }
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/cart/order/settlement',
      data: FormData.fromMap(<String, dynamic>{
        'cartids': encoded,
        'remark': remark,
        'addressid': addressId.toString(),
      }),
    );
    final Object? rawId = _body(resp)['data'];
    final int? id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    if (id == null || id <= 0) throw const FormatException('订单 id 缺失');
    return id;
  }

  String _cartIds(List<int> ids) {
    if (ids.isEmpty ||
        ids.any((int id) => id <= 0) ||
        ids.toSet().length != ids.length) {
      throw ArgumentError.value(ids, 'cartIds', '必须是非空、不重复的正整数');
    }
    return ids.join(',');
  }
}
