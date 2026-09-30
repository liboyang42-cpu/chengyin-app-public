// 商城商品 + 购物车项(对齐后端 PmsProduct / ViewMemberCart)。

import 'package:chengyin_app/core/util/json_parse.dart';

/// 积分数的统一展示。未知保持“待确认”，不冒充 0；整数不补 `.00`。
String formatPoints(num? value) {
  if (value == null || !value.isFinite) return '积分待确认';
  final String text = value % 1 == 0
      ? value.toStringAsFixed(0)
      : value
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return '$text 积分';
}

/// 商品(对齐 PmsProduct,`/api/product/list` 与 `/api/product/info`)。
/// 注意:`price`/`originalPrice` 是积分商城的**积分数**，不是人民币分。
class Product {
  Product({
    required this.id,
    required this.productName,
    required this.price,
    this.pic,
    this.albumPics,
    this.originalPrice,
    this.stock = 0,
    this.unit,
    this.merchantId,
    this.detailHtml,
    this.skuList = const <ProductSku>[],
  });

  final int id;
  final String productName;

  /// 单位:积分。
  final int price;
  final String? pic;

  /// 相册图,逗号分隔(列表接口会被后端清空)。
  final String? albumPics;

  /// 单位:积分。
  final int? originalPrice;
  final int stock;
  final String? unit;
  final int? merchantId;

  /// 详情富文本(列表接口会被后端清空)。
  final String? detailHtml;

  /// 规格列表(仅详情接口返回)。
  final List<ProductSku> skuList;

  /// 兑换所需积分。保留明确命名，避免调用方误当成人民币分再除以 100。
  int get pricePoints => price;

  /// 原积分，无则 null。
  int? get originalPricePoints =>
      (originalPrice == null || originalPrice == 0) ? null : originalPrice;

