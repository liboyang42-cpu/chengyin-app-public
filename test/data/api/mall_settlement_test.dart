import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/mall_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  ({MallApi api, List<RequestOptions> sent}) build(
    Map<String, dynamic> Function(RequestOptions) reply,
  ) {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final List<RequestOptions> sent = <RequestOptions>[];
    client.dio.httpClientAdapter = _StubAdapter((RequestOptions options) {
      sent.add(options);
      return reply(options);
    });
    return (api: MallApi(client), sent: sent);
  }

  Map<String, String> fields(RequestOptions options) => <String, String>{
    for (final MapEntry<String, String> field
        in (options.data as FormData).fields)
      field.key: field.value,
  };

  test('结算预览发送精确 cartids，并保留积分与默认地址', () async {
    final fixture = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'cartType': 2,
          'productAmount': '320',
          'productQuantity': '3',
          'productWeight': null,
          'deliveryFee': 0,
          'taxFee': '0',
          'totalAmount': '320',
          'pointBalance': '500',
          'productList': <dynamic>[
            <String, dynamic>{
              'id': 11,
              'productId': 101,
              'skuId': 1001,
              'quantity': 2,
              'productName': '城市邮票册',
              'price': '160',
            },
          ],
          'address': <String, dynamic>{
            'id': 7,
            'fullName': '顾青',
            'mobilePhone': '13900001111',
            'province': '上海市 黄浦区',
            'detailAddress': '中山东一路 1 号',
            'isDefault': 1,
          },
        },
      },
    );

    final preview = await fixture.api.previewSettlement(<int>[11, 12]);

    expect(fixture.sent.single.path, '/api/cart/settlement');
    expect(fields(fixture.sent.single), <String, String>{'cartids': '11,12'});
    expect(preview.cartType, 2);
    expect(preview.productAmount, 320);
    expect(preview.productQuantity, 3);
    expect(preview.productWeight, isNull);
    expect(preview.totalAmount, 320);
    expect(preview.pointBalance, 500);
    expect(preview.hasEnoughPoints, isTrue);
    expect(preview.products!.single.subtotalPoints, 320);
    expect(preview.address?.id, 7);
    expect(preview.address?.oneLine, '上海市 黄浦区 中山东一路 1 号');
  });

  test('预览空地址与未知积分余额保持 null，不冒充 0', () async {
    final fixture = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'cartType': 2,
          'productAmount': 80,
          'productQuantity': 1,
          'deliveryFee': 0,
          'taxFee': 0,
          'totalAmount': 80,
          'productList': <dynamic>[],
          'address': null,
          'pointBalance': null,
        },
      },
    );

    final preview = await fixture.api.previewSettlement(<int>[1]);
    expect(preview.address, isNull);
    expect(preview.pointBalance, isNull);
    expect(preview.hasEnoughPoints, isNull);
  });

  test('提交兑换发送精确 FormData，并返回服务端订单 id', () async {
    final fixture = build((_) => <String, dynamic>{'code': 200, 'data': 9876});

    final orderId = await fixture.api.settleOrder(
      cartIds: <int>[11, 12],
      remark: '工作日送达',
      addressId: 7,
    );

    expect(fixture.sent.single.path, '/api/cart/order/settlement');
    expect(fields(fixture.sent.single), <String, String>{
      'cartids': '11,12',
      'remark': '工作日送达',
      'addressid': '7',
    });
    expect(orderId, 9876);
  });

  test('服务端积分不足原话透传，不能在客户端改写成支付失败', () async {
    final fixture = build((_) => <String, dynamic>{'code': 500, 'msg': '积分不足'});

    await expectLater(
      fixture.api.settleOrder(cartIds: <int>[11], remark: '', addressId: 7),
      throwsA(predicate((Object error) => error.toString().contains('积分不足'))),
    );
  });

  test('空、重复、非正 cart id 在发请求前拒绝', () async {
    final fixture = build((_) => <String, dynamic>{'code': 200});

    for (final ids in <List<int>>[
      <int>[],
      <int>[1, 1],
      <int>[0],
      <int>[-1],
    ]) {
      await expectLater(
        fixture.api.previewSettlement(ids),
        throwsArgumentError,
      );
    }
    expect(fixture.sent, isEmpty);
  });

  test('结算商品行或地址格式损坏时失败关闭，不能静默丢行或兜 id=0', () async {
    final brokenProduct = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'productList': <dynamic>['not-a-cart-row'],
          'address': null,
        },
      },
    );
    await expectLater(
      brokenProduct.api.previewSettlement(<int>[1]),
      throwsA(isA<FormatException>()),
    );

    final brokenAddress = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'productList': <dynamic>[],
          'address': <String, dynamic>{'id': 0, 'fullName': '无效地址'},
        },
      },
    );
    await expectLater(
      brokenAddress.api.previewSettlement(<int>[1]),
      throwsA(isA<FormatException>()),
    );

    final brokenCartIdentity = build(
      (_) => <String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'productList': <dynamic>[
            <String, dynamic>{
              'id': 0,
              'productId': 101,
              'skuId': 1001,
              'quantity': 1,
            },
          ],
          'address': null,
        },
      },
    );
    await expectLater(
      brokenCartIdentity.api.previewSettlement(<int>[1]),
      throwsA(isA<FormatException>()),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.onRequest);

  final Map<String, dynamic> Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(onRequest(options)),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
