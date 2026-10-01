import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_customer_detail_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_customer_detail_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
  });
  for (final message in <String?>[null, '请求失败', 'Server refused this request']) {
    test('Customer-detail provenance preserves present server message: $message', () async {
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      client.dio.httpClientAdapter = _Reply({'code': 400, if (message != null) 'msg': message});
      addTearDown(() => client.dio.close(force: true));
      await expectLater(MerchantCustomerDetailApi(client).detail(7), throwsA(
        isA<MerchantCustomerDetailApiException>()
          .having((e) => e.message, 'message', message ?? '请求失败')
          .having((e) => e.isLocalFallback, 'local provenance', message == null),
      ));
    });
  }
  for (final message in <String?>[null, '跟进备注已保存', 'Saved by server']) {
    test('Confirmed receipt preserves message provenance: $message', () async {
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      client.dio.httpClientAdapter = _Reply({'code': 200, 'data': <String, dynamic>{}, if (message != null) 'msg': message});
      addTearDown(() => client.dio.close(force: true));
      final receipt = await MerchantCustomerDetailApi(client).addNote(customerMemberId: 7,
        content: '原始备注', requestId: 'test-12345');
      expect(receipt.message, message ?? '跟进备注已保存');
      expect(receipt.isLocalFallback, message == null);
    });
  }
  test('Server data-string receipt is not marked as a local fallback', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.httpClientAdapter = _Reply({'code': 200, 'data': '跟进备注已保存'});
    addTearDown(() => client.dio.close(force: true));
    final receipt = await MerchantCustomerDetailApi(client).addNote(customerMemberId: 7,
      content: '原始备注', requestId: 'test-12345');
    expect(receipt.message, '跟进备注已保存');
    expect(receipt.isLocalFallback, isFalse);
  });
  testWidgets('English error presentation only translates explicitly local fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Column(children: [
        Text(merchantCustomerApiError(context, const MerchantCustomerDetailApiException('请求失败', isLocalFallback: true))),
        Text(merchantCustomerApiError(context, const MerchantCustomerDetailApiException('请求失败'))),
        Text(merchantCustomerApiError(context, const MerchantCustomerDetailApiException('Server refused this request'))),
        Text(merchantCustomerApiReceipt(context, const MerchantCustomerMutationReceipt(message: '跟进备注已保存', data: {}, isLocalFallback: true))),
        Text(merchantCustomerApiReceipt(context, const MerchantCustomerMutationReceipt(message: '跟进备注已保存', data: {}))),
      ])),
    ));
    expect(find.text('Request failed'), findsOneWidget);
    expect(find.text('请求失败'), findsOneWidget);
    expect(find.text('Server refused this request'), findsOneWidget);
    expect(find.text('Follow-up note saved'), findsOneWidget);
    expect(find.text('跟进备注已保存'), findsOneWidget);
  });
}
class _Reply implements HttpClientAdapter {
  _Reply(this.body);
  final Map<String, dynamic> body;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
    ResponseBody.fromString(jsonEncode(body), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}
