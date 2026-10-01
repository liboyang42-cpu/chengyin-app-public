import 'package:chengyin_app/l10n/app_localizations_en.dart';
import 'package:chengyin_app/l10n/error_presentation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final strings = AppLocalizationsEn();
  test('transport authentication is localized and server detail stays verbatim', () {
    const message = '  登录状态已失效，请重新登录  ';
    final options = RequestOptions(path: '/test');
    final result = presentError(DioException(requestOptions: options,
      response: Response(requestOptions: options, statusCode: 401, data: {'msg': message})), strings);
    expect(result.summary, strings.loginExpired);
    expect(result.detail, message);
    expect(result.detailLabel, strings.originalServerMessage);
  });
  test('business text mentioning token or timeout does not imply transport failure', () {
    const message = 'This token costs 401 points; timeout is a product name';
    final result = presentError(Exception(message), strings, originalApiMessage: message);
    expect(result.summary, strings.operationFailed);
    expect(result.detail, message);
    expect(result.detailLabel, strings.errorOriginalMessage);
  });
  test('typed network timeout uses resources and never exposes diagnostics', () {
    final result = presentError(DioException(requestOptions: RequestOptions(path: '/test'),
      type: DioExceptionType.receiveTimeout, message: 'private diagnostics'), strings);
    expect(result.summary, strings.networkError);
    expect(result.detail, isNull);
  });
  test('numeric business code is not interpreted as HTTP authentication status', () {
    final options = RequestOptions(path: '/test');
    final result = presentError(DioException(requestOptions: options,
      response: Response(requestOptions: options, statusCode: 400,
        data: {'code': 401, 'msg': '自定义业务拒绝'})), strings);
    expect(result.summary, strings.operationFailed);
    expect(result.detail, '自定义业务拒绝');
  });
}
