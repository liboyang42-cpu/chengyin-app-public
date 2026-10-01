import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/merchant_review_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_review_strings.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
  });
  for (final message in <String?>[null, '评价加载失败', 'Server refused this request']) {
    test('Review provenance preserves present server message: $message', () async {
      final client = DioClient(TokenStore(const FlutterSecureStorage()));
      client.dio.httpClientAdapter = _Reply({'code': 400, if (message != null) 'msg': message});
      addTearDown(() => client.dio.close(force: true));
      await expectLater(MerchantReviewApi(client).managePage(pageNum: 1, pageSize: 20), throwsA(
        isA<MerchantReviewApiException>()
          .having((e) => e.message, 'message', message ?? '评价加载失败')
          .having((e) => e.isLocalFallback, 'local provenance', message == null),
      ));
    });
  }
  testWidgets('English error presentation only translates explicitly local fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) => Column(children: [
        Text(merchantReviewErrorText(context, const MerchantReviewApiException('评价加载失败', isLocalFallback: true))),
        Text(merchantReviewErrorText(context, const MerchantReviewApiException('评价加载失败'))),
        Text(merchantReviewErrorText(context, const MerchantReviewApiException('Server refused this request'))),
      ])),
    ));
    expect(find.text('Unable to load reviews'), findsOneWidget);
    expect(find.text('评价加载失败'), findsOneWidget);
    expect(find.text('Server refused this request'), findsOneWidget);
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