  /// 相册图拆分(过滤空串)。
  List<String> get albumList => (albumPics ?? '')
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: asInt(json['id']),
    productName: (json['productName'] ?? '') as String,
    price: asInt(json['price']),
    pic: json['pic'] as String?,
    albumPics: json['albumPics'] as String?,
    originalPrice: json['originalPrice'] == null
        ? null
        : asInt(json['originalPrice']),
    stock: asInt(json['stock']),
    unit: json['unit'] as String?,
    merchantId: json['merchantId'] == null ? null : asInt(json['merchantId']),
    detailHtml: json['detailHtml'] as String?,
    skuList: ((json['skuList'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic e) => ProductSku.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// 商品规格(对齐 PmsSku)。`price` 为 BigDecimal，语义仍是积分。
class ProductSku {
  ProductSku({required this.id, this.skuName, this.price, this.stock = 0});

  final int id;
  final String? skuName;

  /// 积分。
  final double? price;
  final int stock;

  factory ProductSku.fromJson(Map<String, dynamic> json) => ProductSku(
    id: asInt(json['id']),
    skuName: json['skuName'] as String?,
    price: asDouble(json['price']),
    stock: asInt(json['stock']),
  );
}

/// 购物车项(对齐 ViewMemberCart,`/api/cart/list`)。
/// `price`/`originalPrice` 为积分商城积分数；BigDecimal 只代表存储类型。
class CartItem {
  CartItem({
    required this.id,
    required this.productId,
    required this.skuId,
    required this.quantity,
    this.productName,
    this.productPic,
    this.price,
    this.originalPrice,
    this.skuName,
  });

  /// 购物车记录 id(update/delete 用)。
  final int id;
  final int productId;
  final int skuId;
  final int quantity;
  final String? productName;
  final String? productPic;

  /// 积分。
  final double? price;

  /// 积分。
  final double? originalPrice;
  final String? skuName;

  /// 小计(积分)= 单价 × 数量。**价格拿不到时返回 null,不是 0** ——
  /// `price ?? 0` 会把一件不知道多少积分的商品显示成 0 积分(看着像免费),
  /// 合计还会静默少算,界面上的数字和结账时不是一个数。
  double? get subtotalPoints => price == null ? null : price! * quantity;

  /// 价格是否可用。调用方据此决定显示金额还是「价格待确认」。
  bool get hasPrice => price != null;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final int id = asInt(json['id']);
    final int productId = asInt(json['productId']);
    final int skuId = asInt(json['skuId']);
    final int quantity = asInt(json['quantity']);
    if (id <= 0 || productId <= 0 || skuId <= 0 || quantity <= 0) {
      throw const FormatException('购物车商品缺少有效标识或数量');
    }
    return CartItem(
      id: id,
      productId: productId,
      skuId: skuId,
      quantity: quantity,
      productName: json['productName'] as String?,
      productPic: json['productPic'] as String?,
      price: asDouble(json['price']),
      originalPrice: asDouble(json['originalPrice']),
      skuName: json['skuName'] as String?,
    );
  }
}

/// `/api/cart/settlement` 返回的默认收货地址快照。
///
/// 地址允许为空（用户可能还没创建），但一旦存在就必须带正 id；否则提交时
/// 无法把它作为后端 `addressid` 使用，不能静默兜成 0。
class SettlementAddress {
  const SettlementAddress({
    required this.id,
    required this.fullName,
    required this.mobilePhone,
    this.province,
    this.detailAddress,
    this.isDefault = false,
  });

  final int id;
  final String fullName;
  final String mobilePhone;
  final String? province;
  final String? detailAddress;
  final bool isDefault;

  String get oneLine => <String?>[province, detailAddress]
      .where((String? value) => value != null && value.trim().isNotEmpty)
      .join(' ');

  factory SettlementAddress.fromJson(Map<String, dynamic> json) {
    final int id = asInt(json['id']);
    if (id <= 0) throw const FormatException('结算地址缺少有效 id');
    return SettlementAddress(
      id: id,
      fullName: (json['fullName'] ?? '').toString(),
      mobilePhone: (json['mobilePhone'] ?? '').toString(),
      province: json['province']?.toString(),
      detailAddress: json['detailAddress']?.toString(),
      isDefault:
          json['isDefault'] == 1 ||
          json['isDefault'] == '1' ||
          json['isDefault'] == true,
    );
  }
}

/// 积分商城结算预览，对齐后端 `MemberCartVO`。
///
/// 后端未下发的金额、数量和积分余额都保持 null。未知不是 0，调用方不得
/// 因为字段缺席就显示“0 积分”或判断“积分不足”。
class CartSettlementPreview {
  const CartSettlementPreview({
    this.cartType,
    this.productAmount,
    this.productQuantity,
    this.productWeight,
    this.deliveryFee,
    this.taxFee,
    this.totalAmount,
    this.products,
    this.address,
    this.pointBalance,
  });

  final int? cartType;
  final double? productAmount;
  final int? productQuantity;
  final double? productWeight;
  final double? deliveryFee;
  final double? taxFee;
  final double? totalAmount;
  final List<CartItem>? products;
  final SettlementAddress? address;
  final double? pointBalance;

  int? get requiredPoints => totalAmount?.ceil();

  bool? get hasEnoughPoints {
    final int? required = requiredPoints;
    if (required == null || pointBalance == null) return null;
    return pointBalance! >= required;
  }

  factory CartSettlementPreview.fromJson(Map<String, dynamic> json) {
    final Object? rawProducts = json['productList'];
    final Object? rawAddress = json['address'];
    if (rawProducts != null && rawProducts is! List<dynamic>) {
      throw const FormatException('结算商品列表格式不正确');
    }
    if (rawAddress != null && rawAddress is! Map<String, dynamic>) {
      throw const FormatException('结算地址格式不正确');
    }
    final List<dynamic>? productRows = rawProducts is List<dynamic>
        ? rawProducts
        : null;
    if (productRows != null &&
        productRows.any((dynamic row) => row is! Map<String, dynamic>)) {
      throw const FormatException('结算商品行格式不正确');
    }
    final Map<String, dynamic>? addressJson = rawAddress is Map<String, dynamic>
        ? rawAddress
        : null;

    return CartSettlementPreview(
      cartType: _nullableInt(json['cartType']),
      productAmount: asDouble(json['productAmount']),
      productQuantity: _nullableInt(json['productQuantity']),
      productWeight: asDouble(json['productWeight']),
      deliveryFee: asDouble(json['deliveryFee']),
      taxFee: asDouble(json['taxFee']),
      totalAmount: asDouble(json['totalAmount']),
      products: productRows
          ?.cast<Map<String, dynamic>>()
          .map(CartItem.fromJson)
          .toList(growable: false),
      address: addressJson == null
          ? null
          : SettlementAddress.fromJson(addressJson),
      pointBalance: asDouble(json['pointBalance']),
    );
  }
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
